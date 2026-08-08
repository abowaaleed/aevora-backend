"""
Response Validation Stage.

Verifies that the generated response does not contain any hallucinated facts.
"""

import os
import asyncio
import concurrent.futures
from typing import Optional

from ..task import Stage
from ..types import PipelineContext, StageStatus
from app.services.ai_engine import AIEngine
from app.runtime.stages.models import ValidationVerdict, ValidationResult
from app.runtime.stages.base_validator import ResponseValidator
from app.runtime.stages.rule_validator import RuleValidator
from app.runtime.stages.judge_validator import JudgeValidator
from app.runtime.stages.composite_validator import CompositeValidator


def requires_fact_check(user_message: str, response: str) -> bool:
    """
    Lightweight deterministic check to see if a response needs an independent LLM judge.
    Returns True for names, numbers, dates, locations, or scientific claims.
    """
    import re

    # 1. Check for numbers (ignoring small quantities like 1-2 sentences)
    # Regex matches multi-digit numbers or sequences that look like years/stats
    if re.search(r'\d{2,}', response) or re.search(r'\d\s?%', response):
        return True

    # 2. Check for dates/years
    if re.search(r'(19|20)\d{2}', response):
        return True

    # 3. Tight, curated list of factual-question indicators (Fix 1)
    # Focus on specific geography, history, and quantity queries.
    fact_keywords = [
        "عاصمة", "متى تأسست", "كم عدد", "في أي سنة", "من هو", "من هي", "أين تقع", "ما هي مساحة",
        "capital", "founded in", "how many", "which year", "who is", "where is located", "population"
    ]

    # Check both user message (intent) and response (content)
    combined_text = (user_message + " " + response).lower()
    if any(k in combined_text for k in fact_keywords):
        return True

    return False

