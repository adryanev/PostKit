---
status: complete
priority: p1
issue_id: "002"
tags: [code-review, security]
dependencies: []
---

# Auth Credentials Stored in Plaintext SwiftData

## Problem Statement

`AuthConfig` stores Bearer tokens, Basic auth passwords, and API key values as plain strings in SwiftData. SwiftData persists to an unencrypted SQLite file on disk. Any process or tool with file system access can read these credentials.

Additionally, `Variable.isSecret` is purely cosmetic — the value is still stored in plaintext SwiftData alongside non-secret variables.

**Why it matters:** Users will paste real API keys and tokens into this app. Storing them in plaintext SQLite is a credential leak risk, especially on shared machines or if the SQLite file is included in backups.

## Findings

- **AuthType.swift:18-22** — `AuthConfig` struct stores `token`, `password`, `apiKeyValue` as `String`
- **HTTPRequest.swift** — `authConfigData: Data?` stored as JSON blob in SwiftData (still plaintext)
- **Variable.swift:15** — `isSecret: Bool` flag exists but `value: String` stored in plaintext regardless
- **KeychainManager.swift** — 108-line Keychain wrapper exists but is NEVER USED anywhere
- **Confirmed by:** Security Sentinel, Architecture Strategist, Pattern Recognition agents

## Proposed Solutions

### Option A: Use the existing KeychainManager (Recommended)
- Store sensitive values (tokens, passwords, API keys) in Keychain via `KeychainManager`
- Store only a Keychain reference key in SwiftData
- Use `isSecret` flag on Variable to route to Keychain
- **Pros:** KeychainManager already implemented, minimal new code
- **Cons:** Need migration for existing data, Keychain has size limits
- **Effort:** Medium
- **Risk:** Low

### Option B: Encrypt sensitive fields in SwiftData
- Use CryptoKit to encrypt sensitive values before storing in SwiftData
- Derive encryption key from device Keychain
- **Pros:** All data in one store, simpler queries
- **Cons:** More code, key management complexity
- **Effort:** Medium
- **Risk:** Medium

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files:** `AuthType.swift`, `HTTPRequest.swift`, `Variable.swift`, `KeychainManager.swift`
- **Components:** Authentication, data persistence, secrets management

## Acceptance Criteria

- [ ] Bearer tokens stored in Keychain, not SQLite
- [ ] Basic auth passwords stored in Keychain
- [ ] API key values stored in Keychain
- [ ] Secret variables stored in Keychain
- [ ] Existing KeychainManager integrated or replaced
- [ ] SwiftData stores only reference keys for secrets

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-13 | Created from code review | KeychainManager exists but is dead code — wire it up |
| 2026-02-13 | Implemented Option A | Wired KeychainManager into Variable.secureValue and AuthConfig.storeSecrets/retrieveSecrets/deleteSecrets |

## Resources

- Branch: `feat/mvp-architecture`
