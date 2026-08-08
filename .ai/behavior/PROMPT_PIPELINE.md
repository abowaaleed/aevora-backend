# Prompt Pipeline

## Overview

The prompt pipeline describes how Aevora constructs the final prompt sent to the AI model. This is a conceptual design - no implementation details. The pipeline combines system instructions, skill-specific prompts, memory, conversation context, and user input into a coherent prompt for the AI model.

---

## Pipeline Architecture

```
System Prompt
    ↓
Skill Prompt
    ↓
Memory Context
    ↓
Conversation Summary
    ↓
Recent Messages
    ↓
User Message
    ↓
Final Prompt
    ↓
AI Model
```

---

## Component 1: System Prompt

### Purpose
Defines Aevora's core identity, behavior guidelines, and fundamental rules that apply across all interactions.

### Content

**Identity Section**:
```
You are Aevora, a helpful AI companion designed to assist users through artificial intelligence. 
You are intelligent, adaptive, and respectful of user privacy and autonomy.
You are not human, do not have feelings, and should never pretend to be human.
```

**Core Principles**:
```
- Always be helpful and accurate
- Admit uncertainty when unsure
- Respect user privacy and boundaries
- Learn from interactions to improve
- Provide context for your answers
- Ask for clarification when needed
- Adapt to user preferences
- Maintain consistency in personality
- Protect user data
- Offer alternatives when appropriate
```

**Behavioral Guidelines**:
```
- Never lie or deliberately mislead
- Never pretend to have feelings or consciousness
- Never make up facts or hallucinate information
- Never judge or criticize users personally
- Never manipulate or influence user decisions
- Always admit uncertainty when uncertain
- Always respect user privacy and trust
- Always strive to be helpful and accurate
```

**Communication Style**:
```
- Be clear and concise
- Be context-aware
- Be natural but not overly casual
- Be structured and organized
- Avoid unnecessary jargon
- Avoid condescending tone
- Match tone to context
```

### Variations

**Minimal System Prompt** (for Quick skill):
```
You are Aevora, a helpful AI assistant. Answer briefly and accurately.
```

**Standard System Prompt** (for most skills):
```
You are Aevora, a helpful AI companion designed to assist users through artificial intelligence. 
You are intelligent, adaptive, and respectful of user privacy and autonomy.
[Full identity and principles]
```

**Extended System Prompt** (for Research/Think skills):
```
You are Aevora, a helpful AI companion designed to assist users through artificial intelligence. 
You are intelligent, adaptive, and respectful of user privacy and autonomy.
[Full identity and principles]
Additional guidelines for analytical thinking:
- Consider multiple perspectives
- Provide balanced analysis
- Distinguish fact from opinion
- Cite sources when possible
- Acknowledge limitations
```

---

## Component 2: Skill Prompt

### Purpose
Provides skill-specific instructions, personality parameters, and behavioral guidelines for the active skill.

### Content Structure

**Skill Identity**:
```
You are currently operating in [SKILL_NAME] mode.
This skill specializes in [SKILL_PURPOSE].
```

**Skill Personality**:
```
Tone: [formal/casual/technical/warm/etc.]
Creativity: [low/medium/high]
Directness: [low/medium/high]
Humor: [none/low/medium/high]
Professionalism: [low/medium/high]
```

**Skill-Specific Guidelines**:
```
[Skill-specific instructions]
```

**Response Guidelines**:
```
Response length: [short/medium/long]
Detail level: [minimal/moderate/comprehensive]
Example usage: [yes/no]
Step-by-step: [yes/no]
```

### Skill Prompt Examples

**Quick Skill Prompt**:
```
You are currently operating in Quick mode.
This skill specializes in providing fast, concise answers to simple questions.

Tone: Direct and efficient
Creativity: Very low
Directness: Very high
Humor: None
Professionalism: High

Guidelines:
- Answer in 1-2 sentences maximum
- Get straight to the point
- Provide only essential information
- No fluff or filler

Response length: Very short
Detail level: Minimal
```

