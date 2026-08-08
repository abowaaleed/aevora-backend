# Memory

## Overview

The Memory Engine is Aevora's long-term storage and retrieval system. It maintains all information about the user, their preferences, history, and context across sessions and years. Memory is what makes Aevora a true companion rather than a ephemeral chatbot.

---

## Memory Philosophy

### Core Principles
- **Persistence**: Memories last across sessions, devices, and years
- **Privacy**: All memories are stored locally by default
- **Relevance**: Only retrieve memories that are contextually relevant
- **Accuracy**: Memories should be verifiable and correctable
- **Hierarchy**: Not all memories are equal; importance varies
- **Evolution**: Memories can be updated, refined, or forgotten over time

### Memory vs. Data
- **Data**: Raw information (facts, numbers, dates)
- **Memory**: Contextualized, meaningful information with relationships
- Aevora stores memories, not just data

---

## Memory Types

### 1. Short-term Memory

**Purpose**
Maintain context within the current conversation and recent interactions.

**Duration**
Current session (hours to days)

**Content**
- Current conversation history
- Recent messages (last 10-20 turns)
- Immediate context and state
- Temporary variables and flags

**Storage**
- In-memory during session
- Persisted to database for session recovery
- Automatically cleared after session timeout

**Retrieval**
- Full conversation history available
- Context window management
- Recent message prioritization

**Expiration**
- Session end (configurable retention period)
- Manual clear by user
- Automatic cleanup after N days

---

### 2. Long-term Memory

**Purpose**
Store information that persists across sessions and years, building Aevora's understanding of the user.

**Duration**
Indefinite (until manually deleted or auto-expired)

**Content**
- User preferences and settings
- Important facts about user
- Relationship information
- Long-term patterns and habits
- Significant events and milestones

**Storage**
- SQLite database (local)
- Encrypted cloud sync (optional)
- Indexed for fast retrieval

**Retrieval**
- Semantic search
- Category-based retrieval
- Time-based retrieval
- Importance-based retrieval

**Expiration**
- Manual deletion by user
- Auto-expiration based on importance
- Decay over time (low-importance memories)

---

## Memory Categories

### Facts

**Definition**
Objective, verifiable information about the user and their world.

**Examples**
- Name, age, location
- Job title, company
- Family members and relationships
- Important dates (birthday, anniversary)
- Contact information

**Storage Structure**
```yaml
fact:
  id: unique_id
  type: fact
  category: personal/contact/work
  content: "User works at TechCorp as Senior Engineer"
  confidence: 0.9
  source: conversation
  created_at: timestamp
  last_accessed: timestamp
  access_count: integer
  importance: high
```

**Importance Scoring**
- High: Core identity information (name, job, family)
- Medium: Regularly used facts (preferences, routines)
- Low: Rarely used facts (old addresses, past jobs)

**Verification**
- User confirmation for important facts
- Cross-reference with other memories
- Confidence tracking
- Correction mechanism

---

### Preferences

**Definition**
User likes, dislikes, and choices that guide Aevora's behavior.

**Examples**
- Communication style (formal vs casual)
- Response length preference
- Humor tolerance
- Topic interests
- Time of day preferences

**Storage Structure**
```yaml
preference:
  id: unique_id
  type: preference
  category: communication/behavior/content
  key: "response_style"
  value: "casual"
  confidence: 0.8
  source: explicit_statement/observed_behavior
  created_at: timestamp
  last_updated: timestamp
  importance: medium
```

**Importance Scoring**
- High: Core preferences (communication style, privacy)
- Medium: Content preferences (topics, humor)
- Low: Minor preferences (formatting, timing)

**Adaptation**
- Explicit user statements override observed behavior
- Observed patterns inform but don't override
- Confidence increases with consistent behavior
- Preferences can conflict (resolution needed)

---

### Projects

**Definition**
Ongoing or completed projects, tasks, and goals the user is working on.

**Examples**
- Software projects
- Learning goals
- Home improvement projects
- Career objectives
- Personal projects

