---
title: "feat: Replace HTTP client engine with libcurl"
type: feat
date: 2026-02-13
brainstorm: docs/brainstorms/2026-02-13-http-client-engine-brainstorm.md
---

## Enhancement Summary

**Deepened on:** 2026-02-13
**Sections enhanced:** 8 (Architecture, Technical Decisions, Constraints, Phases 1–4, Risk Analysis)
**Review agents used:** Architecture Strategist, Performance Oracle, Security Sentinel, Pattern Recognition Specialist, Code Simplicity Reviewer, UI/UX Explorer, Best Practices Researcher

### Key Improvements

1. **Critical architecture fix**: Engine toggle via `@AppStorage` + `EnvironmentKey.defaultValue` is broken — `static let` cannot react to preference changes. Simplified to remove the toggle entirely (YAGNI) and inject `CurlHTTPClient` directly from `PostKitApp.body`.
2. **Thread safety hardened**: `isCancelled` and `didResume` flags must use `OSAllocatedUnfairLock<Bool>` — plain `Bool` is not safe across GCD queue + Swift concurrency boundaries.
3. **Simplified handle lifecycle**: Fresh handle per request instead of reuse via `curl_easy_reset`. Eliminates option leakage risk and the need for `applyBaseOptions()` helper. Small performance trade-off is acceptable for an API client sending one request at a time.
4. **Security hardening**: Added `CURLOPT_PROTOCOLS_STR = "http,https"` (prevent protocol abuse), `CURLOPT_SSLVERSION` minimum TLS 1.2, and `CURLOPT_MAXFILESIZE_LARGE` response size limit.
5. **YAGNI simplifications**: Removed engine toggle + Preferences window, timing persistence in HistoryEntry, and network integration tests. Kept scope focused on the core engine swap.

### New Considerations Discovered

- **Pre-existing security bugs**: `CurlImportSheet` doesn't route imported credentials to Keychain; `getActiveEnvironmentVariables()` uses `.value` instead of `.secureValue` — both are out of scope but flagged for follow-up.
- **Export compliance**: Setting `ITSAppUsesNonExemptEncryption = NO` with bundled OpenSSL needs legal review — OpenSSL qualifies as encryption under U.S. export rules but may fall under an exemption.
- **OpenSSL patching obligation**: Bundling OpenSSL creates an ongoing security maintenance burden — must update curl-apple xcframework when CVEs are published.
- **`curl_slist` lifetime**: Must scope `defer { curl_slist_free_all }` to encompass `curl_easy_perform`, not just the slist creation block.

---

# feat: Replace HTTP Client Engine with libcurl

## Overview

Replace PostKit's `URLSessionHTTPClient` with a new `CurlHTTPClient` backed by libcurl (via the [greatfire/curl-apple](https://github.com/greatfire/curl-apple) xcframework). This gives PostKit full curl feature parity — detailed timing breakdowns, advanced compression (brotli/zstd), SSL skip-verify, proxy support, and exact curl behavior reproduction. The existing `HTTPClientProtocol` abstraction means only the engine layer changes; views, models, and history remain untouched.

## Problem Statement / Motivation

PostKit is an API client where users paste curl commands expecting identical behavior. URLSession's opinionated defaults (automatic cookie handling, ATS enforcement, hidden headers like `User-Agent`) make exact curl reproduction difficult. Additionally:

- **Timing**: Only total duration is captured (`CFAbsoluteTimeGetCurrent` diff). No DNS/TCP/TLS/TTFB breakdown.
- **Compression**: URLSession only supports gzip/deflate. No brotli or zstd.
- **SSL**: Skip-verify (`curl -k`) requires awkward `URLSessionDelegate` + ATS exceptions.
- **The UI is ready**: `ResponseTimingView` already has a "Detailed timing metrics coming soon" placeholder.

## Proposed Solution

Create a new `CurlHTTPClient` actor conforming to `HTTPClientProtocol`, backed by libcurl's easy API. Statically link libcurl via the curl-apple xcframework. Keep `URLSessionHTTPClient` as a fallback.

## Technical Approach

### Architecture

```
┌─────────────────────────────────────────────────┐
│  Views / ViewModels (no changes)                │
│  RequestDetailView → RequestViewModel           │
│       ↓ @Environment(\.httpClient)              │
├─────────────────────────────────────────────────┤
│  HTTPClientProtocol                             │
│  ┌──────────────────┐  ┌─────────────────────┐  │
│  │ URLSessionHTTP   │  │ CurlHTTPClient      │  │
│  │ Client (fallback)│  │ (new, primary)      │  │
│  └──────────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────┤
│  CurlShims (C module)                           │
│  curl_easy_setopt_string/long/pointer/...       │
├─────────────────────────────────────────────────┤
│  curl-apple xcframework (libcurl + OpenSSL)     │
│  Static library — linked at build time          │
└─────────────────────────────────────────────────┘
```

#### Research Insights — Architecture

