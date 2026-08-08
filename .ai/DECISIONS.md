# Decisions

## Overview

This document records all major technical decisions made during Aevora's development. Each decision includes the rationale, alternatives considered, and implications. This serves as project history and helps future developers understand the reasoning behind architectural choices.

---

## Decision 1: Local-First Architecture

**Date**: July 2026
**Status**: Implemented

### Decision
Aevora will be designed as a local-first application with all core functionality working offline. Cloud features will be optional enhancements, not requirements.

### Why This Decision

**Privacy Concerns**
- User data should remain on user devices
- No third-party data sharing without explicit consent
- Compliance with privacy regulations (GDPR, CCPA)

**Reliability**
- Works without internet connection
- No dependency on cloud service uptime
- User has full control over data

**Cost**
- No ongoing cloud infrastructure costs for users
- No API usage fees
- Sustainable long-term model

**Differentiation**
- Most AI assistants are cloud-dependent
- Local-first is a unique selling point
- Appeals to privacy-conscious users

### Alternatives Considered

**Cloud-First**
- Pros: Easier scaling, centralized updates
- Cons: Privacy concerns, ongoing costs, dependency on internet
- Rejected: Violates core value of privacy

**Hybrid (Cloud-Required)**
- Pros: Best of both worlds
- Cons: Still requires internet for core features
- Rejected: Doesn't solve reliability concerns

### Implications

**Technical**
- Must use local AI models (Ollama, llama.cpp)
- Database must be local (SQLite)
- Sync must be opt-in, not required
- Performance depends on user hardware

**User Experience**
- Initial setup requires AI model download
- Hardware requirements for local inference
- Offline capability is a key feature

**Business**
- No recurring revenue from cloud services
- Must find alternative monetization
- Marketplace and premium features for revenue

---

## Decision 2: Provider Abstraction Layer

**Date**: July 2026
**Status**: Implemented

### Decision
Create a Provider abstraction layer to decouple AI model implementations from the rest of the system.

### Why This Decision

**Flexibility**
- Easy to switch between AI models
- Support multiple providers (Ollama, llama.cpp, cloud APIs)
- Future-proof for emerging AI technologies

**Testing**
- Can mock providers for unit tests
- Test different models without changing code
- Isolate provider-specific issues

**Performance**
- Can route to optimal provider based on task
- Load balancing across multiple providers
- Fallback if one provider fails

### Alternatives Considered

**Direct Integration**
- Pros: Simpler initial implementation
- Cons: Tightly coupled, hard to change
- Rejected: Violates principle of replaceability

**Multiple Implementations**
- Pros: Each model optimized
- Cons: Code duplication, maintenance burden
- Rejected: Violates DRY principle

### Implications

**Technical**
- Additional abstraction layer
- Must define common interface
- Provider-specific optimizations limited

**Development**
- More initial complexity
- Easier to add new providers later
- Clear separation of concerns

**Maintenance**
- Provider updates isolated
- Can deprecate providers without breaking system
- Easier to support multiple models

---

## Decision 3: Conversation Manager Orchestration

**Date**: July 2026
**Status**: Implemented

### Decision
Introduce a Conversation Manager layer to orchestrate all AI interactions, preventing direct calls to AI Engine from API layer.

### Why This Decision

**Separation of Concerns**
- API handles HTTP, not conversation logic
- Conversation logic centralized in one place
- Easier to add features (memory, personality, tools)

**Future Extensibility**
- Memory integration point
- Personality application point
- Tool execution point
- Skill selection point

**Testability**
- Can test conversation flow independently
- Mock AI Engine for conversation tests
- Isolate orchestration bugs

### Alternatives Considered

**Direct API → AI Engine**
- Pros: Simpler initial implementation
- Cons: No place for orchestration logic
- Rejected: Would require refactoring later

**Multiple Orchestrators**
- Pros: Specialized orchestrators per feature
- Cons: Complexity, coordination issues
- Rejected: Violates single responsibility

