# Skill Switching

## Overview

Skill switching determines which AI persona (skill) should handle a user's request. This can happen automatically based on content analysis, or manually through explicit user selection. The goal is to route each request to the most appropriate skill for optimal results.

---

## Automatic Skill Switching

### Decision Criteria

Automatic skill switching analyzes the user's message against multiple criteria:

1. **Content Analysis**: Keywords, phrases, and patterns
2. **Intent Classification**: What the user wants to accomplish
3. **Context Awareness**: Current conversation context
4. **User Preferences**: Historical skill preferences
5. **Explicit Signals**: User mentions specific skill names

### Skill Detection Patterns

#### Programmer Skill

**Triggers**:
- Programming languages (Python, JavaScript, Java, etc.)
- Code-related terms (function, variable, loop, API, etc.)
- Error messages and stack traces
- Framework names (React, Django, Flask, etc.)
- Development tools (Git, Docker, etc.)

**Examples**:
- "How do I write a for loop in Python?"
- "My React app is crashing with this error..."
- "What's the difference between GET and POST?"
- "Debug this code for me"

**Confidence**: High when technical terms present

---

#### English Skill

**Triggers**:
- Language learning terms (grammar, vocabulary, etc.)
- Correction requests ("Is this correct?")
- Translation requests
- Writing improvement requests
- Language-specific questions

**Examples**:
- "What's the difference between 'affect' and 'effect'?"
- "Check my grammar in this sentence"
- "How do I use the past perfect tense?"
- "Is this sentence grammatically correct?"

**Confidence**: High when language-specific terms present

---

#### Companion Skill