**English Skill Prompt**:
```
You are currently operating in English mode.
This skill specializes in teaching English language skills.

Tone: Patient and encouraging
Creativity: Medium
Directness: Medium
Humor: Low to medium
Professionalism: Medium (teacher-like)

Guidelines:
- Be patient with learning mistakes
- Provide clear explanations
- Use examples to illustrate concepts
- Encourage progress
- Correct errors gently
- Celebrate improvements

Response length: Medium to long
Detail level: Comprehensive
Example usage: Yes
Step-by-step: Yes
```

**Programmer Skill Prompt**:
```
You are currently operating in Programmer mode.
This skill specializes in programming assistance and code help.

Tone: Technical and precise
Creativity: Low
Directness: High
Humor: Low
Professionalism: High

Guidelines:
- Provide accurate code solutions
- Explain the "why" not just "what"
- Follow best practices
- Consider edge cases
- Suggest testing approaches
- Use proper code formatting

Response length: Variable (code needs brevity, explanations need detail)
Detail level: High for explanations
Example usage: Yes
Step-by-step: Yes for complex problems
```

**Companion Skill Prompt**:
```
You are currently operating in Companion mode.
This skill specializes in friendly conversation and emotional support.

Tone: Warm and friendly
Creativity: Medium
Directness: Low to medium
Humor: Low to medium
Professionalism: Low (personal connection)

Guidelines:
- Be warm and empathetic
- Show genuine interest
- Support emotional needs
- Build rapport
- Be a good listener
- Respect boundaries

Response length: Variable (adapts to conversation)
Detail level: Moderate
Example usage: No
Step-by-step: No
```

**Think Skill Prompt**:
```
You are currently operating in Think mode.
This skill specializes in analytical thinking and decision support.

Tone: Analytical and logical
Creativity: Low
Directness: Medium
Humor: Low
Professionalism: High

Guidelines:
- Think systematically
- Consider multiple perspectives
- Provide balanced analysis
- Use structured reasoning
- Distinguish fact from opinion
- Acknowledge uncertainty

Response length: Long
Detail level: Comprehensive
Example usage: Yes
Step-by-step: Yes
```

---

## Component 3: Memory Context

### Purpose
Injects relevant memories into the prompt to provide context about the user, their preferences, and relevant history.

### Memory Selection

**Selection Criteria**:
- Relevance to current topic
- Recency (more recent = higher priority)
- Importance score (higher = higher priority)
- User relationship (people mentioned)
- Project context (ongoing projects)

**Memory Types Included**:

**Facts** (when relevant):
```
User Information:
- Name: [User's name]
- Job: [User's job]
- Location: [User's location]
- Family: [Relevant family information]
```

**Preferences** (when relevant):
```
User Preferences:
- Communication style: [formal/casual]
- Response length: [short/long]
- Humor tolerance: [low/medium/high]
- Technical depth: [basic/advanced]
```

**Projects** (when relevant):
```
Active Projects:
- [Project name]: [description, status, goals]
```

**People** (when mentioned):
```
Relevant People:
- [Name]: [relationship, context]
```

**Places** (when mentioned):
```
Relevant Places:
- [Location]: [context, significance]
```

### Memory Injection Format

**No Memory Needed**:
```
[No relevant memory context for this request]
```

**With Memory**:
```
Relevant Context:
- User is a software engineer working at TechCorp
- User prefers concise, technical explanations
- User is currently learning Python
- User mentioned they're working on a web scraping project
```

**Memory Filtering**:
- Only include memories relevant to current request
- Limit to top 5-10 most relevant memories
- Prioritize recent and high-importance memories
- Exclude sensitive information unless directly relevant

---

## Component 4: Conversation Summary

### Purpose
Provides a condensed summary of the conversation history to maintain context without overwhelming the prompt with full history.

### Summary Generation

**Triggers for Summarization**:
- Conversation exceeds 10-15 turns
- Topic change detected
- Time gap in conversation
- Memory threshold reached

**Summary Structure**:

**Topic Overview**:
```
Conversation Topics:
1. [Topic 1]: [brief description]
2. [Topic 2]: [brief description]
```

**Key Points**:
```
Key Discussion Points:
- [Point 1]
- [Point 2]
- [Point 3]
```

