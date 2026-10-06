# Spike: Google Docs says Duo's browser is unsupported (F-117, C-32, Q-65)

2026-10-06. Geoff's report: a Google Doc opened in a Duo browser tab shows "This browser version is no longer supported. Please upgrade to a supported browser." He asked for the alternatives and their impact.

**Answer: the engine is fine. Duo's tabs run the system WebKit, the same engine as Safari 27, but they didn't say so.** A bare WKWebView sends a user agent with no `Version/x Safari/605.1.15` part, and Google's check looks for that part. Adding the installed Safari's token removes the banner. This is built in `c967072`. No engine change is needed.

## 1. The user agent, with evidence

This Mac runs macOS 27.0 (26A428) with Safari 27.0 (`/Applications/Safari.app` `CFBundleShortVersionString`).

| | User agent |
|---|---|
| Duo's tabs before (WKWebView default, measured) | `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)` |
| Duo's tabs after, the same as Safari 27's format | `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Safari/605.1.15` |

Nothing in `Sources` set `customUserAgent` or `applicationNameForUserAgent`. All three web views (BrowserTabs, HTMLViewer, DocumentEditor) sent the bare string. I didn't launch Safari to read its string, because that would touch Geoff's browser. The "after" row follows Safari's documented format, with the version read from the installed Safari.

**Probe.** A standalone WKWebView with a non-persistent store and no account, in a scratch folder. It loads each URL, waits 10 seconds, then reads `navigator.userAgent`, the final URL and the page text, and takes a snapshot. There are two runs per URL: the default user agent, and `applicationNameForUserAgent = "Version/27.0 Safari/605.1.15"`.