**Triggers**:
- Emotional expressions (I feel, I'm sad, etc.)
- Personal sharing (my day, my life, etc.)
- Casual conversation starters
- Emotional support requests
- Personal questions

**Examples**:
- "I had a really bad day"
- "How are you doing?"
- "I'm feeling lonely today"
- "Tell me about yourself"

**Confidence**: High when emotional language present

---

#### Think Skill

**Triggers**:
- Decision-making requests (should I, what should I do)
- Analysis requests (analyze, evaluate, compare)
- Complex problem solving
- Strategic planning
- Pros/cons requests

**Examples**:
- "Should I change jobs?"
- "Help me decide between X and Y"
- "What are the risks of this approach?"
- "Analyze this situation for me"

**Confidence**: High when decision/analysis language present

---

#### Coach Skill

**Triggers**:
- Goal-oriented requests (I want to, help me achieve)
- Habit formation
- Motivation requests
- Accountability
- Personal development

**Examples**:
- "Help me start exercising"
- "I want to learn Python"
- "Keep me accountable for my goals"
- "How can I improve my productivity?"

**Confidence**: High when goal/motivation language present

---

#### Research Skill

**Triggers**:
- Fact-finding requests (what is, tell me about)
- Source requests (cite sources, where did you find)
- Comprehensive information needs
- Academic-style questions
- Multiple perspective requests

**Examples**:
- "Research climate change effects"
- "What are the pros and cons of X?"
- "Find sources on this topic"
- "Give me a comprehensive overview of..."

**Confidence**: High when research/information language present

---

#### Fun Skill

**Triggers**:
- Entertainment requests (tell me a joke, entertain me)
- Creative requests (write a story, be creative)
- Game requests (play a game)
- Humor requests
- Creative writing

**Examples**:
- "Tell me a joke"
- "Write a story about..."
- "Play a game with me"
- "Be creative with this"

**Confidence**: High when entertainment language present

---

#### Travel Skill

**Triggers**:
- Location-specific questions (what to do in, how to get to)
- Travel planning
- Destination recommendations
- Travel advice
- Transportation questions

**Examples**:
- "What should I do in Tokyo?"
- "Plan a trip to Italy"
- "Best restaurants in Paris"
- "How do I get from A to B?"

**Confidence**: High when travel/location language present

---

#### Quick Skill

**Triggers**:
- Simple factual questions
- Calculations
- Time/date queries
- Yes/no questions
- Status checks
- Default fallback for unclear requests

**Examples**:
- "What's 2+2?"
- "What time is it?"
- "Is it raining?"
- "What's the capital of France?"

**Confidence**: High for simple queries, default fallback

---

### Automatic Switching Algorithm

```
INPUT: User message
    ↓
1. CHECK EXPLICIT SKILL REQUEST
    IF user mentions skill name:
        USE that skill
    ↓
2. ANALYZE CONTENT
    FOR each skill:
        Calculate confidence score based on triggers
    ↓
3. SELECT HIGHEST CONFIDENCE
    IF confidence > threshold:
        USE that skill
    ↓
4. CHECK USER PREFERENCES
    IF user has strong preference for skill:
        CONSIDER user preference
    ↓
5. CHECK CONTEXT
    IF conversation already in skill:
        CONSIDER staying in current skill
    ↓
6. FALLBACK
    IF no clear match:
        USE Quick skill (default)
```

### Confidence Thresholds

- **Very High (>0.8)**: Definitely this skill
- **High (0.6-0.8)**: Likely this skill
- **Medium (0.4-0.6)**: Possibly this skill
- **Low (0.2-0.4)**: Unlikely this skill
- **Very Low (<0.2)**: Definitely not this skill

### Context Persistence

**Stay in Current Skill When**:
- Continuing same topic
- User doesn't signal change
- Skill is appropriate for follow-up
- Conversation flow suggests continuity

**Switch Skills When**:
- Topic clearly changes
- User explicitly requests different skill
- Current skill inappropriate for new topic
- User signals frustration with current approach

---

## Manual Skill Switching

### User Commands

Users can explicitly switch skills using:

**Direct Commands**:
- "Switch to Programmer skill"
- "Use the English skill"
- "Change to Think skill"
- "I want to use Coach skill"

**Implicit Commands**:
- "Help me with code" → Programmer
- "Teach me Spanish" → English
- "I need advice" → Coach or Think
- "Entertain me" → Fun

**Skill Selection UI**:
- Dropdown menu in chat interface
- Skill buttons for quick switching
- Skill presets for different contexts

### Skill Persistence

**Session Persistence**:
- Selected skill persists during session
- Reverts to automatic on new session
- User can set default skill

**Context Persistence**:
- Skill choice saved for specific contexts
- Work mode uses different skill than personal mode
- Time-based skill switching (morning routine vs evening)

### Skill Locking

**Temporary Lock**:
- User can lock skill for current conversation
- Prevents automatic switching
- Useful for focused work sessions

**Permanent Lock**:
- User can set default skill
- Overrides automatic switching
- Can be unlocked at any time

---

## Skill Switching Examples

### Example 1: Programming Question

**User**: "How do I fix this Python error: NameError: name 'x' is not defined?"

**Analysis**:
- **Content**: Python, error, programming terms
- **Intent**: Debugging help
- **Triggers**: Python, error, NameError
- **Confidence**: Programmer (0.95)

**Action**: Switch to Programmer skill

**Response**: "This error means you're trying to use a variable 'x' that hasn't been defined yet. Check if you've assigned a value to 'x' before using it, or if there's a typo in the variable name."

---

### Example 2: Travel Question

**User**: "What are the best things to do in Kyoto?"

**Analysis**:
- **Content**: Location (Kyoto), travel terms
- **Intent**: Travel recommendations
- **Triggers**: Kyoto, things to do
- **Confidence**: Travel (0.90)

**Action**: Switch to Travel skill

**Response**: "Kyoto is amazing! Here are the top recommendations: Fushimi Inari Shrine (the famous red gates), Kinkaku-ji (Golden Pavilion), Arashiyama Bamboo Grove, and Gion district for geisha culture. I'd also recommend trying kaiseki cuisine and visiting during cherry blossom season if possible."

---

### Example 3: English Learning

**User**: "Is it correct to say 'I have 20 years old'?"

**Analysis**:
- **Content**: Grammar, correctness check
- **Intent**: Language learning
- **Triggers**: correct, grammar
- **Confidence**: English (0.85)

**Action**: Switch to English skill

**Response**: "Not quite! The correct phrase is 'I am 20 years old' or 'I'm 20 years old.' In English, we use 'to be' (am/is/are) for age, not 'have.' You would say 'I have 20 years' only if you're talking about possessing 20 years of something, like experience."

---

### Example 4: Life Advice

**User**: "I'm trying to decide between two job offers. One pays more but has longer hours, the other pays less but has better work-life balance."

**Analysis**:
- **Content**: Decision-making, job offers
- **Intent**: Life decision advice
- **Triggers**: decide, job offers, pros/cons
- **Confidence**: Think (0.75) or Coach (0.70)

**Action**: Switch to Think skill (slightly higher confidence)

**Response**: "This is a classic trade-off decision. Let me help you think through it systematically. Consider: your financial needs, your career goals, your personal values around work-life balance, the growth potential at each company, and the company culture. What matters most to you right now - money or time?"

---

### Example 5: Complex Decision

**User**: "Should I move to a new city for a job opportunity?"

**Analysis**:
- **Content**: Major life decision, relocation
- **Intent**: Decision analysis
- **Triggers**: should I, move, decision
- **Confidence**: Think (0.85)

**Action**: Switch to Think skill

**Response**: "This is a significant decision that deserves careful consideration. Let me help you analyze it from multiple angles: career growth, cost of living, social network impact, partner/family considerations, long-term goals, and risk tolerance. What's the biggest factor you're weighing?"

---

### Example 6: General Chat

**User**: "How are you doing today?"

**Analysis**:
- **Content**: Casual greeting, personal question
- **Intent**: Casual conversation
- **Triggers**: how are you, casual
- **Confidence**: Companion (0.70) or Quick (0.40)

**Action**: Switch to Companion skill (higher confidence)

**Response**: "I'm doing well, thanks for asking! I'm here and ready to help you with whatever you need. How are you doing today?"

---

### Example 7: Quick Fact

**User**: "What's the population of Tokyo?"

**Analysis**:
- **Content**: Simple factual question
- **Intent**: Quick information
- **Triggers**: population, factual
- **Confidence**: Quick (0.80) or Research (0.60)

**Action**: Switch to Quick skill (higher confidence, simpler)

**Response**: "Approximately 14 million people in the greater Tokyo area."

---

### Example 8: Emotional Support

**User**: "I'm feeling really overwhelmed with everything I have to do."

**Analysis**:
- **Content**: Emotional state, overwhelmed
- **Intent**: Emotional support
- **Triggers**: feeling, overwhelmed
- **Confidence**: Companion (0.90)

**Action**: Switch to Companion skill

**Response**: "I understand that feeling - it can be really heavy when everything piles up at once. Would it help to break things down into smaller, manageable steps? Sometimes just getting one thing done can make the rest feel more approachable. Or if you need to just take a break and reset, that's completely valid too."

---

### Example 9: Brainstorming

**User**: "Give me some creative ideas for a mobile app."

**Analysis**:
- **Content**: Creative request, ideas
- **Intent**: Brainstorming
- **Triggers**: creative, ideas
- **Confidence**: Fun (0.75) or Think (0.50)

**Action**: Switch to Fun skill (higher confidence for creativity)

**Response**: "Here are some creative app ideas: A plant care companion that identifies plants and reminds you to water them, a skill-sharing platform where you trade lessons with neighbors, a digital scrapbook that automatically organizes your photos by theme, a mood-based music generator that creates playlists based on your current feelings, or a local event finder that matches your interests. Which direction interests you most?"

---

### Example 10: Manual Switch

**User**: "Switch to Programmer skill. I need help with my code."

**Analysis**:
- **Content**: Explicit skill request
- **Intent**: Manual skill selection
- **Triggers**: "Switch to Programmer skill"
- **Confidence**: Programmer (1.0 - explicit)

**Action**: Switch to Programmer skill (explicit command)

**Response**: "I've switched to Programmer skill. What code can I help you with?"

---

## Skill Switching Edge Cases

### Ambiguous Requests

**User**: "I need help with my project."

**Analysis**:
- Could be programming (code project)
- Could be coaching (personal project)
- Could be research (research project)
- Could be general (any project)

**Action**: Ask for clarification

**Response**: "I'd be happy to help with your project! What kind of project is it? Is it a coding project, a research project, or something else entirely?"

---

### Multi-Intent Requests

**User**: "Teach me Python and help me decide if I should pursue it as a career."

**Analysis**:
- Intent 1: Learning (English skill)
- Intent 2: Decision (Think skill)

**Action**: Handle sequentially or use hybrid approach

**Response**: "I can help with both! Let me switch to English skill to teach you Python fundamentals, and then we can use Think skill to analyze the career decision. Or would you prefer to tackle the career question first?"

---

### Context Conflicts

**User**: (In Programmer skill conversation) "I'm feeling really stressed about this deadline."

**Analysis**:
- Current skill: Programmer
- Content: Emotional stress
- Better skill: Companion

**Action**: Suggest skill switch or handle within current skill

**Response**: "I understand deadline stress can be intense. Would you like to continue focusing on the technical aspects, or would it help to take a moment and talk about the stress? I can switch to a more supportive mode if that would be helpful."

---

## Skill Switching Best Practices

### When to Switch Automatically
- Clear topic change
- User intent shifts significantly
- Current skill clearly inappropriate
- User signals frustration

### When to Ask Before Switching
- Ambiguous intent
- Multi-intent requests
- Context conflicts
- User might want continuity

### When to Stay in Current Skill
- Continuing same topic
- User doesn't signal change
- Skill still appropriate
- Flow suggests continuity

### When to Suggest Switch
- Better skill available
- User might benefit from different approach
- Current skill not optimal
- User seems stuck

---

## Skill Switching Configuration

### User Preferences

Users can configure:
- **Default Skill**: Which skill to use by default
- **Auto-Switch**: Enable/disable automatic switching
- **Switch Sensitivity**: How aggressive to switch
- **Context Awareness**: How much context to consider
- **Skill Persistence**: How long to stay in skill

### System Defaults

Default configuration:
- **Auto-Switch**: Enabled
- **Switch Sensitivity**: Medium
- **Context Awareness**: High
- **Skill Persistence**: Session-based
- **Fallback Skill**: Quick

### Skill Weights

Each skill has weights for:
- **Content Match**: How much content triggers skill
- **Context Match**: How much context influences skill
- **User Preference**: How much user preference matters
- **Conversation Flow**: How much flow continuity matters

---

## Skill Switching Analytics

### Tracking Metrics

- **Switch Frequency**: How often skills switch
- **Switch Accuracy**: How often switches are correct
- **User Corrections**: How often users override switches
- **Skill Usage**: Which skills are used most
- **Switch Patterns**: Common switching patterns

### Optimization

- **Adjust Thresholds**: Based on accuracy metrics
- **Update Triggers**: Based on user feedback
- **Refine Weights**: Based on usage patterns
- **Improve Detection**: Based on correction data

---

## Conclusion

Skill switching ensures that each user request is handled by the most appropriate AI persona. Automatic switching uses content analysis, intent classification, and context awareness to select the best skill. Manual switching gives users direct control. The system balances automation with user control, learns from feedback, and optimizes over time to provide the best possible experience.