**Storage Structure**
```yaml
project:
  id: unique_id
  type: project
  name: "Learn Python"
  status: active/completed/paused
  start_date: timestamp
  end_date: timestamp/null
  description: "Goal to learn Python programming"
  milestones: [...]
  related_memories: [memory_ids]
  created_at: timestamp
  last_updated: timestamp
  importance: high
```

**Importance Scoring**
- High: Active, high-priority projects
- Medium: Active, lower-priority projects
- Low: Completed or paused projects

**Tracking**
- Progress updates
- Milestone tracking
- Related conversations
- Resource links
- Time spent

---

### People

**Definition**
Information about people in the user's life and their relationships.

**Examples**
- Family members
- Friends and colleagues
- Professional contacts
- Important relationships
- People mentioned frequently

**Storage Structure**
```yaml
person:
  id: unique_id
  type: person
  name: "John Smith"
  relationship: "colleague/friend/family"
  context: "Works at same company, lunch buddy"
  last_mentioned: timestamp
  mention_count: integer
  related_memories: [memory_ids]
  created_at: timestamp
  last_updated: timestamp
  importance: medium
```

**Importance Scoring**
- High: Close family, close friends
- Medium: Regular contacts, colleagues
- Low: Occasional contacts, acquaintances

**Relationship Mapping**
- Relationship strength (based on mentions)
- Context of relationship
- Last interaction
- Important events with person

---

### Places

**Definition**
Locations important to the user and their relationship to them.

**Examples**
- Home and work addresses
- Favorite restaurants
- Travel destinations
- Important locations
- Frequently visited places`

**Storage Structure**
```yaml
place:
  id: unique_id
  type: place
  name: "Home"
  location: "123 Main St, City"
  category: home/work/favorite/visited
  context: "Primary residence"
  last_mentioned: timestamp
  visit_count: integer
  related_memories: [memory_ids]
  created_at: timestamp
  last_updated: timestamp
  importance: high
```

**Importance Scoring**
- High: Home, work, primary locations
- Medium: Frequently visited places
- Low: Visited once or rarely

**Location Context**
- Purpose of location
- Frequency of visits
- Associated activities
- Related people

---

### Events

**Definition**
Significant occurrences, experiences, and milestones in the user's life.

**Examples**
- Life events (wedding, graduation)
- Work events (promotion, job change)
- Travel experiences
- Achievements
- Important conversations

**Storage Structure**
```yaml
event:
  id: unique_id
  type: event
  name: "Promotion to Senior Engineer"
  date: timestamp
  category: life/work/travel/achievement
  description: "Got promoted at work"
  significance: high/medium/low
  related_memories: [memory_ids]
  created_at: timestamp
  last_updated: timestamp
  importance: high
```

**Importance Scoring**
- High: Major life events, significant achievements
- Medium: Notable events, important experiences
- Low: Minor events, routine occurrences

**Event Significance**
- Emotional impact
- Life impact
- Frequency of similar events
- User emphasis

---

## Conversation History

### Storage

**Message Structure**
```yaml
message:
  id: unique_id
  timestamp: timestamp
  role: user/assistant/system
  content: "Message text"
  skill_used: "skill_name"
  context: {...}
  related_memories: [memory_ids]
  metadata: {...}
```

**Session Management**
- Session ID for grouping messages
- Session start/end times
- Session metadata (device, location, context)
- Session summaries

### Summarization

**Purpose**
Compress long conversations into concise summaries while preserving key information.

 **Triggers**
- Conversation length exceeds threshold (e.g., 50 messages)
- Session end
- Topic change detected
- Time gap in conversation

**Summary Structure**
```yaml
summary:
  id: unique_id
  session_id: session_id
  start_time: timestamp
  end_time: timestamp
  topics: [topic1, topic2]
  key_points: [...]
  decisions: [...]
  action_items: [...]
  related_memories: [memory_ids]
  created_at: timestamp
