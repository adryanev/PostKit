---
status: complete
priority: p1
issue_id: "003"
tags: [code-review, security, configuration]
dependencies: []
---

# Missing Network Entitlements File

## Problem Statement

The app has App Sandbox enabled in the Xcode project but no `.entitlements` file exists in the repository. Without `com.apple.security.network.client = true`, the app cannot make outbound HTTP requests under the macOS sandbox — which is its entire purpose.

**Why it matters:** The app literally cannot function as an HTTP client without this entitlement. This is a ship-blocking issue.

## Findings

- **No `.entitlements` file found** in the project directory
- App Sandbox is enabled in build settings
- The app's core function (sending HTTP requests) requires `com.apple.security.network.client`
- **Confirmed by:** Security Sentinel agent

## Proposed Solutions

### Option A: Create entitlements file (Recommended)
- Create `PostKit/PostKit.entitlements` with required entitlements
- Add `com.apple.security.network.client = true`
- Add `com.apple.security.files.user-selected.read-write = true` (for file import/export)
- Reference it in Xcode project build settings
- **Pros:** Straightforward fix, standard practice
- **Cons:** None
- **Effort:** Small
- **Risk:** Low

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files:** New `PostKit.entitlements`, Xcode project file
- **Components:** App configuration, sandboxing

## Acceptance Criteria

- [x] `.entitlements` file exists with `com.apple.security.network.client = true`
- [x] File import/export entitlement included
- [x] Xcode project references the entitlements file
- [ ] App can send HTTP requests when built and run

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-13 | Created from code review | Ship-blocking: app cannot make HTTP requests without this |
| 2026-02-13 | Resolved: created entitlements file and updated pbxproj | Added CODE_SIGN_ENTITLEMENTS to both Debug and Release configs |

## Resources

- Branch: `feat/mvp-architecture`
