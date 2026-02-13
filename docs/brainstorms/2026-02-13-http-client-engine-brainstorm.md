# Brainstorm: HTTP Client Engine — URLSession vs libcurl

**Date:** 2026-02-13
**Status:** Decision made
**Participants:** adryanev, Claude

---

## What We're Building

Replace PostKit's HTTP client engine from `URLSession` to **libcurl** (via static linking) to gain full curl feature parity, detailed timing breakdowns, advanced compression, and low-level protocol control — while maintaining Mac App Store compatibility.

The existing `HTTPClientProtocol` abstraction means only the engine implementation changes; the rest of the app (views, models, history) remains untouched.

## Why This Approach

### Problem Statement

PostKit is an API client app (think Postman/Insomnia for macOS). URLSession, while convenient, has fundamental limitations for an HTTP power-tool:

1. **No curl parity** — Users paste curl commands expecting identical behavior (redirects, headers, timing). URLSession's opinionated defaults (automatic cookie handling, ATS enforcement, hidden headers) make exact curl reproduction difficult.
2. **Limited timing data** — While `URLSessionTaskMetrics` provides some timing, libcurl's `CURLINFO_*` gives richer data: name lookup time, connect time, app connect time (TLS), pre-transfer time, start transfer time (TTFB), redirect time, total time.
3. **SSL/TLS inflexibility** — Skip-verify (`curl -k`), client certificates, and custom CA bundles all require awkward `URLSessionDelegate` workarounds and ATS exceptions.
4. **Missing advanced features** — SOCKS proxies, UNIX sockets, HTTP/2 server push, custom DNS resolution, connection reuse control.
5. **Compression gaps** — URLSession only supports gzip/deflate. libcurl supports brotli and zstd.

### Why libcurl over alternatives

| Option | Verdict |
|--------|---------|
| **Enhanced URLSession** | Covers timing + compression for v1, but hits a ceiling quickly for the other 4 pain points. Would need replacement eventually anyway. |
| **libcurl static linking** | **Chosen.** Full feature parity, battle-tested (curl is 28+ years old), App Store safe when statically linked. |
| **SwiftNIO AsyncHTTPClient** | Server-side focused, heavy dependency tree (~10+ packages), less timing granularity than both URLSession metrics and libcurl. |
| **Wrap `/usr/bin/curl` via Process** | Dead on arrival — App Store sandbox prohibits spawning subprocesses. |

### Why now

The app is at MVP stage (Phase 5 complete). Switching the engine now means less code to migrate, and the protocol-based architecture (`HTTPClientProtocol`) was designed exactly for this kind of swap.

## Key Decisions

### 1. Integration: greatfire/curl-apple xcframework