```

**Summary Levels**
- **Brief**: 1-2 sentence overview
- **Standard**: Key points and decisions
- **Detailed**: Full conversation summary with context

---

## Memory Ranking

### Importance Score

**Calculation Factors**
- User emphasis (explicit marking)
- Access frequency
- Recency of access
- Relationship to other memories
- Emotional significance
- Practical utility

**Score Range**
- 0.0 - 1.0 (higher = more important)

**Categories**
- **Critical (>0.8)**: Core identity, essential preferences
- **High (0.6-0.8)**: Important facts, active projects
- **Medium (0.4-0.6)**: Regular preferences, recent events
- **Low (0.2-0.4)**: Minor facts, old information
- **Minimal (<0.2)**: Temporary, low-value information

### Relevance Score

**Contextual Relevance**
- Semantic similarity to current context
- Temporal proximity
- Category relevance
- Skill-specific relevance

**Score Range**
- 0.0 - 1.0 (higher = more relevant)

**Usage**
- Rank search results
- Determine which memories to retrieve
- Prioritize memory display

---

## Memory Expiration

### Automatic Expiration

**Triggers**
- Age exceeds threshold (based on importance)
- Access count below threshold over time
- Confidence decays below threshold
- User inactivity

**Expiration Rules**
```yaml
expiration:
  critical: never
  high: 2 years
  medium: 1 year
  low: 6 months
  minimal: 3 months
```

**Decay Mechanism**
- Importance score decays over time
- Access boosts importance
- Decay rate varies by category
- User can override auto-expiration

### Manual Deletion

**User Actions**
- Delete specific memory
- Delete memory category
- Delete all memories (reset)
- Bulk delete by criteria

**Confirmation**
- Important memories require confirmation
- Bulk deletion requires confirmation
- Deletion is reversible (trash bin)

---

## Privacy

### Local Storage

**Default Behavior**
- All memories stored locally by default
- No cloud sync without explicit consent
- Encrypted storage at rest
- Secure deletion

**Encryption**
- Database encryption
- Per-memory encryption for sensitive data
- Key management (user-controlled)
- Secure key storage

### Cloud Sync (Optional)

**Opt-in Only**
- User must explicitly enable
- End-to-end encryption
- User controls encryption keys
- Selective sync (choose categories)

**Sync Configuration**
```yaml
sync:
  enabled: false
  categories: [facts, preferences, projects]
  encryption: e2e
  key_management: user
  frequency: automatic/manual
