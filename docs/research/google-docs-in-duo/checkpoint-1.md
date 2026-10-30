# Checkpoint 1: questions for Geoff

Google Docs in Duo, end of Phase 1, 2026-10-29. The director brings these to Geoff (console cards or AskUserQuestion). Each question lists its options with the recommendation first. They're Q-309 to Q-316 in `docs/plan/concerns-and-questions.md`. Background: [jobs.md](jobs.md), [duo-browser-today.md](duo-browser-today.md), [google-docs-surface.md](google-docs-surface.md), [comparison-frame.md](comparison-frame.md), [test-plan.md](test-plan.md), and the landscape survey [agent-landscape.md](agent-landscape.md).

## What Phase 1 found that changes the plan

1. **The Docs API can now write real suggestions and anchored comments** (GA 2026-09-30, F-409). Claude's tracked changes no longer need the browser. That also removes the native editor's (B's) only real advantage.
2. **In Duo's WebKit, Docs hands any page script its whole text, its links, your selection, and a way to set the selection** (F-412). This goes through `_docs_annotate_getAnnotatedText`, with no extension id borrowed and no flag set. Measured signed out. That's Claude knowing your selection, live, with no add-on. But it's an undocumented Google internal.
3. **Real mouse drags and keys reach Docs' editor from duo2-style events, with Duo in the background** (F-413). Today's `duo2 browser read`, `fill` and `scroll` get nothing from a Doc (F-411).
4. **No test copy of Duo can stay signed in to Google today.** Isolated copies use a throwaway cookie store (C-32's fix). The real Duo's store is shared by every Duo on the Mac.
5. **Signing in to Google inside an embedded web view is against Google's stated policy** ("may" be blocked; OAuth is refused outright). Whether Geoff can sign in in Duo's tab at all is the first test (T-00).

So the direction I'd test toward is **(C):**
- Docs itself in Duo's tab, for you and your collaborators.
- Claude reads the live tab for your selection and context.
- Claude writes suggestions and comments through the API.

## The questions

### 1. Which jobs matter most? (Q-310)
The catalogue has about 80 jobs in 20 groups. I marked four as your own asks:
- near-perfect rendering
- Claude knows my selection
- Claude edits as tracked changes
- live collaboration

**Options:**
1. **(Recommended)** **Keep my H/M marks as they are.** Phase 2 tests every H and M job, H first. Offline, page setup, building blocks, doc chat and follow-the-presenter stay out.
2. **Narrow to the core loop:**
   - reading
   - selection to Claude
   - Claude's suggestions and comments
   - @claude in comments
   - live collaboration
   - "what changed"

   Everything else waits.
3. **Widen:** add offline (Chrome-only in Google's terms) and templates or building blocks.

### 2. Where do the tests run? (Q-312)
**Options:**
1. **(Recommended)** **A dedicated test Duo you sign into once.**
   - It's a work-tree build with its own support folder and its own persistent cookie store. That store is a small scratch change (W-5), not merged.
   - Your own Duo, its cookies and its allow list stay untouched.
   - You sign in once (T-00), in a window it shows for that.
2. **Your own Duo, signed in.**
   - No build change, and the test sees exactly what you'll use.
   - But scripted runs drive your running Duo, add Google hosts to your allow list (allowed by your request), and use the one cookie store every Duo on this Mac shares.
3. **Both:** the test instance for scripted runs, and your own Duo for the hands-on sweep (T-12).

### 3. Who is the second collaborator for the live tests? (Q-313)
T-08, T-09 and half of T-05 need someone typing and commenting in another browser, about 30 minutes in one sitting.

**Options:**
1. **(Recommended)** **A second Google account of yours, in Chrome on another device** (your phone or laptop), driven by you or by Claude in Chrome. That's the cheapest and needs no one else.
2. **A real colleague** (best for presence and @mentions), at a time you pick.
3. **A second Google account on this Mac, in Chrome, driven by Claude in Chrome.** Fully scripted, but it's one machine, so latency is optimistic.

### 4. The API authorization (Q-314)
The suggestion, comment, index-mapping and change tests (T-04, T-05, T-09, T-11, T-13, T-14) need Google's API with your consent.

**Options:**
1. **(Recommended)** **Your own Google Cloud project, OAuth client in testing mode, you as its only test user.**
   - Scopes: `documents` and `drive.file`, plus the Apps Script scope for T-11.
   - One consent screen, opened in your normal browser.
   - The token stays in this Mac's Keychain.
   - Fleet OAuth (Duo's own verified client) waits for Phase 3.
2. **Google's Docs MCP server only** (developer preview), connected to one scratch Claude session. It needs less code, but the same consent, and it can't do Drive export or revisions.
3. **No API in Phase 2.** Test A's in-page route only, and decide C later. That's cheaper, but it leaves Checkpoint 2 without the API side of the comparison.

### 5. May Duo use Docs' undocumented in-page hook? (Q-309)
It gives Claude your selection and the live text, and it's the best route found. But it's a Google internal that could change without notice. It isn't the "borrowed extension id" the landscape survey worried about: Docs answered with no id.

**Options:**
1. **(Recommended)** **Test it fully in Phase 2. Use it for reading only** (text, selection, setting the selection to show you a passage). Writes go through the API, and Docs' screen-reader mode or an Apps Script sidebar stand by as fallbacks. A nightly probe catches breakage.
2. **Test it, but don't plan on it.** Build selection-to-Claude on a sanctioned route (an Apps Script add-on, or copy-to-Claude).
3. **Don't touch it.** Selection comes only from Apps Script or a copy.

### 6. Whose name is on Claude's suggestions? (Q-315)
API suggestions and comments are credited to the Google account that authorised them, which would be you. In-page suggestions are yours too.

**Options:**
1. **(Recommended)** **Yours for now, with a "Claude:" prefix on Claude's comments.** Duo remembers which suggestion ids Claude made, so it can list and reject "only Claude's". T-05 records what Google actually shows.
2. **A separate Google account for Claude** (for example claude.geoff@…), shared on the Doc as an editor, so others see "Claude" on each suggestion. It's clearer to colleagues, but it's a second account to run, and a shared doc then lists it.
3. **Decide after T-05 shows what Google displays.**

### 7. Duo's shortcuts over a Google Doc (Q-316)
Some Duo chords are also Docs chords:
- ⇧⌘H is Duo's Home and Docs' find and replace.
- ⌥⌘0 is Duo's collapse pane and Docs' Normal text.
- ⌘P is Duo's print, which makes a picture-only PDF of a Doc.

**Options:**
1. **(Recommended)** **Measure first (T-10). Then a decision that, while a Google Docs tab has the keyboard, the page gets these chords** (Duo's stay on the menu bar). That's an amendment to DL-34.
2. **Leave Duo's chords as they are;** people use Docs' menus for these.

### 8. Your work Google account (Q-311)
Phase 2 starts on your personal account. A managed Workspace account can require Chrome with endpoint verification, and block other browsers or unapproved OAuth apps. That would block (A) or (C) at work whatever Phase 2 shows.

**Options:**
1. **(Recommended)** **Personal account for Phase 2.** You try one sign-in to the work account in Duo's tab (T-00, step 3) when convenient on the work Mac, and tell me what it says. No scripts run there.
2. **Personal account only;** work is a Phase 3 question.
3. **Work account from the start** (if that's the one you'd really use), on the Mac mini.
