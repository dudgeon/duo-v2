# Spike: do in-app updates (Sparkle) work on the work Mac?

Status: ready to run once 0.1.6 (the first release with Sparkle) is out · 2026-10-05 · Owner: Geoff

Release builds of Duo now update themselves with Sparkle (Phase L, `Vendor/Sparkle/README.md`). A managed Mac can stop that in three places: the network (the feed and the DMG come from GitHub's release servers), installing (the updater replaces `/Applications/Duo.app`), or policy (management can block apps that update themselves). This test finds out which, if any.

## Run it (about 5 minutes, then once more when the next version ships)

1. On the work Mac, install Duo 0.1.6 from its GitHub release: open the DMG, drag Duo to Applications, open it.
2. In Terminal:
   ```bash
   /Applications/Duo.app/Contents/Helpers/duo2 update probe
   ```
   It checks, without changing anything: the feed (`releases/latest/download/appcast.xml`), the DMG it names (served from GitHub's download host), whether Duo is installed where you can replace it, and any system proxy. Paste its output to Claude (or note the line marked ✗).
3. When 0.1.7 is released: in Duo, Duo › Check for Updates…. Expected: Sparkle's window offers 0.1.7 with its notes; Install downloads it, asks to relaunch, and Duo comes back as 0.1.7 with what was open restored. Note anything macOS or the work Mac's management shows along the way.

## Reading the result

| What you see | Meaning | Then |
|---|---|---|
| Probe all ✓, step 3 updates | In-app updates work there | Done; close G1's update question |
| Feed or download ✗ (blocked, timeout, a proxy page) | The network blocks GitHub's release hosts | Host the feed and DMG somewhere the work Mac allows (ask IT which), or keep updating by hand from the DMG |
| "needs an administrator password" | Applications isn't yours to change | Sparkle asks for the password; if you can't give one, install updates by hand |
| Step 3 fails after downloading (a security or "can't be opened" message) | Management blocks the updater | Log it; updates by hand from the DMG |

Whatever happens, Duo › Check for Updates… still works where Sparkle can't run: the GitHub notice (F-69) tells you a newer version exists and opens its release page.