```

### Privacy Controls

**User Controls**
- Enable/disable cloud sync
- Choose sync categories
- Delete cloud data
- Export all data
- Memory visibility settings

**Privacy Modes**
- **Strict**: No cloud, minimal logging
- **Balanced**: Cloud sync with encryption
- **Convenient**: Cloud sync, cross-device access

---

## Memory Editing

### User Editing

**Edit Types**
- Correct incorrect information
- Update outdated information
- Add context to memories
- Merge duplicate memories
- Split complex memories

**Edit Interface**
- Memory browser/search
- Edit forms with validation
- Change history tracking
- Edit reason logging

### System Editing

**Automatic Updates**
- Confidence adjustments
- Importance recalculation
- Relationship updates
- Category reclassification

**Conflict Resolution**
- User edits override system
- System suggestions require approval
- Edit conflicts flagged for review
- Version history maintained

---

## Memory Deletion

### Deletion Types

**User Initiated**
- Single memory deletion
- Bulk deletion
- Category deletion
- Complete reset

**System Initiated**
- Auto-expiration
- Duplicate removal
- Low-value cleanup
- Privacy cleanup

### Deletion Process

**Soft Delete**
- Mark as deleted
- Keep in trash bin
- Recoverable within time window
- Permanent delete after retention period

**Hard Delete**
- Immediate removal
- Cannot recover
- Secure wiping
- Audit logging

**Deletion Confirmation**
- Important memories: double confirmation
- Bulk deletion: confirmation with count
- Complete reset: strong warning + confirmation

---

## Memory Search

### Search Types

**Semantic Search**
- Natural language queries
- Concept matching
- Contextual relevance
- Embedding-based similarity

**Category Search**
- Filter by memory type
- Filter by category
- Filter by importance
- Filter by time range

**Keyword Search**
- Exact phrase matching
- Fuzzy matching
- Boolean operators
- Wildcard support

### Search Results

**Ranking**
- Relevance score
- Importance score
- Recency factor
- User feedback integration

**Display**
- Memory preview
- Full memory on click
- Related memories
- Edit/delete options

**Search History**
- Recent searches
- Saved searches
- Search analytics
- Popular searches

---

## Memory Architecture

### Storage Layers

**Layer 1: In-Memory**
- Current session data
- Frequently accessed memories
- Cache for hot data

**Layer 2: SQLite Database**
- Persistent storage
- Indexed for fast retrieval
- Full-text search capability
- Transaction support

**Layer 3: Encrypted Cloud (Optional)**
- Cross-device sync
- Backup and recovery
- Remote access
- Version history

### Indexing Strategy

**Primary Indexes**
- Memory ID
- Memory type
- Creation timestamp
- Importance score
- Last accessed timestamp

**Secondary Indexes**
- Category
- Related entities (people, places, projects)
- Skill relevance
- User tags

**Full-Text Search**
- Content indexing
- Semantic embeddings
- N-gram indexing
- Phrase matching

### Performance Optimization

**Caching**
- Frequently accessed memories
- Search result caching
- Summary caching
- Related memory caching

**Lazy Loading**
- Load memories on demand
- Pagination for large result sets
- Background preloading
- Predictive loading

**Query Optimization**
- Index-aware queries
- Query plan caching
- Result size limiting
- Timeout handling

---

## Memory Analytics

### Statistics

**Memory Counts**
- Total memories by type
- Memories by category
- Memories by importance
- Memories by time period

**Access Patterns**
- Most accessed memories
- Least accessed memories
- Access frequency distribution
- Temporal access patterns

**Growth Metrics**
- Memory creation rate
- Memory deletion rate
- Net memory growth
- Category growth rates

### Health Monitoring

**Memory Quality**
- Confidence distribution
- Duplicate detection
- Conflict detection
- Stale memory identification

**Storage Health**
- Database size
- Index efficiency
- Fragmentation level
- Backup status

**User Engagement**
- Memory edit frequency
- Search frequency
- Memory deletion patterns
- Sync activity

---

## Memory API Design

### Core Operations

**Create Memory**
```python
create_memory(
    content: str,
    memory_type: MemoryType,
    category: str,
    importance: float,
    metadata: dict
) -> Memory
```

**Retrieve Memory**
```python
retrieve_memory(
    memory_id: str
) -> Memory
```

**Search Memories**
```python
search_memories(
    query: str,
    memory_types: List[MemoryType],
    categories: List[str],
    limit: int
) -> List[Memory]
```

**Update Memory**
```python
update_memory(
    memory_id: str,
    updates: dict
) -> Memory
```

**Delete Memory**
```python
delete_memory(
    memory_id: str,
    permanent: bool = False
) -> bool
```

### Contextual Retrieval

**Get Context**
```python
get_context(
    conversation_id: str,
    skill: str,
    max_memories: int
) -> List[Memory]
```

**Relevant Memories**
```python
get_relevant_memories(
    message: str,
    skill: str,
    limit: int
) -> List[Memory]
```

---

## Future Memory Features

### Advanced Features
- Memory graphs and visualization
- Memory timeline views
- Memory export/import (JSON, CSV)
- Memory sharing (with consent)
- Memory collaboration (family accounts)
- Memory backup and restore
- Memory versioning
- Memory conflict resolution UI
- Memory analytics dashboard

### AI-Enhanced Memory
- Automatic memory extraction from conversations
- Memory summarization and consolidation
- Memory relationship detection
- Memory importance auto-scoring
- Memory quality assessment
- Memory gap detection
- Proactive memory suggestions

### Integration
- Calendar integration (events)
- Contact integration (people)
- Location services (places)
- File system integration (documents)
- Email integration (correspondence)
- Social media integration (optional)