**Decision:** Use [greatfire/curl-apple](https://github.com/greatfire/curl-apple) as the pre-compiled libcurl xcframework provider.

**Rationale:**
- Auto-updates within 24 hours of new curl releases (critical for security patches)
- Builds as xcframework with static linking — App Store compatible
- Includes OpenSSL for TLS 1.3 (Apple's SecureTransport is being deprecated)
- Supports iOS and macOS (both arm64 and x86_64)
- No need to maintain our own build pipeline

**Not using** greatfire/SwiftyCurl (the ObjC wrapper) because:
- CocoaPods-first; SPM has a cacert.pem discovery issue
- We want full control over the Swift API surface
- Our existing `HTTPClientProtocol` already defines the contract

### 2. Architecture: New CurlHTTPClient behind existing protocol

**Decision:** Create a new `CurlHTTPClient` actor conforming to `HTTPClientProtocol`.

- Drop-in replacement for `URLSessionHTTPClient`
- Same `execute(_ request:, taskID:) async throws -> HTTPResponse` interface
- The app layer (views, models) doesn't change at all
- Could keep `URLSessionHTTPClient` as a fallback (user-selectable in settings, or automatic if curl init fails)

### 3. Timing data: Expose CURLINFO_* metrics

**Decision:** Extend `HTTPResponse` to include a `TimingBreakdown` struct.

Key metrics from libcurl:
- `CURLINFO_NAMELOOKUP_TIME` — DNS resolution
- `CURLINFO_CONNECT_TIME` — TCP connection
- `CURLINFO_APPCONNECT_TIME` — TLS handshake
- `CURLINFO_STARTTRANSFER_TIME` — Time to first byte (TTFB)
- `CURLINFO_TOTAL_TIME` — Total request duration
- `CURLINFO_REDIRECT_TIME` — Time spent on redirects
- `CURLINFO_SIZE_DOWNLOAD` — Response size

### 4. Distribution: Both App Store and direct

**Decision:** Support both distribution channels.

- Static linking of libcurl is App Store compliant
- Sandbox entitlements remain the same (`network.client`, `files.user-selected.read-write`)
- No subprocess spawning needed

### 5. Compression

**Decision:** Enable all compression methods libcurl supports.

Set `CURLOPT_ACCEPT_ENCODING` to `""` (empty string = all supported encodings). This enables gzip, deflate, brotli, and zstd automatically, depending on what the curl-apple build includes.

## Technical Considerations

### C Interop Challenge: `curl_easy_setopt` is variadic

Swift cannot import C variadic functions directly. The standard workaround is a small C shim file that wraps each `curl_easy_setopt` call with a typed function:

```c
// CurlShims.h
CURLcode curl_easy_setopt_string(CURL *curl, CURLoption option, const char *value);
CURLcode curl_easy_setopt_long(CURL *curl, CURLoption option, long value);
CURLcode curl_easy_setopt_pointer(CURL *curl, CURLoption option, void *value);
```

This is a well-known pattern used by every Swift-libcurl project.

### Async/Await bridging

libcurl's easy API is synchronous (blocking). Options:
1. **Wrap in `Task.detached`** — Run `curl_easy_perform` on a background thread
2. **Use curl multi API** — Non-blocking with `curl_multi_perform` + run loop integration
3. **Actor isolation** — The `CurlHTTPClient` actor naturally serializes access

For v1, option 1 (detached task) is simplest and matches the current architecture.

### Memory: Response handling

Current `URLSessionHTTPClient` streams to disk for large responses (>1MB). The libcurl equivalent:
- Use `CURLOPT_WRITEFUNCTION` callback to stream response data to a temp file
- Same threshold logic (>1MB → keep on disk, else load into `Data`)

### Cancellation

libcurl supports cancellation via `CURLOPT_PROGRESSFUNCTION` — return non-zero to abort. Map this to Swift's `Task.isCancelled` for cooperative cancellation.

## Open Questions

*(None — all key decisions resolved during brainstorm)*

## Resolved Questions

1. **URLSession vs libcurl?** → libcurl, for full curl feature parity across all dimensions (timing, SSL, compression, proxies)
2. **Distribution channel?** → Both App Store and direct distribution; static linking is compatible with both
3. **Integration method?** → greatfire/curl-apple xcframework (pre-compiled, auto-updated)
4. **v1 priority features?** → Detailed timing breakdown and compression support
5. **Keep URLSession as fallback?** → Yes, behind the existing protocol; could be user-selectable

## References

- [greatfire/curl-apple](https://github.com/greatfire/curl-apple) — Pre-compiled libcurl xcframework for iOS/macOS
- [greatfire/SwiftyCurl](https://github.com/greatfire/SwiftyCurl) — ObjC/Swift wrapper (evaluated, not chosen)
- [khoi/curl-swift](https://github.com/khoi/curl-swift) — Lightweight libcurl Swift wrapper (reference implementation)
- [jasonacox/Build-OpenSSL-cURL](https://github.com/jasonacox/Build-OpenSSL-cURL) — Build scripts for OpenSSL + curl (alternative to curl-apple)
- [curl-apple auto-build](https://github.com/greatfire/curl-apple) — Auto-updates within 24h of new curl releases
- [Apple Developer Forums: Static C Library in Swift](https://developer.apple.com/forums/thread/758816)