| Page (signed out) | Default UA | Safari token |
|---|---|---|
| Public Google Doc (Chromium WebSocket design doc) | Loads, with the **banner** | Loads, **no banner** |
| Public Google Sheet (alicekeeler template) | Loads, with the **banner** | Loads, **no banner** |
| Public Google Slides (chromium.org deck) | Redirects to sign-in (the deck isn't public) | Same |
| Gmail, `docs.google.com/document/u/0/` | Redirects to sign-in, no banner | Same |
| Drive | Redirects to sign-in | Redirects to the Drive marketing page |
| `accounts.google.com` | **"WebLiteSignIn"** flow: the basic page, with a long language list and "Not your computer?" | **"GlifWebSignIn"**: Safari's normal sign-in |

Typing an address that doesn't exist into sign-in, with real key events and Return, gave "Couldn't find this account" under both user agents. Google didn't refuse the embedded web view ("This browser or app may not be secure") at the identifier step.

**In Duo itself.** I built this branch and ran an isolated instance (its own `DUO_SUPPORT_DIR`, a scratch `CLAUDE_CONFIG_DIR`, `--state project`), then ran `duo2 browser allow docs.google.com`, `browser open <doc>` and `browser read`. The Doc and the Sheet both read without "no longer supported". The capture is `duo-doc-after.png` in the session scratchpad. The editor and the HTML viewer get the same token, which does nothing harmful to local pages.

**Found on the way (C-32).** In that run, the Doc showed **Geoff's own Google avatar**. Browser tabs use `WKWebsiteDataStore.default()`, which is keyed by the app's bundle id (`~/Library/WebKit/com.dudgeon.duo`), not by `DUO_SUPPORT_DIR`. So every isolated or scripted Duo shares Geoff's real browser cookies and signed-in sites, and can write to them. Nothing was edited: it was a read of a public doc, which may now appear in his Docs "recent" list. It does show that the fix works signed in: Geoff's real session, no banner. Fixed in the second commit: an isolated instance's tabs use a non-persistent store. Rerun result: the doc shows "Sign in", with no banner.

## 2. The other Google-in-a-web-view traps

| Trap | Status in Duo today | Evidence |
|---|---|---|
| Sign-in refusing embedded views (`disallowed_useragent`, "browser may not be secure") | The identifier step passes. The password, 2-step and passkey steps were **not tested**, because there's no scratch account. Google's `disallowed_useragent` targets OAuth for *third-party* apps ("Sign in with Google" on another site), which may still refuse inside a tab. Passkeys in a third-party WKWebView need Apple's web-browser entitlement, which Duo doesn't have, so passkey sign-in is likely to fail and password sign-in is expected to work. | Probe, sign-in runs |
| Cookies and ITP | Tabs use the persistent default store, so they stay signed in. WKWebView applies the same Intelligent Tracking Prevention as Safari, and Google works under it in Safari. No difference was found. | Geoff's store loaded Docs signed in |
| Popups and new windows | `createWebViewWith` loads the URL **in the same tab** and returns nil, so `window.opener` is gone. Docs uses new windows for print (a PDF), some "Open" links, and OAuth-style popups for add-ons. Those replace the doc, or break the popup handshake. | `BrowserTabs.swift:154` |
| File upload (Insert › Image › Upload, Drive upload) | **Doesn't work.** No `runOpenPanelWith` UI delegate method, and macOS WKWebView shows no file chooser without one. | Code |
| Downloads (File › Download) | **Not handled.** No `decidePolicyFor navigationResponse` or `WKDownload`, so an attachment either shows inline or fails, and is never saved. | Code |
| Print | `window.print()` does nothing in a WKWebView without the private print delegate. Docs' own print opens a PDF window (see popups). | Code |
| Clipboard | ⌘C, ⌘X and ⌘V are native events and work as in Safari. Edit-menu paste through the async Clipboard API gets WebKit's "Paste" callout, as Safari does. **Not tested in an editable doc.** | — |
| Editing, comments and keyboard shortcuts | **Not tested.** It needs an account and a doc we may edit. I didn't type into anyone's public doc. With the same engine and user agent as Safari, it should behave as Safari does. | — |

Upload, download, print and popups are Duo's own missing UI delegate methods. Every engine would need them, so they don't count against WebKit. Q-65 asks whether to build them.

## 3. The alternatives

| Option | Fixes the banner? | Duo's browser verbs (`browser read/click/fill/wait/screenshot`), pick and send element (F-71, F-72, PageHost) | Editor (CodeMirror) and the PowerPoint viewer (DL-121) | Size, signing, Sparkle, memory | Work Mac (no admin, proxy, C-1) and Xcode-free (ADR-0001) | Effort |
|---|---|---|---|---|---|---|
| **WKWebView with Safari's token** (built) | **Yes** (measured) | Unchanged | Unchanged | +0 | System proxy and keychain trust, as now. No change | **Done: 1 file plus 1 initializer** |
| CEF (Chromium Embedded Framework, through a Swift wrapper) | Yes (it's Chrome) | All rewritten: no WKUserScript or content worlds, no `evaluateJavaScript`, no `takeSnapshot` or context-menu hook. Each needs CEF's V8 and process messages. | The editor would stay on WKWebView, so it's two engines. The PowerPoint viewer is unaffected. | About +200–250 MB; 4–5 helper apps, each signed with JIT and library-validation entitlements; notarization is fiddly; every Sparkle update carries Chromium (about 100 MB compressed), and security fixes need a CEF update each month; about +150–300 MB of memory for its processes | No admin needed. Uses the system proxy and keychain roots. CEF's C++ wrapper needs CMake, and the Swift wrappers are thin or unmaintained. It's buildable with the Command Line Tools, but against the grain of ADR-0001. | **Weeks**, plus ongoing upkeep |
| Electron | Yes | Means a different app | — | — | — | Out of scope. Named for completeness. |
| Hand Google URLs to the default browser | Yes, in their browser | Lost for those pages: no read, pick or send. The pages leave Duo. | Unchanged | +0 | Fine | Hours (`AllowedSites` could already send them out). Already the fallback: "Open in Browser" in the tab bar. |
| Safari Web Extension | No: it runs inside Safari, not in Duo's views | Could only add Send-to-Duo from Safari, as part of a hand-off | — | A Safari extension needs an `.appex` signed into the app | Probably wants Xcode for the extension target | Days; doesn't solve it |
| SFSafariViewController | **Not on macOS.** SafariServices on macOS has the extension and share APIs only. The view controller is iOS-only. | — | — | — | — | — |

## 4. Recommendation

1. **Merge `c967072`** (the user agent fix). It's the whole fix for the banner, with zero cost to every other feature.
2. **Merge the C-32 commit** (isolated instances get a non-persistent browser store). It's a safety fix for test runs, whoever merges it.
3. **Stay on WebKit. Don't adopt CEF.** It fixes nothing the token doesn't, and it costs weeks of work, about 200 MB, monthly security upkeep, and a rewrite of every browser verb and PageHost.
4. **Q-65:** whether Duo's tabs should grow the browser basics Google's apps use (file upload, downloads, print, popups that keep their opener), or hand those actions to the default browser. Each is a small UI delegate method. Upload and downloads matter most for Docs and Drive.
5. Before calling Google fully supported, test with a **scratch Google account**: password, 2-step and passkey sign-in, then edit, comment, paste and shortcuts in a doc it owns. I had no such account (Q-65 asks).
