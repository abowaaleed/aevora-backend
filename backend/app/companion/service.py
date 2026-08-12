"""
CompanionService — "الصديق الدائم".

مساعد شخصي بذاكرة دائمة يحفظ ما يعرفه عن المستخدم (الاسم، الأهداف، الاهتمامات،
حقائق، مفردات، أخطاء إنجليزية مصحّحة) وسجل المحادثة والمهام. تُحفظ كل البيانات
محلياً في data/users/{uid}/companion وتُنسخ احتياطياً إلى السحابة (S3) لتدوم
عبر عمليات إعادة بناء الخادم.

يُشتق uid من مفاتيح المستخدم، لذا فالذاكرة مرتبطة بالمستخدم وليس بالجهاز:
نفس المفاتيح على أي جهاز = نفس الذاكرة والمحادثة.
"""

from __future__ import annotations

import asyncio
import json
import datetime
import re
import uuid
from pathlib import Path
from typing import Any, AsyncGenerator, Dict, List, Optional

from app.core.user_context import current_user_id
from app.rag.cloud_store import get_cloud_store
from app.services.smart_router import SmartRouter
from app.companion.models import (
    CompanionMessage,
    CompanionProfile,
    CompanionState,
    CompanionTask,
)

COMPANION_DIR_NAME = "companion"
MAX_HISTORY = 40
ANALYSIS_WINDOW = 12


def _now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def _local_date() -> str:
    return datetime.datetime.now().strftime("%Y-%m-%d")


def _new_task(text: str, due: Optional[str] = None) -> CompanionTask:
    return CompanionTask(
        id=f"t_{uuid.uuid4().hex[:8]}",
        text=text.strip(),
        due=due,
        created=_now(),
    )


class _Store:
    """تحميل/حفظ ملفات الذاكرة مع نسخة سحابية (أفضل جهد)."""

    def __init__(self, uid: str):
        self.uid = uid
        self.cloud = get_cloud_store()
        self.dir = Path(__file__).parent.parent.parent / "data" / "users" / uid / COMPANION_DIR_NAME
        self.dir.mkdir(parents=True, exist_ok=True)

    def _path(self, name: str) -> Path:
        return self.dir / name

    def _cloud_key(self, name: str) -> str:
        return f"users/{self.uid}/{COMPANION_DIR_NAME}/{name}"

    def load(self, name: str, default):
        path = self._path(name)
        if path.exists():
            try:
                return json.loads(path.read_text(encoding="utf-8"))
            except Exception as e:
                print(f"[COMPANION] load {name} parse error: {e}")
        if self.cloud.enabled and self.uid:
            try:
                data = self.cloud.download(self.uid, f"{COMPANION_DIR_NAME}/{name}")
                if data:
                    parsed = json.loads(data.decode("utf-8"))
                    path.write_text(json.dumps(parsed, ensure_ascii=False, indent=2), encoding="utf-8")
                    return parsed
            except Exception as e:
                print(f"[COMPANION] cloud load {name} error: {e}")
        return default

    def save(self, name: str, data) -> None:
        try:
            text = json.dumps(data, ensure_ascii=False, indent=2)
            self._path(name).write_text(text, encoding="utf-8")
            if self.cloud.enabled and self.uid:
                try:
                    self.cloud.upload(self.uid, f"{COMPANION_DIR_NAME}/{name}", text.encode("utf-8"))
                except Exception as e:
                    print(f"[COMPANION] cloud save {name} error: {e}")
        except Exception as e:
            print(f"[COMPANION] local save {name} error: {e}")

    def delete_all(self) -> None:
        try:
            for f in self.dir.glob("*.json"):
                f.unlink()
            if self.cloud.enabled and self.uid:
                for name in ["profile", "memories", "history", "tasks", "summary"]:
                    self.cloud.delete(self.uid, f"{COMPANION_DIR_NAME}/{name}")
        except Exception as e:
            print(f"[COMPANION] delete_all error: {e}")


