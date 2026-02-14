---
status: pending
priority: p3
issue_id: "022"
tags: [code-review, build, size]
dependencies: []
---

# 022: iOS xcframework Slices Unnecessary

## Problem Statement

The vendored `curl.xcframework` includes iOS simulator and device architecture slices, but PostKit is a macOS-only application (minimum deployment target: macOS 14.0 Sonoma). These extra slices add significant size to the repository (estimated ~100MB+) without providing any value, increasing clone times, CI build times, and disk usage for all contributors.

## Findings

- **File:** `Frameworks/curl.xcframework`
- **Severity:** P3 (Nice-to-have)
- **Category:** Build, repository size

The xcframework bundle contains architecture slices for platforms that PostKit does not target:
- iOS device (arm64)
- iOS Simulator (arm64, x86_64)
- macOS (arm64, x86_64) -- this is the only needed slice

Each platform slice contains the full libcurl static library plus headers, multiplying the storage footprint unnecessarily. This impacts:
- **Git clone time:** All contributors must download the full xcframework including unused slices
- **Repository size:** Bloats the git history with large binary artifacts
- **CI/CD:** Slower checkout and potentially slower builds
- **Disk usage:** Unnecessary storage on developer machines

## Proposed Solutions

### Option A: Rebuild xcframework with only macOS slice (Recommended)

Rebuild the xcframework using `xcodebuild -create-xcframework` with only the macOS architecture slice.

**Pros:**
- Dramatically reduces framework size (estimated 60-70% reduction)
- Faster git clone and CI checkout
- Cleaner build configuration
- Accurately reflects the project's platform targets

**Cons:**
- Requires rebuilding the xcframework (one-time effort)
- If PostKit ever targets iOS in the future, the framework must be rebuilt with additional slices
- Need to ensure the libcurl build configuration for macOS is preserved correctly

**Effort:** Low-medium (1-2 hours, depending on familiarity with xcframework creation)
**Risk:** Low -- well-documented process, can verify with a clean build

### Option B: Use .gitattributes LFS for the framework

Keep all slices but move the xcframework to Git LFS to reduce the impact on repository cloning.

**Pros:**
- Reduces impact on git clone (LFS downloads on demand)
- Preserves all architecture slices for potential future use
- No need to rebuild the framework

**Cons:**
- Does not actually reduce the framework size
- Requires Git LFS setup for all contributors
- Adds infrastructure dependency (LFS server storage)
- Still wastes disk space after checkout
- Does not address the root issue (unnecessary slices)

**Effort:** Low (30 minutes)
**Risk:** Low -- but requires LFS infrastructure

## Recommended Action

<!-- To be filled after review -->

## Technical Details

Current xcframework structure (expected):
```
curl.xcframework/
├── Info.plist
├── ios-arm64/
│   └── libcurl.a (+ headers)
├── ios-arm64_x86_64-simulator/
│   └── libcurl.a (+ headers)
└── macos-arm64_x86_64/
    └── libcurl.a (+ headers)
```

Target xcframework structure:
```
curl.xcframework/
├── Info.plist
└── macos-arm64_x86_64/
    └── libcurl.a (+ headers)
```

To rebuild with macOS only:
```bash
# Build libcurl for macOS (if building from source)
# Or extract the macOS slice from the existing xcframework

# Create new xcframework with only macOS
xcodebuild -create-xcframework \
    -library path/to/macos/libcurl.a \
    -headers path/to/include/ \
    -output curl.xcframework
```

Size verification:
```bash
# Check current size
du -sh Frameworks/curl.xcframework/

# Check per-slice sizes
du -sh Frameworks/curl.xcframework/*/
```

## Acceptance Criteria

- [ ] `curl.xcframework` contains only macOS architecture slices (arm64, x86_64)
- [ ] iOS device and simulator slices are removed
- [ ] Framework size is significantly reduced
- [ ] Project builds successfully with the trimmed framework
- [ ] All existing tests continue to pass
- [ ] Linking against libcurl works correctly on both Apple Silicon and Intel Macs

## Work Log

| Date | Action | Notes |
|------|--------|-------|
| 2026-02-14 | Created | Initial finding from PR #2 code review |

## Resources

- PR #2: feat: Replace HTTP client engine with libcurl
- File: `PostKit/PostKit/Frameworks/curl.xcframework`
- [Apple: Creating a Multi-Platform Binary Framework Bundle](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)
- [xcodebuild -create-xcframework documentation](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)