### Implications

**Technical**
- Additional layer in call stack
- Must define clear orchestration interface
- Slight performance overhead

**Development**
- More complex initial architecture
- Easier to add features later
- Clear extension points

**Maintenance**
- Orchestration logic centralized
- Easier to debug conversation issues
- Consistent behavior across features

---

## Decision 4: Skills-Based System

**Date**: July 2026
**Status**: Designed (Phase 2)

### Decision
Implement a skills-based system where different AI personas specialize for specific tasks rather than a single general-purpose AI.

### Why This Decision

**Specialization**
- Different tasks require different approaches
- Better quality for specialized tasks
- Clearer user expectations

**User Control**
- Users can choose appropriate skill
- Explicit skill selection for specific tasks
- Predictable behavior

**Extensibility**
- Easy to add new skills
- Community can create skills
- Marketplace for skills

### Alternatives Considered

**Single General AI**
- Pros: Simpler, no skill selection
- Cons: Lower quality for specialized tasks
- Rejected: Doesn't meet quality goals

**Adaptive AI**
- Pros: Automatically adapts to context
- Cons: Unpredictable, harder to debug
- Rejected: User control is important

### Implications

**Technical**
- Skill configuration system
- Skill selection logic
- Skill-specific prompts
- Skill personality parameters

**User Experience**
- Skill selection UI
- Skill switching mechanism
- Skill documentation
- Learning curve for users

**Development**
- More complex system
- Need skill design guidelines
- Skill testing framework
- Skill marketplace infrastructure

---

## Decision 5: SQLite for Local Storage

**Date**: July 2026
**Status**: Designed (Phase 3)

### Decision
Use SQLite as the primary local database for storing memories, conversations, and user data.

### Why This Decision

**Simplicity**
- No separate database server required
- Single file storage
- Easy backup and migration

**Performance**
- Fast for local applications
- No network overhead
- Efficient for typical AI companion workload

**Portability**
- Cross-platform support
- Single file database
- Easy to copy/move

**Reliability**
- ACID compliance
- Mature and stable
- Excellent Python support

### Alternatives Considered

**PostgreSQL/MySQL**
- Pros: More features, better for scaling
- Cons: Requires separate server, overkill for local
- Rejected: Too complex for local-first app

**DuckDB**
- Pros: Better analytics performance
- Cons: Less mature, smaller ecosystem
- Rejected: SQLite is more proven

**File-Based (JSON/CSV)**
- Pros: Simple, human-readable
- Cons: No querying, poor performance
- Rejected: Doesn't meet performance needs

### Implications

**Technical**
- Schema design critical
- Migration strategy needed
- Backup/restore implementation
- Index optimization

**Scalability**
- Limited to single-machine
- May need sharding for very large datasets
- Consider future migration path

**Development**
- SQL skills required
- ORM or raw SQL decision
- Database versioning strategy

---

## Decision 6: Flutter for Cross-Platform UI

**Date**: July 2026
**Status**: Implemented

### Decision
Use Flutter as the UI framework for all client applications (desktop, mobile, web).

### Why This Decision

**Code Reuse**
- Single codebase for all platforms
- Consistent UI/UX across platforms
- Faster development cycle

**Performance**
- Native performance
- Fast rendering
- Smooth animations

**Developer Experience**
- Hot reload for rapid development
- Rich widget library
- Strong tooling support

**Future-Proof**
- Active development by Google
- Growing ecosystem
- Long-term viability

### Alternatives Considered

**Native (Swift/Kotlin)**
- Pros: Best platform integration
- Cons: Multiple codebases, higher cost
- Rejected: Too expensive for small team

**React Native**
- Pros: Large ecosystem, JavaScript
- Cons: Performance issues, bridge overhead
- Rejected: Flutter has better performance

**Electron (Desktop Only)**
- Pros: Web technologies
- Cons: Heavy, poor mobile support
- Rejected: Need mobile support

### Implications

