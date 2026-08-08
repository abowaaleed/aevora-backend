# Architecture

## Overview

Aevora follows a clean, modular architecture with clear separation of concerns. Each component has a single responsibility and communicates through well-defined interfaces. This ensures maintainability, testability, and extensibility.

---

## Core Principles

### 1. Layered Architecture
- Clear separation between layers
- Each layer has specific responsibilities
- Layers communicate through interfaces
- No layer skips another layer

### 2. Dependency Injection
- Dependencies injected, not hardcoded
- Easy to swap implementations
- Facilitates testing
- Supports multiple configurations

### 3. Single Responsibility
- Each component has one job
- No component does too much
- Easy to understand and maintain
- Changes are localized

### 4. Interface-Based Design
- Components depend on interfaces
- Implementations are swappable
- Clear contracts between components
- Easy to mock for testing

### 5. Local-First
- Core functionality works offline
- Cloud features are optional enhancements
- Data stored locally by default
- Privacy by design

---

## System Architecture

### High-Level Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                         Flutter UI                           │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │  Chat    │  │  Skills  │  │  Memory  │  │ Settings │  │
│  │  Screen  │  │  UI      │  │  UI      │  │  UI      │  │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ HTTP/JSON
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      FastAPI Backend                         │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                   API Layer                            │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐           │  │
│  │  │  Health  │  │  Chat    │  │  Memory  │           │  │
│  │  │  Router │  │  Router  │  │  Router  │           │  │
│  │  └──────────┘  └──────────┘  └──────────┘           │  │
│  └──────────────────────────────────────────────────────┘  │
│                              │                               │
│                              ▼                               │
│  ┌──────────────────────────────────────────────────────┐  │
│  │           Conversation Manager (Orchestration)        │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐           │  │
│  │  │  Skills  │  │  Memory  │  │  Prompt  │           │  │
│  │  │  Engine  │  │  Engine  │  │  Engine  │           │  │
│  │  └──────────┘  └──────────┘  └──────────┘           │  │
│  └──────────────────────────────────────────────────────┘  │
│                              │                               │
│                              ▼                               │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                  AI Engine                             │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐           │  │
│  │  │  Model   │  │  Token   │  │  Context │           │  │
│  │  │  Config  │  │  Mgmt    │  │  Window  │           │  │
│  │  └──────────┘  └──────────┘  └──────────┘           │  │
│  └──────────────────────────────────────────────────────┘  │
│                              │                               │
│                              ▼                               │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                  Provider Layer                         │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐           │  │
│  │  │  Ollama  │  │  Llama   │  │  Cloud   │           │  │
│  │  │ Provider │  │  Provider │  │  Provider │           │  │
│  │  └──────────┘  └──────────┘  └──────────┘           │  │
│  └──────────────────────────────────────────────────────┘  │
│                              │                               │
│                              ▼                               │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                  External Services                      │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐           │  │
│  │  │  Ollama  │  │  Llama   │  │  Cloud   │           │  │
│  │  │  API     │  │  .cpp    │  │  APIs    │           │  │
│  │  └──────────┘  └──────────┘  └──────────┘           │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Data Layer                                 │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │  SQLite  │  │  Embed   │  │  Vector  │  │  Cloud   │  │
│  │  Database │  │  Database │  │  Store   │  │  Storage │  │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## Request Flow

### Complete Request Flow

```
1. User Input (Flutter)
   ↓
2. HTTP POST /chat (JSON: {"message": "..."})
   ↓
3. API Layer (chat.py)
   - Validates request with Pydantic
   - Calls ConversationManager
   ↓
4. ConversationManager
   - Selects appropriate skill (Skills Engine)
   - Retrieves relevant context (Memory Engine)
   - Constructs prompt (Prompt Engine)
   - Calls AI Engine
   ↓
5. AI Engine
   - Manages model configuration
   - Handles context window
   - Calls Provider
   ↓
6. Provider (OllamaProvider)
   - Formats request for Ollama API
   - Sends HTTP request to Ollama
   - Returns response
   ↓
7. Response flows back up
   - AI Engine → ConversationManager
   - ConversationManager stores interaction (Memory Engine)
   - ConversationManager → API Layer
   - API Layer → Flutter UI
   ↓
8. Display response to user
```

### Detailed Flow Diagram