class CompanionService:
    def __init__(self, uid: Optional[str] = None):
        self.uid = uid or current_user_id() or "anon"
        self._store = _Store(self.uid)
        self._router = SmartRouter()
        self._analysis_lock = asyncio.Lock()
        self._load_all()

    # ------------------------------------------------------------------ load
    def _load_all(self):
        now = _now()
        self.profile = CompanionProfile(**self._store.load("profile", {}))
        if not self.profile.created:
            self.profile.created = now
            self.profile.updated = now
        self.memories: List[str] = list(self._store.load("memories", []))
        self.tasks: List[CompanionTask] = [
            CompanionTask(**t) for t in self._store.load("tasks", [])
        ]
        self.history: List[CompanionMessage] = [
            CompanionMessage(**m) for m in self._store.load("history", [])
        ]
        self.summary: str = self._store.load("summary", "") or ""
        self._save_all()

    def _save_all(self):
        self.profile.updated = _now()
        self._store.save("profile", self.profile.model_dump())
        self._store.save("memories", self.memories)
        self._store.save("tasks", [t.model_dump() for t in self.tasks])
        self._store.save("history", [m.model_dump() for m in self.history])
        self._store.save("summary", self.summary)

    # ----------------------------------------------------------------- tasks
    def add_task(self, text: str, due: Optional[str] = None) -> CompanionTask:
        task = _new_task(text, due)
        self.tasks.append(task)
        self._save_all()
        return task

    def toggle_task(self, task_id: str) -> Optional[CompanionTask]:
        for t in self.tasks:
            if t.id == task_id:
                t.completed = not t.completed
                t.done_at = _now() if t.completed else None
                self._save_all()
                return t
        return None

    def delete_task(self, task_id: str) -> bool:
        before = len(self.tasks)
        self.tasks = [t for t in self.tasks if t.id != task_id]
        if len(self.tasks) != before:
            self._save_all()
            return True
        return False

    def _pending_tasks(self) -> List[CompanionTask]:
        return [t for t in self.tasks if not t.completed]

    # -------------------------------------------------------------- prompts
    def _build_system_prompt(self) -> str:
        p = self.profile
        lines = []
        if p.name:
            lines.append(f"- اسم المستخدم: {p.name}")
        if p.english_level:
            lines.append(f"- مستواه في الإنجليزية: {p.english_level}")
        if p.goals:
            lines.append(f"- أهدافه: {'، '.join(p.goals)}")
        if p.interests:
            lines.append(f"- اهتماماته: {'، '.join(p.interests)}")
        if p.known_facts:
            lines.append(f"- حقائق تعرفها عنه: {'، '.join(p.known_facts[-8:])}")
        if p.last_corrections:
            lines.append(f"- آخر أخطاء صُححت له: {'؛ '.join(p.last_corrections[-4:])}")
        if p.vocabulary:
            lines.append(f"- مفردات علّمته إياها: {'، '.join(p.vocabulary[-8:])}")
        if p.learning_stats:
            stats = ", ".join(f"{k}={v}" for k, v in list(p.learning_stats.items())[-5:])
            lines.append(f"- إحصائيات التعلم: {stats}")
        profile_block = "\n".join(lines) if lines else "لا تعرف عنه شيئاً بعد — ابدأ بتكوين علاقة."

        pending = self._pending_tasks()
        tasks_block = (
            "؛ ".join(f"«{t.text}»{' (مستحقة: ' + t.due + ')' if t.due else ''}" for t in pending)
            if pending
            else "لا توجد مهام معلقة."
        )

        recent = self.history[-10:]
        recent_block = "\n".join(
            f"{'المستخدم' if m.role == 'user' else 'ايفورا'}: {m.text[:300]}" for m in recent
        ) or "لا يوجد حديث بعد."

        summary_block = self.summary or "لا يوجد ملخّص مسبق للمحادثات القديمة."

        return (
            "أنت «إيفورا»، صديق المستخدم الدائم ومساعده الشخصي الذكي. "
            "أنت رفيق يعرفه عن قرب، يتذكر تفاصيل حياته، ويبادر بالاهتمام به.\n\n"
            "قواعد شخصيتك وسلوكك:\n"
            "1. الدفء والصدق: تحدث كصديق مقرّب يهتم حقاً، لا كآلة. استخدم لغة عربية طبيعية دافئة، "
            "وخاطب المستخدم باسمه إن عرفته.\n"
            "2. الذاكرة الدائمة: استعمل ما تعرفه عنه من الملف الشخصي والملخص والمحادثة السابقة. "
            "استرجِع أحداثاً قالها سابقاً («ذكرت لي الأسبوع الماضي أن...») — لا تختلق أي ذكرى.\n"
            "3. تعليم الإنجليزية: صوّب أخطاءه الإنجليزية بلطف ودون إحراج: اذكر الخطأ، ثم الصحيح، ثم القاعدة بجملة "
            "واحدة، وأضف كلمة أو تعبيراً مفيداً. شجّعه على التحدث بالإنجليزية قليلاً في كل جلسة.\n"
            "4. تذكيره بالمهام: إن كانت هناك مهام معلقة فذكّره بها وساعده على تنظيمها وتقسيمها.\n"
            "5. تحليل السلوك بلطف: لاحظ أنماطه (مثلاً: يدرس ليلاً، يحب كرة القدم، يسعى لوظيفة) وعلّق عليها "
            "بحرارة. لا تتحليل ممل أو مطوّل.\n"
            "6. المبادرة: اقترح موضوعاً أو سؤالاً يومياً، وأسئلة باللغة الإنجليزية لممارسة.\n"
            "7. الإيجاز: اجعل ردك مركّزاً (3-6 أسطر عادة)، ما لم يطلب التفصيل.\n"
            "8. حدود: لا تدّعِ أنك إنسان، لا تختلق حقائق أو ذكريات، وقل إنك غير متأكد إن لم تعرف شيئاً.\n\n"
            "=== ما تعرفه عن المستخدم ===\n"
            f"{profile_block}\n\n"
            "=== ملخص المحادثات السابقة ===\n"
            f"{summary_block}\n\n"
            "=== المهام المعلقة ===\n"
            f"{tasks_block}\n\n"
            "=== آخر محادثة ===\n"
            f"{recent_block}"
        )

    # ------------------------------------------------------------ analysis
    def _analysis_prompt(self, window: List[CompanionMessage]) -> str:
        convo = "\n".join(
            f"{'المستخدم' if m.role == 'user' else 'ايفورا'}: {m.text[:500]}" for m in window
        )
        return (
            "اقرأ هذه المحادثة مع مستخدم يتعلم الإنجليزية. استخرج منه معلومات وأعدها كـ JSON فقط "
            "(بدون أي نص خارج الكائن)، بهذه البنية الحرفية — القيم المثال للإيضاح فقط:\n"
            '{\n'
            '  "name": "مثال: محمد",\n'
            '  "english_level": "مثال: مبتدئ",\n'
            '  "goals": ["مثال: أجد وظيفة في الخارج"],\n'
            '  "interests": ["مثال: كرة القدم"],\n'
            '  "new_facts": ["مثال: يسكن في الرياض"],\n'
            '  "new_tasks": [{"text": "مثال: حل واجب اللغة", "due": "2026-08-15"}],\n'
            '  "corrections": [{"mistake": "جملته الخاطئة", "correct": "الجملة الصحيحة", "rule": "القاعدة باختصار"}],\n'
            '  "vocabulary": ["مثال: unforgettable"]\n'
            "}\n"
            "قواعد صارمة: لا تخترع شيئاً غير وارد في المحادثة. القيم غير المعروفة تكون null أو مصفوفات فارغة. "
            "التاريخ بصيغة YYYY-MM-DD أو null.\n\n"
            "المحادثة:\n" + convo
        )

    def _merge_analysis(self, parsed: dict) -> None:
        now = _now()
        if isinstance(parsed, dict):
            name = parsed.get("name")
            if isinstance(name, str) and name.strip() and not self.profile.name:
                self.profile.name = name.strip()

            level = parsed.get("english_level")
            if isinstance(level, str) and level.strip() and not self.profile.english_level:
                self.profile.english_level = level.strip()

            for key, attr in (("goals", "goals"), ("interests", "interests")):
                vals = parsed.get(key)
                if isinstance(vals, list):
                    for v in vals:
                        v = str(v).strip()
                        if v and v not in getattr(self.profile, attr):
                            getattr(self.profile, attr).append(v)

            facts = parsed.get("new_facts")
            if isinstance(facts, list):
                for f in facts:
                    f = str(f).strip()
                    if f and f not in self.memories:
                        self.memories.append(f)

            vocab = parsed.get("vocabulary")
            if isinstance(vocab, list):
                for v in vocab:
                    v = str(v).strip()
                    if v and v not in self.profile.vocabulary:
                        self.profile.vocabulary.append(v)

            corr = parsed.get("corrections")
            if isinstance(corr, list):
                for c in corr:
                    if isinstance(c, dict) and c.get("correct"):
                        entry = f"{c.get('mistake','')} ← {c['correct']} ({c.get('rule','')})"
                        if entry not in self.profile.last_corrections:
                            self.profile.last_corrections.append(entry)

            tasks = parsed.get("new_tasks")
            if isinstance(tasks, list):
                for t in tasks:
                    if isinstance(t, dict) and t.get("text"):
                        self.add_task(str(t["text"]), t.get("due"))

            stats = self.profile.learning_stats
            stats["corrections_count"] = len(self.profile.last_corrections)
            stats["vocabulary_count"] = len(self.profile.vocabulary)
            stats["memories_count"] = len(self.memories)
            stats["last_analysis"] = now
            self.profile.learning_stats = stats

        # لفّ المحادثات القديمة في ملخص موجز عند بلوغ الحد
        if len(self.history) > MAX_HISTORY:
            self._roll_summary()
        self._save_all()

    def _roll_summary(self) -> None:
        """اختزال جزء من التاريخ إلى ملخص نصي قصير (يقتطع الأقدم)."""
        overflow = self.history[: len(self.history) - MAX_HISTORY]
        if overflow:
            old = self.summary
            tail = " | ".join(m.text[:200] for m in overflow[-12:])
            self.summary = f"{old} — سابقاً: {tail}"[-1500:]
            self.history = self.history[-MAX_HISTORY:]

    def _generate(self, prompt: str, max_tokens: int = 800) -> str:
        """توليد نص كامل: Gemini أولاً ثم Groq احتياطاً (مثل بقية الأجزاء)."""
        from app.usage.service import record_provider_usage
        last_err = None
        try:
            out = self._router.gemini.service.generate_content_sync(prompt)
            record_provider_usage("gemini", self.uid)
            return out
        except Exception as e:
            last_err = e
        if self._router.groq.available:
            try:
                out = self._router.groq.generate(prompt, num_predict=max_tokens)
                record_provider_usage("groq", self.uid)
                return out
            except Exception as e:
                last_err = e
        raise RuntimeError(f"لا يتوفر نموذج للتحليل: {last_err}")

    @staticmethod
    def _extract_json(text: str) -> Optional[dict]:
        if not text:
            return None
        cleaned = text.strip()
        if cleaned.startswith("```"):
            cleaned = re.sub(r"^```[a-zA-Z]*\n?", "", cleaned)
            cleaned = re.sub(r"\n?```$", "", cleaned)
        try:
            return json.loads(cleaned)
        except json.JSONDecodeError:
            pass
        match = re.search(r"\{[\s\S]*\}", cleaned)
        if match:
            try:
                return json.loads(match.group(0))
            except json.JSONDecodeError:
                pass
        return None

    def analyze(self) -> None:
        """تحليل سلوكي لفهم المستخدم وتحديث الذاكرة (يعمل في الخلفية)."""
        window = self.history[-ANALYSIS_WINDOW:]
        if len(window) < 2:
            return
        if self._analysis_lock.locked():
            return
        try:
            prompt = self._analysis_prompt(window)
            raw = self._generate(prompt, max_tokens=900)
            parsed = self._extract_json(raw)
            if parsed is not None:
                self._merge_analysis(parsed)
        except Exception as e:
            print(f"[COMPANION] analysis failed: {e}")

    async def run_analysis_async(self) -> None:
        try:
            await asyncio.to_thread(self.analyze)
        except Exception as e:
            print(f"[COMPANION] async analysis error: {e}")

    # --------------------------------------------------------------- chat
    async def chat(self, message: str) -> AsyncGenerator[str, None]:
        try:
            from app.usage.service import get_usage_service
            get_usage_service(self.uid).record_event("companion_messages")
        except Exception as e:
            print(f"[COMPANION] usage event error: {e}")
        # قمع المبادرة بعد أي تفاعل بالمحادثة
        self.profile.last_proactive_shown = _now()
        self.history.append(CompanionMessage(role="user", text=message.strip(), ts=_now()))
        system = self._build_system_prompt()
        full = ""
        try:
            async for chunk in self._router.stream(message, system_instruction=system):
                full += chunk
                yield chunk
        finally:
            if not full.strip():
                full = "عذراً، واجهت خطأً في الاتصال. حاول مجدداً."
            self.history.append(CompanionMessage(role="assistant", text=full.strip(), ts=_now()))
            self._save_all()
            if len(self.history) % 3 == 0:
                asyncio.get_event_loop().create_task(self.run_analysis_async())

    # ------------------------------------------------------------ proactive
    def proactive(self) -> tuple[Optional[str], Optional[str]]:
        """رسالة مبادرة: تذكير بالمهام، أو تحية اليوم، أو تفاعل بعد غياب.
        لا يُعرض مرة ثانية إذا عُرض خلال آخر 12 ساعة (حتى لا يزعج)."""
        # قمع التكرار: لا تُظهر المبادرة إذا عُرضت خلال آخر 12 ساعة
        last_shown = self.profile.last_proactive_shown
        if last_shown:
            try:
                last_dt = datetime.datetime.fromisoformat(last_shown)
                elapsed = datetime.datetime.now(datetime.timezone.utc) - last_dt
                if elapsed.total_seconds() < 12 * 3600:
                    return None, None
            except Exception:
                pass

        pending = self._pending_tasks()
        last_ts = self.history[-1].ts if self.history else None

        if pending:
            first = pending[0]
            due_hint = f" والمستحقة {first.due}" if first.due else ""
            msg = f"عندك مهمة معلقة: «{first.text}»{due_hint}. تريد أن نبدأ بها الآن؟"
            self.profile.last_proactive_shown = _now()
            self._save_all()
            return msg, "ذكرني بمهامي وابدأ معي بأهمها"

        now = datetime.datetime.now()
        hour = now.hour
        if hour < 12:
            time_text = "صباح الخير"
        elif hour < 17:
            time_text = "مساء الخير"
        else:
            time_text = "مساءً"
        if last_ts:
            try:
                last = datetime.datetime.fromisoformat(last_ts)
                if last.date() != now.date():
                    msg = f"{time_text} 👋 اشتقت إليك منذ الأمس. كيف حالك اليوم؟"
                    self.profile.last_proactive_shown = _now()
                    self._save_all()
                    return msg, "حدثني عن يومك"
            except Exception:
                pass

        # لا تُظهر تحية وقتية إذا سبق تفاعل اليوم
        return None, None

    def acknowledge_proactive(self) -> None:
        """تسجيل أن المستخدم فعّل/رأى بطاقة المبادرة."""
        self.profile.last_proactive_shown = _now()
        self._save_all()

    # ----------------------------------------------------------------- state
    def get_state(self) -> CompanionState:
        msg, prompt = self.proactive()
        return CompanionState(
            profile=self.profile,
            memories=list(self.memories[-30:]),
            tasks=list(self.tasks),
            recent=list(self.history[-MAX_HISTORY:]),
            summary=self.summary or None,
            proactive=msg,
            suggested_prompt=prompt,
        )

    def reset(self) -> None:
        self._store.delete_all()
        now = _now()
        self.profile = CompanionProfile(created=now, updated=now)
        self.memories = []
        self.tasks = []
        self.history = []
        self.summary = ""
        self._save_all()


_services: Dict[str, CompanionService] = {}


def get_companion_service(uid: Optional[str] = None) -> CompanionService:
    key = uid or current_user_id() or "anon"
    if key not in _services:
        _services[key] = CompanionService(uid=key)
    return _services[key]