**Technical**
- Dart language learning curve
- Flutter ecosystem dependencies
- Platform-specific code for some features

**Development**
- Single frontend team
- Cross-platform testing
- Platform-specific optimizations

**Maintenance**
- Single codebase to maintain
- Flutter updates affect all platforms
- Platform-specific bug handling

---

## Decision 7: FastAPI for Backend

**Date**: July 2026
**Status**: Implemented

### Decision
Use FastAPI as the Python web framework for the backend API.

### Why This Decision

**Performance**
- Async support for better performance
- Fast execution
- Efficient handling of concurrent requests

**Developer Experience**
- Automatic API documentation (Swagger)
- Type hints for validation
- Easy to use and learn

**Modern Python**
- Uses latest Python features
- Async/await support
- Pydantic integration

**Ecosystem**
- Growing popularity
- Good middleware support
- Easy testing

### Alternatives Considered

**Flask**
- Pros: Mature, large ecosystem
- Cons: Synchronous by default, slower
- Rejected: FastAPI is more modern and performant

**Django**
- Pros: Full-featured, batteries included
- Cons: Overkill for API-only backend
- Rejected: Too heavy for our needs

**Tornado**
- Pros: Async, fast
- Cons: Less popular, fewer features
- Rejected: FastAPI has better ecosystem

### Implications

**Technical**
- Async programming model
- Pydantic for validation
- Automatic OpenAPI docs

**Development**
- Faster development with auto-docs
- Type safety catches errors early
- Easy to test

**Deployment**
- ASGI server required (Uvicorn)
- Need to handle async properly
- Monitoring async operations

---

## Decision 8: Modular Engine Architecture

**Date**: July 2026
**Status**: Designed

### Decision
Design the system with independent engines (Skills, Memory, Prompt, AI, Provider, Voice, Vision, Knowledge, Plugin) that can be developed and replaced independently.

### Why This Decision

**Maintainability**
- Clear separation of concerns
- Easier to understand and modify
- Isolated bug fixes

**Testability**
- Each engine can be tested independently
- Mock dependencies easily
- Faster test execution

**Extensibility**
- Easy to add new engines
- Can replace engines without affecting others
- Plugin system for third-party extensions

**Team Collaboration**
- Different teams can work on different engines
- Clear interfaces reduce coordination overhead
- Parallel development possible

### Alternatives Considered

**Monolithic Architecture**
- Pros: Simpler initial design
- Cons: Hard to maintain, test, extend
- Rejected: Doesn't scale with complexity

**Microservices**
- Pros: Independent deployment, scaling
- Cons: Too complex for local-first app
- Rejected: Overkill for single-machine deployment

### Implications

**Technical**
- More complex initial architecture
- Need clear interface definitions
- Inter-engine communication overhead

**Development**
- Higher initial complexity
- Easier long-term maintenance
- Requires discipline to maintain boundaries

**Performance**
- Some overhead from inter-engine calls
- Can be optimized with caching
- Generally acceptable for AI workloads

---

## Decision 9: Ollama as Default AI Provider

**Date**: July 2026
**Status**: Implemented

### Decision
Use Ollama as the default local AI inference engine, with plans to support llama.cpp in the future.

### Why This Decision

**Ease of Use**
- Simple installation and setup
- Easy model management
- User-friendly CLI

**Model Support**
- Wide range of models available
- Easy to add new models
- Active model updates

**API Simplicity**
- RESTful API
- Simple request/response format
- Good documentation

**Community**
- Active development
- Growing community
- Good support

### Alternatives Considered

**llama.cpp**
- Pros: Very fast, efficient
- Cons: More complex setup, fewer models
- Rejected: Will add as secondary provider

**LocalAI**
- Pros: OpenAI-compatible API
- Cons: Less mature, smaller community
- Rejected: Ollama has better ecosystem

**Direct Model Integration**
- Pros: Maximum control
- Cons: High maintenance burden
- Rejected: Don't want to maintain model code

### Implications