```
┌─────────────┐
│   Flutter   │
│   Client    │
└──────┬──────┘
       │ POST /chat
       │ {"message": "Hello"}
       ▼
┌─────────────┐
│  API Layer  │
│  (chat.py)  │
└──────┬──────┘
       │ ChatRequest(message)
       ▼
┌─────────────────────┐
│Conversation Manager │
│                     │
│ 1. Skills Engine    │
│    - Select skill   │
│    - Load config    │
│                     │
│ 2. Memory Engine    │
│    - Retrieve      │
│    - Context       │
│                     │
│ 3. Prompt Engine    │
│    - Build prompt  │
│    - Inject context│
└──────┬──────────────┘
       │ generate_reply(prompt)
       ▼
┌─────────────┐
│  AI Engine  │
│             │
│ - Model cfg │
│ - Context   │
│ - Tokens    │
└──────┬──────┘
       │ generate(prompt)
       ▼
┌─────────────┐
│  Provider   │
│  (Ollama)   │
│             │
│ - HTTP call │
│ - Ollama API│
└──────┬──────┘
       │ HTTP POST
       │ /api/generate
       ▼
┌─────────────┐
│   Ollama    │
│   Service   │
└──────┬──────┘
       │ Response
       ▼
┌─────────────┐
│  Provider   │
└──────┬──────┘
       │ Response text
       ▼
┌─────────────┐
│  AI Engine  │
└──────┬──────┘
       │ Reply
       ▼
┌─────────────────────┐
│Conversation Manager │
│                     │
│ - Store interaction │
│ - Update memory     │
└──────┬──────────────┘
       │ ChatResponse(reply)
       ▼
┌─────────────┐
│  API Layer  │
└──────┬──────┘
       │ JSON response
       ▼
┌─────────────┐
│   Flutter   │
│   Client    │
└─────────────┘
```

---

## Future Engine Integration Points

### Voice Engine Integration

```
┌─────────────┐
│   Flutter   │
│   Voice UI  │
└──────┬──────┘
       │ Audio input
       ▼
┌─────────────┐
│ Voice Engine│
│             │
│ - STT       │
│ - TTS       │
│ - Wake word │
└──────┬──────┘
       │ Text
       ▼
┌─────────────────────┐
│Conversation Manager │
└─────────────────────┘
```

**Integration Point**: Voice Engine sits between Flutter UI and Conversation Manager, converting audio to text and text to audio.

### Vision Engine Integration

```
┌─────────────┐
│   Flutter   │
│  Image UI   │
└──────┬──────┘
       │ Image upload
       ▼
┌─────────────┐
│Vision Engine│
│             │
│ - Analysis  │
│ - OCR       │
│ - Description│
└──────┬──────┘
       │ Visual context
       ▼
┌─────────────────────┐
│Conversation Manager │
└──────┬──────────────┘
       │
       ▼
┌─────────────┐
│Memory Engine│
│             │
│ - Store     │
│ - Visual    │
│ - Memories  │
└─────────────┘
```

**Integration Point**: Vision Engine processes images and provides visual context to Conversation Manager, which stores visual memories.

### Knowledge Engine Integration

```
┌─────────────────────┐
│Conversation Manager │
└──────┬──────────────┘
       │ Knowledge query
       ▼
┌─────────────┐
│Knowledge    │
│Engine       │
│             │
│ - Search    │
│ - Retrieve  │
│ - Graph     │
└──────┬──────┘
       │ Knowledge
       ▼
┌─────────────┐
│Prompt Engine│
└─────────────┘
```

**Integration Point**: Knowledge Engine provides knowledge to Prompt Engine for context injection.

### Plugin Engine Integration

```
┌─────────────┐
│Plugin Engine│
│             │
│ - Load      │
│ - Execute   │
│ - Sandbox   │
└──────┬──────┘
       │ Plugin skill
       ▼
┌─────────────┐
│Skills Engine│
└──────┬──────┘
       │
       ▼
┌─────────────────────┐
│Conversation Manager │
└─────────────────────┘
```

**Integration Point**: Plugin Engine provides custom skills to Skills Engine.

---

## Data Flow

### Memory Data Flow

```
┌─────────────────────┐
│Conversation Manager │
└──────┬──────────────┘
       │ Store memory
       ▼
┌─────────────┐
│Memory Engine│
│             │
│ - Classify  │
│ - Rank      │
│ - Index     │
└──────┬──────┘
       │ Store
       ▼
┌─────────────┐
│ SQLite DB   │
└─────────────┘
```

### Prompt Data Flow

```
┌─────────────┐
│Skills Engine│
└──────┬──────┘
       │ Skill config
       ▼
┌─────────────┐
│Prompt Engine│
│             │
│ - Template  │
│ - Context   │
│ - Personality│
└──────┬──────┘
       │ Final prompt
       ▼
┌─────────────┐
│  AI Engine  │
└─────────────┘
```

---

## Component Responsibilities

### API Layer
- HTTP request/response handling
- Request validation (Pydantic)
- Authentication (future)
- Rate limiting (future)
- Error handling

### Conversation Manager
- Orchestrate conversation flow
- Coordinate engines
- Manage conversation state
- Handle skill switching
- Store interactions

### Skills Engine
- Maintain skill registry
- Select appropriate skill
- Load skill configuration
- Apply skill personality
- Manage skill lifecycle

### Memory Engine
- Store and retrieve memories
- Classify memory types
- Rank by importance
- Search and filter
- Manage expiration

### Prompt Engine
- Maintain prompt templates
- Inject context and memory
- Apply personality
- Optimize for model
- Manage token limits

### AI Engine
- Manage model configuration
- Handle context window
- Coordinate with provider
- Manage tokens
- Handle streaming (future)