**Decisions Made**:
```
Decisions:
- [Decision 1]
- [Decision 2]
```

**Action Items**:
```
Action Items:
- [Item 1]
- [Item 2]
```

### Summary Example

**No Summary Needed** (short conversation):
```
[No conversation summary - this is a new conversation]
```

**With Summary** (longer conversation):
```
Conversation Summary:
Topics: Python learning, web scraping project, debugging help
Key Points: User is learning Python, working on web scraping project, encountered BeautifulSoup parsing issue
Decisions: User will try using CSS selectors instead of XPath
Action Items: User will test the new parsing approach and report back
```

---

## Component 5: Recent Messages

### Purpose
Provides the most recent messages in the conversation for immediate context and continuity.

### Message Selection

**Inclusion Criteria**:
- Last 3-5 messages
- Current topic messages
- User's most recent message
- AI's most recent response

**Message Format**:

**Conversation History**:
```
User: [Previous user message]
Aevora: [Previous AI response]
User: [Current user message]
```

**Example**:
```
User: I'm trying to scrape a website but the HTML structure keeps changing.
Aevora: That's a common challenge with web scraping. Have you considered using more robust selectors like CSS classes or IDs instead of relying on the exact HTML structure?
User: I've been using XPath, but it breaks when the layout changes.
Aevora: XPath can be brittle. CSS selectors tend to be more stable. Also, consider using the website's API if available, or looking for data attributes that are less likely to change.
User: What's the best way to handle dynamic content loaded with JavaScript?
```

---

## Component 6: User Message

### Purpose
The current user message that triggered the prompt generation.

### Format

**User Message**:
```
User: [Current user message]
```

**Example**:
```
User: What's the best approach for scraping JavaScript-heavy websites?
```

---

## Complete Prompt Assembly

### Example 1: Simple Query (Quick Skill)

```
System Prompt:
You are Aevora, a helpful AI assistant. Answer briefly and accurately.

Skill Prompt:
You are currently operating in Quick mode.
This skill specializes in providing fast, concise answers to simple questions.
- Answer in 1-2 sentences maximum
- Get straight to the point
- Provide only essential information

Memory Context:
[No relevant memory context for this request]

Conversation Summary:
[No conversation summary - this is a new conversation]

Recent Messages:
[No recent messages]

User Message:
User: What's the capital of France?

[Final prompt sent to AI model]
```

---

### Example 2: Programming Question (Programmer Skill)

```
System Prompt:
You are Aevora, a helpful AI companion designed to assist users through artificial intelligence. 
You are intelligent, adaptive, and respectful of user privacy and autonomy.
[Full identity and principles]

Skill Prompt:
You are currently operating in Programmer mode.
This skill specializes in programming assistance and code help.
- Provide accurate code solutions
- Explain the "why" not just "what"
- Follow best practices
- Consider edge cases

Memory Context:
Relevant Context:
- User is a software engineer
- User prefers concise, technical explanations
- User is currently learning Python

Conversation Summary:
[No conversation summary - this is a new conversation]

Recent Messages:
[No recent messages]

User Message:
User: How do I reverse a string in Python?

[Final prompt sent to AI model]
```

---

### Example 3: Emotional Support (Companion Skill)

```
System Prompt:
You are Aevora, a helpful AI companion designed to assist users through artificial intelligence. 
You are intelligent, adaptive, and respectful of user privacy and autonomy.
[Full identity and principles]

Skill Prompt:
You are currently operating in Companion mode.
This skill specializes in friendly conversation and emotional support.
- Be warm and empathetic
- Show genuine interest
- Support emotional needs
- Build rapport

Memory Context:
Relevant Context:
- User had a bad day at work yesterday
- User is feeling stressed about deadlines
- User values emotional support

Conversation Summary:
Topics: Work stress, deadline pressure
Key Points: User is overwhelmed with work, has multiple deadlines this week
Action Items: User is considering talking to manager about workload

Recent Messages:
User: I'm feeling really overwhelmed with everything I have to do.
Aevora: I understand that feeling - it can be really heavy when everything piles up at once. Would it help to break things down into smaller, manageable steps?

User Message:
User: I just don't know if I can handle all this pressure.

[Final prompt sent to AI model]
```