**Technical**
- Dependency on Ollama service
- Must handle Ollama unavailability
- Model version management

**User Experience**
- Users must install Ollama
- Model download required
- Hardware requirements vary by model

**Development**
- Easy to test with Ollama
- Can switch providers via config
- Must maintain provider abstraction

---

## Decision 10: Clean Architecture Principles

**Date**: July 2026
**Status**: Implemented

### Decision
Follow clean architecture principles with clear layer separation and dependency injection throughout the codebase.

### Why This Decision

**Maintainability**
- Clear structure makes code easier to understand
- Changes are localized to specific layers
- Easier to onboard new developers

**Testability**
- Dependencies can be mocked
- Each layer can be tested independently
- Higher test coverage possible

**Flexibility**
- Easy to swap implementations
- Can change one layer without affecting others
- Supports multiple configurations

**Quality**
- Enforces best practices
- Reduces coupling
- Improves code organization

### Alternatives Considered

**Layered Architecture (Less Strict)**
- Pros: Simpler to implement
- Cons: More coupling, harder to maintain
- Rejected: Doesn't provide enough structure

**Onion Architecture**
- Pros: Very strict dependency rules
- Cons: Overly complex for our needs
- Rejected: Clean architecture is sufficient

### Implications

**Technical**
- More initial boilerplate
- Need dependency injection framework
- Steeper learning curve

**Development**
- Slower initial development
- Faster long-term development
- Requires discipline to maintain

**Code Quality**
- Better organized code
- Fewer bugs from coupling
- Easier refactoring

---

## Decision 11: Pydantic for All API Models

**Date**: July 2026
**Status**: Implemented

### Decision
Use Pydantic models for all API request/response validation throughout the backend.

### Why This Decision

**Type Safety**
- Automatic type validation
- Catches type errors early
- Clear type definitions

**Documentation**
- Auto-generated API docs
- Schema validation
- Clear request/response structure

**Developer Experience**
- IDE autocomplete
- Type hints
- Self-documenting code

**Error Handling**
- Automatic validation errors
- Clear error messages
- Consistent error format

### Alternatives Considered

**Manual Validation**
- Pros: No dependency
- Cons: Error-prone, repetitive
- Rejected: Too much boilerplate

**Other Validation Libraries**
- Pros: Different features
- Cons: Pydantic is standard with FastAPI
- Rejected: Pydantic integrates best

### Implications

**Technical**
- Pydantic dependency
- Must define models for all endpoints
- Validation happens automatically

**Development**
- Slower initial development (define models)
- Faster debugging (validation errors)
- Better IDE support

**API Quality**
- Consistent error handling
- Auto-generated documentation
- Type-safe API contracts

---

## Decision 12: No Hardcoded Prompts

**Date**: July 2026
**Status**: Designed (Prompt Engine)

### Decision
All prompts must be stored in the Prompt Engine, never hardcoded in code. This enables prompt iteration without code changes.

### Why This Decision

**Flexibility**
- Can update prompts without redeploying
- A/B test different prompts
- Easy to iterate on prompt quality

**Maintainability**
- Prompts in one place
- Easy to find and modify
- Version control for prompts

**Transparency**
- Prompts are visible and editable
- Users can customize prompts
- Clear what AI is being told

**Testing**
- Can test different prompts
- Prompt performance tracking
- Easy to rollback bad prompts

### Alternatives Considered

**Hardcoded Prompts**
- Pros: Simpler initial implementation
- Cons: Requires code changes for updates
- Rejected: Violates principle of replaceability

**Template Strings in Code**
- Pros: Some flexibility
- Cons: Still requires code changes
- Rejected: Not sufficient for prompt iteration

### Implications

**Technical**
- Need Prompt Engine infrastructure
- Prompt storage and retrieval
- Prompt versioning

**Development**
- Additional complexity
- Better long-term maintainability
- Clear separation of prompts

**User Experience**
- Potential for prompt customization
- Better prompt quality over time
- Transparency in AI behavior

---