**Critical Fix: Engine injection**
The original plan had `HTTPClientKey.defaultValue` as `static let` (which it must be per SwiftUI's `EnvironmentKey`), with Phase 4 adding an `@AppStorage`-driven toggle. This is architecturally broken — a `static let` is evaluated once and never re-read. The simplest fix (and the YAGNI-recommended approach) is to **remove the engine toggle entirely** and inject `CurlHTTPClient` directly from `PostKitApp.body`:

```swift
// PostKitApp.swift
@main struct PostKitApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.httpClient, CurlHTTPClient())
        }
    }
}
```

If a fallback is ever needed, it can be added as a runtime check in `PostKitApp.body` (not as a user-facing preference).

**Module map vs. bridging header**
An alternative to a bridging header is a `module.modulemap` inside the CurlShims directory. This is cleaner for SPM compatibility and avoids the global bridging header, but a bridging header works fine for a single-target Xcode project. Either approach is valid — the plan uses a bridging header for simplicity.

**CurlShims placement**
CurlShims could live as a top-level directory (`CurlShims/`) rather than nested under `PostKit/PostKit/Services/`. This makes it easier to extract as a standalone module later. However, keeping it under `Services/` is consistent with the existing project structure.

---

### Key Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Async bridging | `DispatchQueue.async` + continuation | `Task.detached` blocks cooperative pool → deadlocks. GCD pool is separate. |
| C variadic shim | Typed C wrappers per param type | Swift cannot import `curl_easy_setopt` (variadic). Standard workaround. |
| Handle lifecycle | **Fresh handle per request** *(changed)* | Eliminates option leakage risk from `curl_easy_reset` not clearing all state. No `applyBaseOptions()` helper needed. Connection cache trade-off is acceptable — PostKit sends one request at a time. |
| Cancellation | `CURLOPT_XFERINFOFUNCTION` + `isCancelled` flag | `CURLOPT_PROGRESSFUNCTION` is deprecated. Return non-zero to abort. |
| Thread safety | `OSAllocatedUnfairLock<Bool>` for flags *(added)* | `isCancelled` and `didResume` are read/written across GCD queue + Swift concurrency. Plain `Bool` is not safe — use `OSAllocatedUnfairLock` from `os` module. |
| Body data | `CURLOPT_COPYPOSTFIELDS` *(changed)* | Tells libcurl to copy the body data internally, removing the lifetime pinning requirement. Slight memory overhead but eliminates an entire class of use-after-free bugs. |
| Response streaming | `CURLOPT_WRITEFUNCTION` → temp file for >1MB | Matches existing `URLSessionHTTPClient` threshold behavior. |
| TLS backend | OpenSSL 3.6.0 (bundled in curl-apple) | SecureTransport dropped from curl 8.15.0+. OpenSSL required. |
| CA certificates | Bundle `cacert.pem` from xcframework | OpenSSL doesn't use macOS Keychain. Must provide CA bundle at runtime. |
| Protocol restriction | `CURLOPT_PROTOCOLS_STR = "http,https"` *(added)* | Prevents `file://`, `ftp://`, `gopher://` protocol abuse if a malicious URL is pasted. |
| TLS minimum | `CURLOPT_SSLVERSION = CURL_SSLVERSION_TLSv1_2` *(added)* | Prevents downgrade to TLS 1.0/1.1. |
| Response size limit | `CURLOPT_MAXFILESIZE_LARGE = 100MB` *(added)* | Prevents unbounded memory/disk use from enormous responses. |

### Important Constraints

1. **No HTTP/2**: curl-apple is built with `--without-nghttp2`. Only HTTP/1.1 for now.
2. **Binary size**: curl-apple xcframework is ~70MB (compressed) due to bundled OpenSSL.
3. **`curl_global_init` must be called once before any handle creation** — Use a `static let` inside `CurlHTTPClient` (not `PostKitApp.init()`) to guarantee ordering, since `HTTPClientKey.defaultValue` is evaluated lazily and may run before `PostKitApp.init()`.
4. **Handle serialization**: A curl easy handle is NOT thread-safe. With fresh-handle-per-request, the serial GCD queue still ensures only one `curl_easy_perform` runs at a time. (PostKit sends one request at a time in practice.)
5. **`CURLOPT_COPYPOSTFIELDS`** — Use instead of `CURLOPT_POSTFIELDS`. Libcurl copies the body data internally, removing the lifetime pinning burden from `CurlTransferContext`.
6. **`curl_slist` for headers must outlive `curl_easy_perform`** — Scope the `defer { curl_slist_free_all(headerList) }` to encompass the entire perform call, not just the slist creation block. Libcurl does NOT copy header strings.
7. **`CURLOPT_NOSIGNAL = 1`** must be set on every handle — prevents SIGALRM crashes during DNS timeout in multithreaded apps.
8. **Continuation double-resume prevention** — Use `OSAllocatedUnfairLock<Bool>` for the `didResume` flag in `CurlTransferContext` to ensure the `CheckedContinuation` is resumed exactly once (handles the race between perform completion and Task cancellation).
9. **`Unmanaged` pointer safety** — Use `Unmanaged.passRetained(context).toOpaque()` when passing `CurlTransferContext` to C callbacks, and `Unmanaged.fromOpaque(ptr).takeRetainedValue()` after perform completes. This ensures the context isn't deallocated during the callback. *(Added per security review)*
10. **OpenSSL patching obligation** — Bundling OpenSSL means PostKit must track curl-apple releases for security patches. curl-apple auto-updates within 24h of upstream curl releases, but the app must be rebuilt and re-released. *(Added per security review)*

---

## Implementation Phases

### Phase 1: xcframework Integration + C Shims

**Goal:** Get libcurl callable from Swift. No HTTP logic yet — just verify the build pipeline.

#### Tasks

- [ ] Download `curl.xcframework.zip` from [curl-apple releases](https://github.com/greatfire/curl-apple/releases) (v8.18.0)
- [ ] Add xcframework to Xcode project under `Frameworks, Libraries, and Embedded Content` → "Do Not Embed" (static library)
- [ ] Add required linker dependencies:
  - `libz` (system — for compression)
  - `libldap` (system — macOS only)
  - `SystemConfiguration.framework` (macOS)
- [ ] Create C shim module at `PostKit/Services/CurlShims/`:
  - `include/CurlShims.h` — typed wrappers for `curl_easy_setopt` and `curl_easy_getinfo`
  - `CurlShims.c` — trivial implementations delegating to the variadic originals
- [ ] Set up bridging header (`PostKit-Bridging-Header.h`) that imports `<curl/curl.h>` and `"CurlShims.h"`
- [ ] Configure `SWIFT_OBJC_BRIDGING_HEADER` build setting
- [ ] Add `HEADER_SEARCH_PATHS` for curl-apple headers
- [ ] Extract `cacert.pem` from `curl.framework/Resources/cacert.pem`, add to app bundle
- [ ] Ensure `curl_global_init(CURL_GLOBAL_ALL)` runs before any handle creation — use a `static let` inside `CurlHTTPClient`:
  ```swift
  private static let globalInit: Void = { curl_global_init(Int(CURL_GLOBAL_ALL)) }()
  ```
  Reference this in `CurlHTTPClient.init()` to trigger it exactly once.
- [ ] Write a smoke test: create a curl handle, set a URL, clean up — verify it compiles and links

**Files created/modified:**
- `PostKit/PostKit/Services/CurlShims/include/CurlShims.h` (new)
- `PostKit/PostKit/Services/CurlShims/CurlShims.c` (new)
- `PostKit/PostKit/PostKit-Bridging-Header.h` (new)
- `PostKit/PostKit/PostKitApp.swift` (no changes needed — global init is in CurlHTTPClient)
- `PostKit/PostKit.xcodeproj/project.pbxproj` (xcframework, build settings)
- `PostKit/PostKit/Resources/cacert.pem` (new, extracted from xcframework)

**Success criteria:** Project builds, `curl_easy_init()` returns a valid handle, `curl_easy_cleanup()` runs without crash.

#### Research Insights — Phase 1

**C Shim best practices:**
- Keep shims minimal — one typed wrapper per `curl_easy_setopt` parameter type (`string`, `long`, `pointer`, `int64`, `write_callback`, `progress_callback`) and one per `curl_easy_getinfo` return type (`double`, `long`, `string`).
- Use `#pragma once` in the header. Include `<curl/curl.h>` in the shim header so Swift sees the curl types.
- The shim `.c` file is trivial — each function is a single-line delegation to the variadic original.

**cacert.pem verification:**
- After adding `cacert.pem` to the bundle, verify it's accessible at runtime with `Bundle.main.path(forResource: "cacert", ofType: "pem")`. Add a `preconditionFailure` in debug builds if the path is nil.
- curl-apple bundles a Mozilla-derived CA bundle. Check the bundle date against https://curl.se/docs/caextract.html to ensure it's reasonably current.

**Linker flags:**
- If you get duplicate symbol errors, ensure the xcframework is set to "Do Not Embed" (static, not dynamic).
- You may need `-ObjC` linker flag if curl-apple includes ObjC categories (unlikely but check).

---

### Phase 2: CurlHTTPClient Core Implementation

**Goal:** A working `CurlHTTPClient` actor that can send requests and return responses via `HTTPClientProtocol`.

#### Tasks

- [ ] Create `CurlHTTPClient` actor conforming to `HTTPClientProtocol`
  - `execute(_ request: URLRequest, taskID: UUID) async throws -> HTTPResponse`
  - `cancel(taskID: UUID) async`
- [ ] Implement `URLRequest` → curl options conversion:
  - URL: `CURLOPT_URL`
  - HTTP method: `CURLOPT_CUSTOMREQUEST`
  - Headers: `CURLOPT_HTTPHEADER` via `curl_slist_append` — scope `defer { curl_slist_free_all(headerList) }` to encompass `curl_easy_perform` (libcurl does NOT copy header strings)
  - Body: `CURLOPT_COPYPOSTFIELDS` + `CURLOPT_POSTFIELDSIZE_LARGE` — libcurl copies data internally, no lifetime pinning needed *(changed from POSTFIELDS)*
  - Follow redirects: `CURLOPT_FOLLOWLOCATION` + `CURLOPT_MAXREDIRS = 10`
  - Timeout: `CURLOPT_TIMEOUT` (30s request), `CURLOPT_CONNECTTIMEOUT` (10s connect)
  - CA bundle: `CURLOPT_CAINFO` pointing to bundled `cacert.pem` (fail fast with descriptive error if path not found)
  - Compression: `CURLOPT_ACCEPT_ENCODING` = `""` (all supported)
  - Safety: `CURLOPT_NOSIGNAL = 1` (prevent SIGALRM in multithreaded context)
  - Security: `CURLOPT_PROTOCOLS_STR = "http,https"` (prevent file://, ftp://, gopher:// protocol abuse) *(added)*
  - Security: `CURLOPT_SSLVERSION = CURL_SSLVERSION_TLSv1_2` (prevent TLS downgrade) *(added)*
  - Safety: `CURLOPT_MAXFILESIZE_LARGE = 100 * 1024 * 1024` (100MB response limit) *(added)*
- [ ] Implement response collection via `CURLOPT_WRITEFUNCTION`:
  - Non-capturing `@convention(c)` callback
  - `CurlTransferContext` class passed via `CURLOPT_WRITEDATA` using `Unmanaged.passRetained(context).toOpaque()` — call `Unmanaged.fromOpaque(ptr).takeRetainedValue()` after perform completes to balance the retain *(updated per security review)*
  - Pre-allocate `Data(capacity: 65_536)` for response buffer to reduce reallocation churn *(added per performance review)*
  - Dual-path: buffer in `Data` for small responses, stream to temp file for >1MB
- [ ] Implement header collection via `CURLOPT_HEADERFUNCTION`:
  - Separate callback collecting response headers into `[String: String]`
- [ ] Implement async bridging:
  - Dedicated **serial** `DispatchQueue(label: "com.postkit.curl-perform", qos: .userInitiated)` — serial ensures only one `curl_easy_perform` runs at a time
  - `withCheckedThrowingContinuation` wrapping `curl_easy_perform`
  - Use `OSAllocatedUnfairLock<Bool>` for `didResume` flag in `CurlTransferContext` — prevents double-resume of continuation (race between perform completion and Task cancellation). Import `os` module. *(updated per architecture + performance reviews)*
- [ ] Implement cancellation:
  - `CURLOPT_XFERINFOFUNCTION` callback checking `context.isCancelled` (via `OSAllocatedUnfairLock<Bool>`)
  - `CURLOPT_NOPROGRESS = false` to enable callback
  - `withTaskCancellationHandler { ... } onCancel: { context.isCancelled.withLock { $0 = true } }`
  - Track active contexts by `taskID` for external `cancel(taskID:)` calls
- [ ] Implement handle lifecycle (fresh handle per request):
  - Create handle at start of `execute()`, clean up at end *(simplified per simplicity review — eliminates option leakage risk from `curl_easy_reset` not clearing all state)*
  - `curl_slist_free_all` after `curl_easy_perform` returns (scoped by `defer`)
  - `curl_easy_cleanup` after extracting response data and timing
- [ ] Map curl error codes to `HTTPClientError` (comprehensive):
  - `CURLE_ABORTED_BY_CALLBACK` → `CancellationError()`
  - `CURLE_URL_MALFORMAT` → `HTTPClientError.invalidURL`
  - `CURLE_COULDNT_RESOLVE_HOST` → `HTTPClientError.networkError` with "Could not resolve host"
  - `CURLE_COULDNT_CONNECT` → `HTTPClientError.networkError` with "Could not connect to server"
  - `CURLE_OPERATION_TIMEDOUT` → `HTTPClientError.networkError` with "Request timed out"
  - `CURLE_SSL_CONNECT_ERROR` / `CURLE_PEER_FAILED_VERIFICATION` → `HTTPClientError.networkError` with "SSL/TLS error: [curl message]"
  - `CURLE_SEND_ERROR` / `CURLE_RECV_ERROR` → `HTTPClientError.networkError` with "Connection interrupted"
  - `CURLE_GOT_NOTHING` → `HTTPClientError.invalidResponse`
  - All other codes → `HTTPClientError.networkError` with `curl_easy_strerror(code)` message
- [ ] Handle partial response data: discard all data on error (match URLSession behavior)
- [ ] Implement `CurlTransferContext` as a concrete class (mark `@unchecked Sendable` — thread safety managed via `OSAllocatedUnfairLock`):
  - `var responseData: Data` — response body buffer, pre-allocated with `Data(capacity: 65_536)`
  - `var headerLines: [String]` — raw header lines from header callback
  - `let isCancelled: OSAllocatedUnfairLock<Bool>` — set from cancellation handler, read from progress callback *(updated)*
  - `let didResume: OSAllocatedUnfairLock<Bool>` — prevents double continuation resume *(updated)*
  - `var tempFileHandle: FileHandle?` — for large response streaming
  - `var bytesReceived: Int64` — tracks response size
  - Lifetime: created before perform, passed to callbacks via `Unmanaged.passRetained`, balanced with `takeRetainedValue` after perform
  - Note: `requestBodyData` field removed — `CURLOPT_COPYPOSTFIELDS` makes libcurl copy the data internally *(simplified)*
- [ ] Extract response metadata via `curl_easy_getinfo`:
  - `CURLINFO_RESPONSE_CODE` → `statusCode`
  - `CURLINFO_CONTENT_LENGTH_DOWNLOAD_T` → `size`
- [ ] Extract `statusMessage` by parsing the first header line (e.g., `HTTP/1.1 200 OK` → `"OK"`) in the header callback. Fallback to `HTTPURLResponse.localizedString(forStatusCode:)` if parsing fails.

**Files created/modified:**
- `PostKit/PostKit/Services/CurlHTTPClient.swift` (new)
- `PostKit/PostKit/Services/Protocols/HTTPClientProtocol.swift` (no changes — protocol stays as-is)

**Success criteria:** Can send GET/POST requests via `CurlHTTPClient`, receive status codes, headers, and response bodies. Cancellation aborts in-flight requests. Large responses stream to disk.

#### Research Insights — Phase 2

**Async bridging pattern (concrete):**
```swift
func execute(_ request: URLRequest, taskID: UUID) async throws -> HTTPResponse {
    try await withCheckedThrowingContinuation { continuation in
        performQueue.async {
            let handle = curl_easy_init()
            defer { curl_easy_cleanup(handle) }
            // ... set options, callbacks ...
            let code = curl_easy_perform(handle)
            context.didResume.withLock { didResume in
                guard !didResume else { return }
                didResume = true
                if code == CURLE_OK {
                    continuation.resume(returning: buildResponse(handle, context))
                } else {
                    continuation.resume(throwing: mapError(code, handle))
                }
            }
        }
    }
}
```

**Error mapping simplification (per simplicity review):**
Rather than mapping every curl error code individually, use a 3-way branch:
1. `CURLE_OK` → success
2. `CURLE_ABORTED_BY_CALLBACK` → `CancellationError()`
3. Everything else → `HTTPClientError.networkError` with `String(cString: curl_easy_strerror(code))`

This covers all cases without maintaining a mapping table. Specific error codes (URL malformat, SSL errors) are already described well by `curl_easy_strerror`.

**Write callback data flow:**
```
CURLOPT_WRITEFUNCTION callback
    ↓ (ptr, size, nmemb, userdata)
    Unmanaged<CurlTransferContext>.fromOpaque(userdata).takeUnretainedValue()
    ↓
    if context.bytesReceived + nmemb > 1MB && tempFileHandle == nil:
        flush responseData to temp file, open FileHandle
    ↓
    append to responseData or write to FileHandle
    ↓
    return nmemb (bytes consumed)
```

---

### Phase 3: Timing Breakdown + UI

**Goal:** Expose libcurl's detailed timing metrics and display them in `ResponseTimingView`.

#### Tasks

- [ ] Define `TimingBreakdown` struct in `HTTPClientProtocol.swift`:
  ```
  struct TimingBreakdown: Sendable, Codable {
      let dnsLookup: TimeInterval      // CURLINFO_NAMELOOKUP_TIME
      let tcpConnection: TimeInterval   // CURLINFO_CONNECT_TIME - NAMELOOKUP_TIME
      let tlsHandshake: TimeInterval    // CURLINFO_APPCONNECT_TIME - CONNECT_TIME
      let transferStart: TimeInterval   // CURLINFO_STARTTRANSFER_TIME - APPCONNECT_TIME
      let download: TimeInterval        // CURLINFO_TOTAL_TIME - STARTTRANSFER_TIME
      let total: TimeInterval           // CURLINFO_TOTAL_TIME
      let redirectTime: TimeInterval    // CURLINFO_REDIRECT_TIME
  }
  ```
  Note: `Codable` conformance added for potential future persistence *(per architecture review)*.
- [ ] Add `timingBreakdown: TimingBreakdown?` to `HTTPResponse` struct (with default `= nil` so existing construction sites compile unchanged)
- [ ] Update `URLSessionHTTPClient` construction sites (lines 77 and 91) to pass `timingBreakdown: nil` explicitly
- [ ] Extract timing in `CurlHTTPClient` after `curl_easy_perform` via `curl_easy_getinfo_double`
- [ ] Compute delta values with `max(0, delta)` clamping (handles floating-point artifacts, non-TLS requests where APPCONNECT_TIME is 0, and connection-reused requests)
- [ ] Update `ResponseTimingView` in `ResponseViewerPane.swift`:
  - Replace "Detailed timing metrics coming soon" placeholder
  - **Implementation approach**: Use native SwiftUI `GeometryReader` + stacked `Rectangle` bars (no Charts framework dependency needed — keeps it simple) *(per UI exploration: no existing chart components in the project)*
  - Show waterfall-style horizontal bar chart for each phase (DNS → TCP → TLS → TTFB → Download)
  - Use **semantic system colors** (`.blue`, `.green`, `.orange`, `.purple`, `.teal`) — consistent with existing design system that uses no custom Color extensions *(per UI exploration)*
  - Use existing layout constants: 12px padding, 6px corner radius, `.callout`/`.caption` fonts *(per UI exploration)*
  - Show millisecond values next to each bar
  - Keep showing total duration and size as before
  - When all DNS+TCP+TLS phases are near-zero (connection reused), show a "connection reused" label instead of empty bars
  - Graceful fallback: if `timingBreakdown` is nil (URLSession engine), show current simple view
  - **Note**: The timing tab is already wired — `ResponseViewerPane` has Body | Headers | Timing segments
- [ ] ~~Update `HistoryEntry` to optionally store timing breakdown data~~ **DEFERRED (YAGNI)** — Timing data is only useful for the current response. Persisting it in `HistoryEntry` adds complexity (schema migration, Codable encoding) with no immediate user benefit. Can be added later if users request historical timing comparison. *(per simplicity review)*

**Files created/modified:**
- `PostKit/PostKit/Services/Protocols/HTTPClientProtocol.swift` (add `TimingBreakdown`, update `HTTPResponse`)
- `PostKit/PostKit/Services/CurlHTTPClient.swift` (extract timing after perform)
- `PostKit/PostKit/Views/RequestDetail/ResponseViewer/ResponseViewerPane.swift` (new timing UI)

**Success criteria:** Timing waterfall displays accurate per-phase durations. Values match what `curl --write-out` would report for the same request.

#### Research Insights — Phase 3

**Timing waterfall UI pattern (concrete SwiftUI):**
```swift
struct TimingWaterfallView: View {
    let timing: TimingBreakdown

    private var phases: [(String, TimeInterval, Color)] {
        [
            ("DNS", timing.dnsLookup, .blue),
            ("TCP", timing.tcpConnection, .green),
            ("TLS", timing.tlsHandshake, .orange),
            ("TTFB", timing.transferStart, .purple),
            ("Download", timing.download, .teal),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(phases, id: \.0) { name, duration, color in
                HStack(spacing: 8) {
                    Text(name).font(.caption).frame(width: 60, alignment: .trailing)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color)
                            .frame(width: max(2, geo.size.width * (duration / timing.total)))
                    }.frame(height: 12)
                    Text(String(format: "%.1f ms", duration * 1000))
                        .font(.caption).monospacedDigit()
                }
            }
        }
    }
}
```

**Connection reuse detection:**
When DNS + TCP + TLS phases are all < 0.001s (1ms), the connection was reused from a previous request. Show "Connection reused" badge instead of near-zero bars.

**Alternative: Swift Charts `BarMark`**
If Charts framework is acceptable as a dependency, `BarMark(xStart: .value(...), xEnd: .value(...))` creates a proper Gantt chart. However, the `GeometryReader` approach above is simpler and avoids importing a framework for a single view.

---

### Phase 4: Testing & App Store Prep

**Goal:** Add tests, prepare for App Store submission, swap default engine.

#### Tasks

- [ ] ~~Add engine preference~~ **REMOVED (YAGNI)** — The engine toggle is architecturally broken (`EnvironmentKey.defaultValue` is `static let`, cannot react to `@AppStorage`). More importantly, no user needs to switch back to URLSession. If libcurl init fails, fall back automatically — no UI needed. *(per simplicity + architecture reviews)*
- [ ] Swap default engine by injecting from `PostKitApp.body`:
  ```swift
  // PostKitApp.swift
  ContentView()
      .environment(\.httpClient, CurlHTTPClient())
  ```
  - If `CurlHTTPClient.init()` throws (curl_global_init fails), catch and fall back to `URLSessionHTTPClient()` with `os_log` warning
  - `HTTPClientKey.defaultValue` remains `URLSessionHTTPClient()` as a safe default for previews/tests
- [ ] Add `ITSAppUsesNonExemptEncryption` to `Info.plist` — **NOTE: needs legal review** before setting to `YES` or `NO`. Bundled OpenSSL performs encryption; this may qualify for an exemption under TSU Exception (category 5 part 2). *(flagged by security review)*
- [ ] Write tests in `PostKitTests.swift`:
  - `CurlHTTPClientTests` struct using Swift Testing
  - **Unit tests only (no network — per simplicity review):**
    - Test: `CurlTransferContext` write callback buffer management (threshold switching at 1MB)
    - Test: header callback parses multi-value and malformed headers correctly
    - Test: curl error code → `HTTPClientError` mapping (3-way branch)
    - Test: status message extraction from raw header line
    - Test: timing delta computation with `max(0, delta)` clamping
    - Test: `CurlHTTPClient` conforms to `HTTPClientProtocol` (compile-time check)
  - ~~Integration tests~~ **DEFERRED** — Network-dependent tests are flaky in CI. Manual testing against real endpoints during development is sufficient for v1. *(per simplicity review)*
- [ ] Verify App Sandbox compatibility:
  - Test with sandbox enabled (already in entitlements)
  - Confirm `com.apple.security.network.client` entitlement is sufficient for libcurl sockets
- [ ] Test universal binary:
  - Build and run on both Apple Silicon and Intel (Rosetta) if possible

**Files created/modified:**
- `PostKit/PostKit/PostKitApp.swift` (inject `CurlHTTPClient` via `.environment`)
- `PostKit/PostKit/Info.plist` or build settings (encryption compliance key)
- `PostKit/PostKitTests/PostKitTests.swift` (new test struct)

**Success criteria:** All unit tests pass. App runs correctly under sandbox. CurlHTTPClient is default engine. App Store submission requirements met.

#### Research Insights — Phase 4

**Export compliance deep-dive:**
- OpenSSL is classified as encryption software under U.S. Bureau of Industry and Security (BIS) Export Administration Regulations (EAR)
- Apps using encryption solely for authentication (not encryption of user data) may qualify for the "mass market" exemption
- PostKit uses OpenSSL for HTTPS transport — this is standard and widely used in App Store apps
- Recommendation: Set `ITSAppUsesNonExemptEncryption = YES` and file an annual self-classification report (SNAP/R) with BIS. Many developers set `NO` and are fine, but `YES` + report is the legally correct path when bundling OpenSSL.
- Reference: https://developer.apple.com/help/app-store-connect/reference/export-compliance-documentation-for-encryption/

**Testing strategy:**
- Unit-test the C callback functions by creating a `CurlTransferContext`, calling the write/header callbacks directly with test data, and asserting the context state. No curl handle needed.
- For timing delta tests, construct `TimingBreakdown` with known values (including edge cases: zeros, negative deltas, very large values) and verify the `max(0, delta)` clamping.

**Pre-existing security issues (out of scope, tracked for follow-up):**
- `CurlImportSheet.swift`: Imported curl commands with `-u user:pass` or `--header "Authorization: Bearer ..."` store credentials in plain SwiftData fields, not Keychain.
- `VariableInterpolator.swift` → `getActiveEnvironmentVariables()`: Uses `variable.value` instead of `variable.secureValue`, potentially exposing secrets in interpolation.

---

## Edge Cases & Gotchas (from SpecFlow Analysis)

These were identified during specification analysis and are incorporated into the tasks above:

| Edge Case | Resolution |
|-----------|-----------|
| `curl_global_init` called after `curl_easy_init` due to lazy `EnvironmentKey` | Use `static let` in `CurlHTTPClient` for guaranteed ordering |
| Concurrent `curl_easy_perform` on same handle → undefined behavior | Serial GCD queue serializes all perform calls + fresh handle per request |
| `CURLOPT_POSTFIELDS` data freed while curl reads it | Use `CURLOPT_COPYPOSTFIELDS` instead — libcurl copies data internally *(updated)* |
| `CheckedContinuation` double-resume (perform completes + Task cancelled simultaneously) | `OSAllocatedUnfairLock<Bool>` for `didResume` flag gates resume to exactly once *(updated)* |
| `CURLOPT_XFERINFOFUNCTION` not called during DNS/TCP phase → cancellation delayed | Accepted limitation; `CURLOPT_CONNECTTIMEOUT = 10` bounds the worst case |
| Negative timing deltas (non-TLS requests, connection reuse, floating-point) | `max(0, delta)` clamping on all computed phases |
| `statusMessage` not available via `curl_easy_getinfo` | Parse from first line of header callback; fallback to `HTTPURLResponse.localizedString(forStatusCode:)` |
| `curl_slist` leak or use-after-free | Scope `defer { curl_slist_free_all(headerList) }` to encompass `curl_easy_perform` — libcurl does NOT copy header strings *(updated)* |
| `cacert.pem` not found at runtime → all HTTPS fails | Fail fast in `CurlHTTPClient.init()` with descriptive error |
| SIGALRM crash during DNS timeout in multithreaded app | Always set `CURLOPT_NOSIGNAL = 1` |
| Redirect loop hangs for full timeout | Set `CURLOPT_MAXREDIRS = 10` |
| Cookie behavior differs from URLSession | Correct for API testing tool — no auto-cookie handling. Document in release notes. |
| Adding `timingBreakdown` to `HTTPResponse` breaks existing construction sites | Provide default `= nil` in struct definition |
| Protocol abuse via `file://`, `ftp://` URLs *(new)* | `CURLOPT_PROTOCOLS_STR = "http,https"` restricts allowed protocols |
| TLS downgrade attack *(new)* | `CURLOPT_SSLVERSION = CURL_SSLVERSION_TLSv1_2` sets minimum version |
| Unbounded response size fills disk *(new)* | `CURLOPT_MAXFILESIZE_LARGE = 100MB` limit |
| `Unmanaged` pointer freed during callback *(new)* | Use `passRetained` / `takeRetainedValue` pair to ensure context survives |
| `isCancelled` flag read from GCD queue, written from Swift concurrency *(new)* | `OSAllocatedUnfairLock<Bool>` provides proper synchronization |

## Alternative Approaches Considered

| Approach | Why Rejected |
|----------|-------------|
| **Enhanced URLSession + TaskMetrics** | Covers timing/compression for v1, but hits ceiling for SSL, proxies, curl parity. Would need replacement eventually. |
| **SwiftNIO AsyncHTTPClient** | Server-focused, ~10+ transitive dependencies, less timing granularity than both URLSession metrics and libcurl. |
| **greatfire/SwiftyCurl ObjC wrapper** | CocoaPods-first, SPM has cacert.pem issues, handles not reused (created per request), many libcurl features not exposed. Better to own the wrapper. |
| **Wrap `/usr/bin/curl` via Process** | App Store sandbox prohibits spawning subprocesses. Dead on arrival. |
| **Build libcurl from source ourselves** | Maintaining a build pipeline for libcurl + OpenSSL across architectures is significant ongoing effort. curl-apple auto-updates within 24h of releases. |

## Acceptance Criteria

### Functional Requirements

- [ ] GET, POST, PUT, PATCH, DELETE requests work correctly via libcurl
- [ ] Custom headers are sent exactly as specified (no hidden additions)
- [ ] Request body (JSON, raw, form) is sent correctly
- [ ] Response body is received correctly (small in-memory, large to disk)
- [ ] Response headers are parsed correctly
- [ ] Status code and status message are extracted correctly
- [ ] Timing breakdown (DNS, TCP, TLS, TTFB, download) is accurate
- [ ] Cancellation aborts in-flight requests within ~1 second
- [ ] Compression (gzip/deflate/brotli) is handled automatically
- [ ] SSL verification works by default with bundled CA certificates
- [ ] All existing curl import functionality (`CurlParser`) continues working
- [ ] History entries are saved with timing breakdown data

### Non-Functional Requirements

- [ ] No main thread blocking — curl_easy_perform runs on dedicated GCD queue
- [ ] Memory usage matches current behavior (1MB threshold for disk streaming)
- [ ] App Sandbox compatibility — works with existing entitlements
- [ ] App Store compliance — export compliance key set in Info.plist
- [ ] Response size capped at 100MB via `CURLOPT_MAXFILESIZE_LARGE`
- [ ] Only `http://` and `https://` protocols allowed

### Quality Gates

- [ ] All existing tests continue to pass (CurlParser, VariableInterpolator, etc.)
- [ ] New CurlHTTPClient tests pass
- [ ] Build succeeds for both arm64 and x86_64
- [ ] No memory leaks (curl handles, slists, response buffers properly freed)

## Dependencies & Prerequisites

| Dependency | Version | Source | Purpose |
|-----------|---------|--------|---------|
| curl-apple xcframework | 8.18.0 | [GitHub release](https://github.com/greatfire/curl-apple/releases/tag/8.18.0) | libcurl + OpenSSL static library |
| libz | system | macOS SDK | Compression (gzip/deflate) |
| libldap | system | macOS SDK | LDAP support (linked by curl) |
| SystemConfiguration | system | macOS SDK | Network reachability (linked by curl) |

No SPM packages required — xcframework is manually embedded.

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| C interop complexity (shims, callbacks, Unmanaged) | Medium | High | Well-documented patterns exist (IBM-Swift/CCurl, khoi/curl-swift). Shim layer is thin. |
| curl-apple stops being maintained | Low | High | Can switch to jasonacox/Build-OpenSSL-cURL scripts or fork. Static library means no runtime dependency. |
| App Store rejection | Low | Medium | Static linking is explicitly allowed. OpenSSL is widely used. File export compliance documentation. |
| Binary size increase (~70MB compressed) | Certain | Low | Acceptable for a macOS desktop app. Can be reduced later by building curl without unused features. |
| No HTTP/2 | Certain | Low | Most API testing is HTTP/1.1. Can add nghttp2 later by building curl-apple from source. |
| cacert.pem not found at runtime | Medium | High | Extract from xcframework at build time, add to app bundle, fail fast in init with descriptive error. |
| Thread safety (isCancelled/didResume flags) | Medium | High | Use `OSAllocatedUnfairLock<Bool>` — proper synchronization across GCD + Swift concurrency. *(updated: raised from Low/Low)* |
| OpenSSL security vulnerability (CVE) | Medium | High | curl-apple auto-updates within 24h of upstream releases. Must rebuild and re-release PostKit promptly. Monitor curl security advisories. *(new per security review)* |
| cacert.pem becomes stale over time | Medium | Medium | Update alongside curl-apple xcframework updates. Consider fetching from https://curl.se/ca/cacert.pem at build time. *(new per security review)* |
| Export compliance legal exposure | Low | Medium | Consult legal counsel on whether bundled OpenSSL requires `ITSAppUsesNonExemptEncryption = YES` + annual BIS self-classification report. *(new per security review)* |

## Future Considerations

These are **not** in scope for this plan but are enabled by the libcurl foundation:

- SSL skip-verify toggle (`CURLOPT_SSL_VERIFYPEER = 0`) for local dev servers
- Client certificate authentication (`CURLOPT_SSLCERT`, `CURLOPT_SSLKEY`)
- Proxy support (HTTP, SOCKS4, SOCKS5) via `CURLOPT_PROXY`
- Custom DNS resolution via `CURLOPT_RESOLVE`
- HTTP/2 support (rebuild curl-apple with nghttp2)
- Request/response size optimization (brotli/zstd compression metrics in UI)
- Connection reuse indicator in timing view
- Export as curl command with exact flags matching the engine's behavior

## References & Research

### Internal References

- Brainstorm document: `docs/brainstorms/2026-02-13-http-client-engine-brainstorm.md`
- Current HTTP client: `PostKit/PostKit/Services/HTTPClient.swift` (URLSessionHTTPClient actor)
- Protocol definition: `PostKit/PostKit/Services/Protocols/HTTPClientProtocol.swift`
- Environment injection: `PostKit/PostKit/Utilities/Environment+HTTPClient.swift`
- Response viewer: `PostKit/PostKit/Views/RequestDetail/ResponseViewer/ResponseViewerPane.swift` (line ~217: ResponseTimingView placeholder)
- App entitlements: `PostKit/PostKit/PostKit.entitlements`
- Architecture plan: `plans/postkit-mvp-architecture.md`

### External References

- [greatfire/curl-apple](https://github.com/greatfire/curl-apple) — Pre-compiled libcurl xcframework
- [greatfire/SwiftyCurl](https://github.com/greatfire/SwiftyCurl) — Reference ObjC/Swift wrapper (not used, but studied)
- [khoi/curl-swift](https://github.com/khoi/curl-swift) — Reference Swift wrapper with isolate/share patterns
- [IBM-Swift/CCurl shim.h](https://github.com/IBM-Swift/CCurl/blob/master/shim.h) — C shim pattern reference
- [curl: SecureTransport going away](https://daniel.haxx.se/blog/2025/01/14/secure-transport-support-in-curl-is-on-its-way-out/)
- [CURLOPT_WRITEFUNCTION docs](https://curl.se/libcurl/c/CURLOPT_WRITEFUNCTION.html)
- [CURLOPT_XFERINFOFUNCTION docs](https://curl.se/libcurl/c/CURLOPT_XFERINFOFUNCTION.html)
- [Ole Begemann: C Callbacks in Swift](https://oleb.net/blog/2015/06/c-callbacks-in-swift/)
- [Apple: Export compliance](https://developer.apple.com/help/app-store-connect/reference/export-compliance-documentation-for-encryption/)
- [Apple Developer Forums: Static C Library in Swift](https://developer.apple.com/forums/thread/758816)
