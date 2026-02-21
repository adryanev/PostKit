---
review_agents: [code-simplicity-reviewer, security-sentinel, performance-oracle, architecture-strategist]
plan_review_agents: [code-simplicity-reviewer]
---

# Review Context

PostKit is a native macOS HTTP client (like Postman/Insomnia) built with SwiftUI and SwiftData.

**Key architecture:**
- MVVM with `@Observable` ViewModels
- Factory 2.5.x for DI (`@Injected` properties must be `@ObservationIgnored` in `@Observable` classes)
- Actor-based HTTP client (`CurlHTTPClient`)
- SwiftData for persistence (`@Model`, `@Query`)
- Keychain for secrets via `KeychainManager`

**Critical patterns to check:**
- All `@Injected` in `@Observable` classes must have `@ObservationIgnored`
- `@MainActor` isolation for SwiftUI views and ModelContext access
- `Sendable` conformance for types crossing concurrency boundaries
- No secrets in logs or committed files