## Decision 13: Conversation Manager as Single Entry Point

**Date**: July 2026
**Status**: Implemented

### Decision
All conversation requests must go through Conversation Manager. No component should bypass it to call AI Engine or other engines directly.

### Why This Decision

**Consistency**
- All conversations follow same flow
- Consistent behavior across features
- Easier to debug conversation issues

**Orchestration**
- Single place for conversation logic
- Memory integration point
- Skill selection point

**Security**
- Can enforce policies at one point
- Consistent validation
- Easier to add security features

**Monitoring**
- Single point for logging
- Consistent metrics
- Easier to track conversation patterns

### Alternatives Considered

**Multiple Entry Points**
- Pros: More flexibility
- Cons: Inconsistent behavior, harder to maintain
- Rejected: Violates single responsibility

**Direct AI Engine Access**
- Pros: Simpler for some features
- Cons: Bypasses orchestration
- Rejected: Would fragment conversation logic

### Implications

**Technical**
- Conversation Manager becomes critical component
- Must handle all conversation types
- Performance bottleneck risk

**Development**
- All features must use Conversation Manager
- Clear extension points
- Consistent API

**Maintenance**
- Single place for conversation logic
- Easier to add features
- Easier to debug issues

---

## Decision 14: Memory Independence from AI Model

**Date**: July 2026
**Status**: Designed (Phase 3)

### Decision
Memory storage and retrieval must be completely independent from the AI model implementation. Memory should work regardless of which AI provider is used.

### Why This Decision

**Portability**
- Can switch AI models without losing memories
- Memories are model-agnostic
- Future-proof for new AI technologies

**Privacy**
- User data not tied to specific AI service
- Can export/import memories
- User owns their memories

**Flexibility**
- Can use different memory strategies
- Memory optimization independent of AI
- Can change memory without affecting AI

**Testing**
- Can test memory independently
- Mock memory for AI tests
- Isolate memory issues

### Alternatives Considered

**Model-Specific Memory**
- Pros: Optimized for specific model
- Cons: Tied to model, not portable
- Rejected: Violates principle of independence

**Cloud-Hosted Memory**
- Pros: Easier sync
- Cons: Privacy concerns, dependency
- Rejected: Violates local-first principle

### Implications

**Technical**
- Need independent memory system
- Memory schema must be generic
- Memory retrieval must be model-agnostic

**Development**
- Additional complexity
- Better long-term flexibility
- Clear separation of concerns

**User Experience**
- Memories persist across model changes
- Can export/import memories
- User has full control

---

## Decision 15: Dark Theme as Default

**Date**: July 2026
**Status**: Implemented

### Decision
Implement dark theme as the default UI theme for the Flutter application.

### Why This Decision

**User Preference**
- Dark theme is popular among developers
- Easier on eyes for extended use
- Modern aesthetic

**Battery Life**
- OLED screens use less power with dark theme
- Better for laptop battery life
- Environmentally friendly

**Focus**
- Reduces eye strain
- Less visual fatigue
- Better for long conversations

**Differentiation**
- Many apps default to light theme
- Dark theme stands out
- Appeals to tech-savvy users

### Alternatives Considered

**Light Theme Default**
- Pros: Traditional, familiar
- Cons: Less popular with target audience
- Rejected: Doesn't match user preferences

**System Theme**
- Pros: Respects user system preference
- Cons: Inconsistent across devices
- Rejected: Want consistent experience

### Implications

**Technical**
- Must ensure good contrast
- Test on different screens
- Consider light theme option later

**User Experience**
- May not appeal to all users
- Should add theme toggle later
- Need to ensure accessibility

**Design**
- Careful color selection
- Good contrast ratios
- Readable in various lighting

---

## Future Decisions

This document will be updated as new major technical decisions are made. Each decision should follow this format:

- Decision description
- Date made
- Current status
- Why this decision (rationale)
- Alternatives considered
- Implications

This ensures project history is preserved and future developers understand the reasoning behind architectural choices.