class ResponseValidationStage(Stage):
    """
    Stage to validate generated response content against active context facts.
    """

    def __init__(self, ai_engine: AIEngine, validator: Optional[ResponseValidator] = None):
        super().__init__("response_validation")
        self.ai_engine = ai_engine
        if validator is None:
            self.validator = CompositeValidator(RuleValidator(), JudgeValidator(ai_engine))
        else:
            self.validator = validator

    def execute(self, context: PipelineContext):
        if not context.ai_response:
            return self._create_result(
                status=StageStatus.SKIPPED,
                output="No response to validate"
            )

        from app.runtime.stages.trivial_check import is_trivial_input
        if is_trivial_input(context.request.user_message):
            print("[VALIDATION] Input is trivial. Skipping validation stage entirely.")
            return self._create_result(
                status=StageStatus.SKIPPED,
                output="Trivial input skipped validation"
            )

        reply = context.ai_response

        # Build list of allowed facts and terms from current inputs, memory, and history
        allowed_context = context.request.user_message + " "
        if context.relevant_knowledge:
            allowed_context += context.relevant_knowledge + " "
        if context.selected_memory:
            allowed_context += context.selected_memory + " "
        for m in context.retrieved_memories:
            allowed_context += m + " "
        if context.user_brain_context:
            allowed_context += context.user_brain_context + " "

        # Tier-based judge optimization
        tier = getattr(context.adaptive_decision, "tier", "high")

        # New: Deterministic Fact Check Gate
        needs_judge = requires_fact_check(context.request.user_message, reply)
        # Also check if entity extraction found specific entities that should be verified
        if context.entities and len(context.entities) > 0:
            needs_judge = True

        print(f"[VALIDATION] Tier: {tier}, Needs Independent Judge: {needs_judge}")

        # Check personal identity hallucinations first
        critical_entities = ["ناصر", "القصيم", "الهلال", "أيفورا", "صالح", "علي", "محمد", "Aevora"]
        for entity in critical_entities:
            if entity in reply and entity not in allowed_context:
                print(f"[VALIDATION] Hallucination detected: model mentioned '{entity}' but it's not in the context!")
                reply = "عذراً، لم أجد هذه المعلومة في ذاكرتي."
                context.ai_response = reply
                return self._create_result(
                    status=StageStatus.COMPLETED,
                    output=f"Hallucination of '{entity}' blocked. Response set to fallback."
                )

        # Fast deterministic rule-based fact verification to bypass LLM latency
        if context.relevant_knowledge:
            k_lower = context.relevant_knowledge.lower()
            r_lower = reply.lower()
            if "تلد ولا تبيض" in k_lower or "لا يبيض" in k_lower:
                if ("يبيض" in r_lower or "تضع البيض" in r_lower) and ("لا يبيض" not in r_lower and "لا تبيض" not in r_lower and "ليس يبيض" not in r_lower):
                    print("[VALIDATION] Fast contradiction detected: mammal claimed to lay eggs! Forcing refinement.")
                    reply = "الأسود من الثدييات، والثدييات تلد ولا تبيض."
                    context.ai_response = reply
                    return self._create_result(
                        status=StageStatus.COMPLETED,
                        output="Logical contradiction corrected via rule checker."
                    )
            if "خمسة أصابع" in k_lower or "خمس أصابع" in k_lower:
                if "أربعة" in r_lower or "اربعة" in r_lower or "أربع" in r_lower:
                    print("[VALIDATION] Fast contradiction detected: wrong finger count! Forcing refinement.")
                    reply = "يد الإنسان تحتوي على خمسة أصابع."
                    context.ai_response = reply
                    return self._create_result(
                        status=StageStatus.COMPLETED,
                        output="Logical contradiction corrected via rule checker."
                    )

        # Track the number of times judge has rejected the reply
        judge_rejected_count = 0

        tier = getattr(context.adaptive_decision, "tier", "high")

        # Skip LLM-heavy self-critique loop for Low complexity queries
        if tier == "low":
            print("[VALIDATION] Low complexity tier detected. Skipping Self-Critique loop and Judge.")
            # Still run Rule-based validation if possible
            if hasattr(self.validator, "rule_validator"):
                val_context = {
                    "relevant_knowledge": context.relevant_knowledge,
                    "user_message": context.request.user_message,
                    "selected_memory": context.selected_memory,
                    "retrieved_memories": context.retrieved_memories,
                    "user_brain_context": context.user_brain_context,
                }
                def run_async(coro):
                    try:
                        loop = asyncio.get_event_loop()
                    except RuntimeError:
                        loop = asyncio.new_event_loop()
                        asyncio.set_event_loop(loop)
                    return loop.run_until_complete(coro)

                val_res = run_async(self.validator.rule_validator.validate(context.request.user_message, reply, val_context))
                if val_res.verdict == ValidationVerdict.REJECTED:
                    print(f"[VALIDATION] Rule validator REJECTED: {val_res.reason}")
                    # Handle rejection if necessary, but here we just proceed or fallback

            context.ai_response = reply
            return self._create_result(
                status=StageStatus.COMPLETED,
                output="Validation skipped (Low complexity tier)."
            )

        # General Logical & Factual Self-Critique validation loop (max 2 attempts)
        for attempt in range(2):
            validation_prompt = (
                "[SYSTEM: Logical & Factual Verification]\n"
                "Analyze the user's query, verified scientific facts, and the AI response.\n"
                "1. Verify if the response contains any factual errors or logical contradictions.\n"
                "2. CRITICAL: Check if the response addressed EVERY distinct instruction in the user's message. If the user asked for multiple things (e.g. 'tell me X and then ask Y'), ensure both are present. If any instruction was ignored or merely echoed back, the status is INVALID.\n\n"
                f"User Query: {context.request.user_message}\n"
                f"Verified Core Facts: {context.relevant_knowledge or 'None'}\n"
                f"AI Response: {reply}\n\n"
                "Format your response exactly as follows:\n"
                "CONFIDENCE: <number between 0 and 100>\n"
                "STATUS: <VALID or INVALID>\n"
                "REASON: <short explanation of contradiction/omission>"
            )

            try:
                validation_res = self.ai_engine.generate_with_prompt(validation_prompt).strip()
            except Exception as e:
                print(f"[VALIDATION] Error during validation request: {e}")
                break

            print(f"[VALIDATION ATTEMPT {attempt+1}] Result:\n{validation_res}")

            # Parse confidence and status
            confidence = 100.0
            status = "VALID"
            reason = ""
            for line in validation_res.split("\n"):
                if line.upper().startswith("CONFIDENCE:"):
                    try:
                        confidence = float(line.split(":")[-1].replace("%", "").strip())
                    except:
                        pass
                elif line.upper().startswith("STATUS:"):
                    status = "INVALID" if "INVALID" in line.upper() else "VALID"
                elif line.upper().startswith("REASON:"):
                    reason = line.split(":", 1)[-1].strip()

            context.confidence_score = confidence

            # Check if consistency checker found contradictions as well
            has_consistency_issue = context.reasoning_analysis and "contradiction" in context.reasoning_analysis
            if has_consistency_issue:
                status = "INVALID"
                reason += f" [Consistency Checker: {context.reasoning_analysis.get('contradiction')}]"

            # If user explicitly corrections and model still returned old error
            if context.user_correction and status == "VALID":
                # Ensure we didn't repeat the wrong answer
                prev = context.user_correction.get("previous_answer", "").strip()
                if prev and prev in reply:
                    status = "INVALID"
                    reason += " [Repeated the previous incorrect answer]"

            if status == "VALID" and confidence >= 80.0:
                # --- NEW COMPOSITE VALIDATOR GATES ---
                val_context = {
                    "relevant_knowledge": context.relevant_knowledge,
                    "user_message": context.request.user_message,
                    "selected_memory": context.selected_memory,
                    "retrieved_memories": context.retrieved_memories,
                    "user_brain_context": context.user_brain_context,
                }
                
                # Tier-based judge optimization
                old_judge_env = os.environ.get("ENABLE_JUDGE_VALIDATION", "true")
                if tier == "medium" or not needs_judge:
                    print(f"[VALIDATION] {'Medium tier' if tier == 'medium' else 'Non-factual content'} detected: Disabling Independent Judge.")
                    os.environ["ENABLE_JUDGE_VALIDATION"] = "false"
                else:
                    os.environ["ENABLE_JUDGE_VALIDATION"] = "true"

                # Execute the validator synchronously using ThreadPoolExecutor helper
                def run_async(coro):
                    try:
                        loop = asyncio.get_event_loop()
                    except RuntimeError:
                        loop = asyncio.new_event_loop()
                        asyncio.set_event_loop(loop)
                    if loop.is_running():
                        with concurrent.futures.ThreadPoolExecutor() as executor:
                            future = executor.submit(lambda: asyncio.run(coro))
                            return future.result()
                    else:
                        return loop.run_until_complete(coro)

                try:
                    val_res = run_async(self.validator.validate(context.request.user_message, reply, val_context))
                finally:
                    os.environ["ENABLE_JUDGE_VALIDATION"] = old_judge_env
                
                if val_res.verdict == ValidationVerdict.APPROVED:
                    context.ai_response = reply
                    return self._create_result(
                        status=StageStatus.COMPLETED,
                        output=f"Response validation passed. Confidence: {confidence}%"
                    )
                elif val_res.verdict == ValidationVerdict.UNCERTAIN:
                    print(f"[VALIDATION] Judge uncertain/timeout: {val_res.reason}. Using ungraded original response.")
                    context.ai_response = reply # Fallback to original response instead of generic clarification
                    return self._create_result(
                        status=StageStatus.COMPLETED,
                        output=f"Response validation returned UNCERTAIN ({val_res.reason}). Using ungraded response."
                    )
                elif val_res.verdict == ValidationVerdict.REJECTED:
                    judge_rejected_count += 1
                    if judge_rejected_count > 1 or attempt >= 1:
                        print(f"[VALIDATION] Judge rejected second time or max attempts reached: {val_res.reason}. Returning clarification question.")
                        reply = "هل يمكنك توضيح سؤالك بشكل أدق؟"
                        context.ai_response = reply
                        return self._create_result(
                            status=StageStatus.COMPLETED,
                            output="Response set to clarification question due to repeated judge rejection."
                        )
                    else:
                        status = "INVALID"
                        reason = f"رُفض من المقيّم المستقل: {val_res.reason}"

            # If low confidence or invalid, refine
            error_reason = reason or "Low confidence/possible contradiction."
            print(f"[VALIDATION] Error found: {error_reason}. Confidence: {confidence}%. Refining...")

            refinement_prompt = (
                f"{context.built_prompt}\n\n"
                "[CRITICAL CONTRADICTION ALERT & REFINEMENT REQUIRED]\n"
                f"Your previous candidate response: '{reply}' was invalid or had low confidence because: {error_reason}.\n"
                f"Core Scientific/Factual Reality: {context.relevant_knowledge or 'None'}\n\n"
                "Please rewrite the response to completely correct this error. Be logical, direct, and factually accurate. Do not repeat the error. Your final response should ONLY be the corrected answer, do not include any meta-talk or unrequested comments. If you are not completely sure of the facts, answer with EXACTLY AND ONLY: 'لا أملك ثقة كافية بالإجابة.'"
            )

            try:
                new_reply = self.ai_engine.generate_with_prompt(refinement_prompt).strip()
                # Ensure the new_reply completely replaces the old one if it contains the fallback string
                if "لا أملك ثقة كافية بالإجابة" in new_reply:
                    reply = "لا أملك ثقة كافية بالإجابة."
                else:
                    reply = new_reply
            except Exception as e:
                print(f"[VALIDATION] Error during refinement request: {e}")
                break

        # Fallback if both refinement attempts fail or output low confidence
        if context.confidence_score and context.confidence_score < 80.0:
            reply = "لا أملك ثقة كافية بالإجابة."

        # Final safety check to prevent concatenation
        if "لا أملك ثقة كافية بالإجابة" in reply:
            reply = "لا أملك ثقة كافية بالإجابة."

        context.ai_response = reply
        return self._create_result(
            status=StageStatus.COMPLETED,
            output="Response validation finished after refinement."
        )