### Provider Layer
- Abstract AI model implementations
- Handle model-specific APIs
- Manage connections
- Handle errors
- Optimize performance

---

## Communication Patterns

### Synchronous Communication
- API → Conversation Manager
- Conversation Manager → Skills Engine
- Conversation Manager → Memory Engine
- Conversation Manager → AI Engine
- AI Engine → Provider

### Asynchronous Communication (Future)
- Voice processing (audio streams)
- Vision processing (large images)
- Cloud sync (background)
- Plugin execution (sandboxed)

### Event-Driven (Future)
- Memory updates trigger reindexing
- Skill changes trigger prompt rebuild
- Provider failures trigger fallback

---

## Error Handling Strategy

### Layered Error Handling
1. **Provider Layer**: Model-specific errors, timeouts
2. **AI Engine**: Generation errors, context issues
3. **Conversation Manager**: Orchestration errors
4. **API Layer**: HTTP errors, validation errors
5. **Flutter UI**: Network errors, display errors

### Error Propagation
- Errors caught at appropriate layer
- User-friendly error messages
- Logging at each layer
- Graceful degradation

### Fallback Strategies
- Provider fallback (Ollama → llama.cpp)
- Skill fallback (specialized → general)
- Memory fallback (semantic → keyword)
- Network fallback (cloud → local)

---

## Security Architecture

### Local Security
- Database encryption at rest
- Secure key storage
- Input validation
- SQL injection prevention

### Network Security
- HTTPS for all external calls
- Certificate pinning (future)
- API key management (future)
- Request signing (future)

### Plugin Security
- Sandbox execution
- Permission system
- API restrictions
- Resource limits

---

## Performance Architecture

### Caching Strategy
- In-memory cache for hot data
- Prompt template caching
- Memory search result caching
- Model connection pooling

### Optimization Points
- Lazy loading of memories
- Batch database operations
- Connection pooling
- Asynchronous I/O

### Monitoring
- Response time tracking
- Error rate monitoring
- Resource usage tracking
- Performance profiling

---

## Scalability Architecture

### Horizontal Scaling (Future)
- Multiple API instances
- Load balancing
- Database sharding
- Distributed caching

### Vertical Scaling
- Model optimization
- Memory optimization
- CPU optimization
- Storage optimization

### Data Partitioning
- User data isolation
- Time-based partitioning
- Geographic partitioning (future)

---

## Deployment Architecture

### Development
- Local development environment
- Docker containers (future)
- Hot reload
- Debug mode

### Staging (Future)
- Production-like environment
- Load testing
- Integration testing
- Performance testing

### Production (Future)
- High availability setup
- Auto-scaling
- Disaster recovery
- Backup and restore

---

## Technology Stack

### Backend
- **Framework**: FastAPI
- **Language**: Python 3.12+
- **Database**: SQLite
- **AI**: Ollama (local), llama.cpp (future)
- **HTTP**: requests, httpx

### Frontend
- **Framework**: Flutter
- **Language**: Dart
- **Platforms**: macOS, iOS, Android, Web
- **HTTP**: http package

### Infrastructure (Future)
- **Containerization**: Docker
- **Orchestration**: Kubernetes
- **Monitoring**: Prometheus, Grafana
- **Logging**: ELK Stack
- **CI/CD**: GitHub Actions

---

## Testing Architecture

### Unit Tests
- Test individual components
- Mock dependencies
- Fast execution
- High coverage

### Integration Tests
- Test component interactions
- Use real dependencies
- Slower execution
- Critical paths

### End-to-End Tests
- Test complete flows
- Real infrastructure
- Slowest execution
- User scenarios

### Test Pyramid
```
        /\
       /E2E\      (10%)
      /------\
     /Integration\ (30%)
    /------------\
   /   Unit Tests  \ (60%)
  /----------------\
```

---

## Documentation Architecture

### Code Documentation
- Docstrings for all functions
- Type hints everywhere
- Inline comments for complex logic
- Architecture diagrams

### API Documentation
- Auto-generated with FastAPI
- Interactive docs (Swagger)
- Request/response examples
- Error documentation

### User Documentation
- Installation guides
- Feature documentation
- Troubleshooting guides
- FAQ

### Developer Documentation
- Architecture documentation
- Contribution guidelines
- Code style guide
- Onboarding guide

---

## Version Control Strategy

### Branching Model
- `main`: Production code
- `develop`: Integration branch
- `feature/*`: Feature branches
- `bugfix/*`: Bug fix branches
- `release/*`: Release preparation

### Commit Convention
- Conventional Commits
- `feat:` New features
- `fix:` Bug fixes
- `docs:` Documentation
- `refactor:` Code refactoring
- `test:` Test additions
- `chore:` Maintenance

### Release Process
- Semantic versioning
- Changelog generation
- Release notes
- Tagging strategy

---

## Conclusion

This architecture provides a solid foundation for Aevora's development. The modular design ensures that each component can be developed, tested, and replaced independently. The clear separation of concerns makes the system maintainable and extensible. The local-first approach ensures privacy and reliability, while the modular design allows for future expansion and enhancement.