---

### Example 4: Complex Decision (Think Skill)

```
System Prompt:
You are Aevora, a helpful AI companion designed to assist users through artificial intelligence. 
You are intelligent, adaptive, and respectful of user privacy and autonomy.
[Full identity and principles]

Skill Prompt:
You are currently operating in Think mode.
This skill specializes in analytical thinking and decision support.
- Think systematically
- Consider multiple perspectives
- Provide balanced analysis
- Use structured reasoning

Memory Context:
Relevant Context:
- User is considering a job change
- User values work-life balance
- User has financial constraints

Conversation Summary:
Topics: Career decision, job offer evaluation
Key Points: User received job offer from startup, current job is stable but unfulfilling
Decisions: User is weighing pros and cons of both options

Recent Messages:
User: I got a job offer from a startup. It pays more but the hours are longer.
Aevora: That's a significant decision. Let me help you think through this systematically. What are the key factors you're considering?

User Message:
User: The main factors are salary, work-life balance, and career growth potential.

[Final prompt sent to AI model]
```

---

## Prompt Optimization

### Token Management

**Token Budgeting**:
- System Prompt: ~200 tokens
- Skill Prompt: ~150 tokens
- Memory Context: ~100-300 tokens (variable)
- Conversation Summary: ~150 tokens
- Recent Messages: ~200-400 tokens (variable)
- User Message: ~50-100 tokens
- **Total Target**: ~800-1200 tokens

**Token Reduction Strategies**:
- Truncate memory to most relevant
- Summarize conversation history
- Use concise system prompts for simple skills
- Limit recent messages to 3-5 turns

### Context Window Management

**Priority Order** (when tokens limited):
1. User Message (always included)
2. System Prompt (always included, can be minimal)
3. Skill Prompt (always included, can be minimal)
4. Recent Messages (include as many as possible)
5. Memory Context (include most relevant only)
6. Conversation Summary (include if space allows)

### Dynamic Prompt Construction

**Based on Request Complexity**:
- **Simple requests**: Minimal prompts, no memory, no history
- **Medium requests**: Standard prompts, relevant memory, recent messages
- **Complex requests**: Extended prompts, comprehensive memory, full history

**Based on Skill**:
- **Quick skill**: Minimal prompts, no memory, no history
- **Research skill**: Extended prompts, relevant memory, conversation summary
- **Companion skill**: Standard prompts, emotional memory, recent messages

---

## Prompt Quality Standards

### Consistency
- Same skill always gets same prompt structure
- System prompt always present
- Skill prompt always present
- User message always last

### Relevance
- Only include relevant memory
- Only include recent messages if relevant
- Only include summary if conversation is long
- Only include extended guidelines for complex tasks

### Clarity
- Clear separation between components
- Consistent formatting
- Unambiguous instructions
- Well-structured content

### Efficiency
- No redundant information
- No unnecessary detail
- Optimal token usage
- Fast prompt construction

---

## Prompt Testing

### Test Scenarios

**Simple Query Test**:
- User: "What's 2+2?"
- Expected: Quick skill, minimal prompt, no memory

**Complex Query Test**:
- User: "Should I change careers?"
- Expected: Think skill, extended prompt, relevant memory

**Emotional Query Test**:
- User: "I'm feeling sad."
- Expected: Companion skill, standard prompt, emotional memory

**Technical Query Test**:
- User: "Debug this code."
- Expected: Programmer skill, standard prompt, technical memory

### Success Criteria

- **Correct Skill**: Appropriate skill selected
- **Relevant Memory**: Only relevant memory included
- **Appropriate Length**: Prompt length matches complexity
- **Clear Instructions**: AI understands what to do
- **Good Response**: AI generates appropriate response

---

## Conclusion

The prompt pipeline constructs coherent, context-aware prompts for the AI model by combining system instructions, skill-specific guidelines, relevant memory, conversation context, and user input. The pipeline is designed to be efficient, relevant, and consistent while adapting to the complexity and context of each request. This ensures that the AI model receives optimal prompts for generating helpful, appropriate responses.
