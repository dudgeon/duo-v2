# Duo: the "Trust this folder" notice — design handoff

Status: Geoff picked by buttons on 2026-10-20 (DL-229): the action **A (Duo writes the one key, after a sheet)**, where **A (a bar under the terminal)**, after **A (Fork Again)**, duo2 **A (always asks)**. The canvas is https://claude.ai/artifact/JvLDXJw54Vm8yWTf8r8ZGn ("Duo · Trust this folder"). Not built: `tasks/build-trust-notice.md` is the suggested build.

This draws Q-219 (c), which DL-227 left for its own round: what Duo does when Claude Code's `/fork` says "Workspace not trusted". Why it happens is in `docs/research/fork-handling.md` §2 and F-344. It fits the fork tabs and threads (DL-228, `fork-thread-handoff/`) and changes nothing there.

The screens are copies of the canvas boards: static HTML, with `png/` at 2x. They are presentation boards, so build only what the table names. The canvas sources are in `canvas/`; the boards draw their parts through `Console.dc.html`, `Chat.dc.html`, `Sheet.dc.html` and `Strip.dc.html` (the last copied from `fork-thread-handoff/`). Names and paths are illustrative.

## Targets

| Screen | Build | Not chosen (canvas only) |
|---|---|---|
| `00-why-and-questions` | Context only: why, exactly what Duo writes, the rules, the four questions and the answers. | — |
| `01-where` | **The bar under the terminal (Q2 A)**; chat's bar over the composer. | B (a bar over the terminal, under the strip) |
| `02-action` | **The sheet, then Duo writes the one key (Q1 A).** | B (Claude Code's own trust question in a tab) |
| `03-after` | **"Now trusts" with Fork Again (Q3 A)**; when Duo can't write; duo2 (Q4 A). | B (words only) |

## The facts this rests on

Checked 2026-10-20 on Claude Code **2.1.219, 2.1.303 and 2.1.304**, with a scratch `CLAUDE_CONFIG_DIR` and `HOME`, a dummy key and a dead API port (no turn ran), in F-344's setup: the parent folder trusted, the project made a git repository after the session started.

- **The line.** 2.1.303 and 2.1.304 print one result line: `⎿  Workspace not trusted. Run claude in ‹real path› once and accept the trust prompt, then retry.` (the source has backticks around `claude`). Two other variants say the path "could not be resolved on disk" and that "The home directory is trusted one session at a time"; **neither gets the notice**.
- **Where trust lives**, the same on all three versions: `‹config›/.claude.json` (`$CLAUDE_CONFIG_DIR/.claude.json`, else `~/.claude.json`), key `projects["‹abs path›"].hasTrustDialogAccepted == true`. The path is the real path (`/private/tmp`, not `/tmp`; symlinks resolved), with no trailing slash. In a git repository the key goes at the **repository's top folder**, which covers its subfolders.
- **The entry.** Claude makes the project's entry with `false` at each start, and accepting its own prompt flips it to `true`. An entry holding only `{"hasTrustDialogAccepted": true}` is enough when there is none.
- **Claude's writes.** Claude takes a directory lock, `.claude.json.lock`, re-reads the file, merges `projects` by key, writes `.claude.json.tmp.‹pid›.‹hex›` and renames it over the file. If the lock stays held, it skips its write rather than clobber. A key added from outside while a session ran survived that session's later saves.
- **No restart.** Once the key is set, the next `/fork` in the same running session works (Claude re-reads the file on each check), and so does accepting Claude's own prompt in a separate `claude`.
- **2.1.219** keys trust the same way. It shows no prompt for a repository under a trusted parent, and its `/fork` works in this setup, so the notice never appears there. The action still works there: same file, same key.

## Where it appears (`01`)

- **Only on Claude Code's line.** Duo reads the session's screen (as chat reads dialogs: `ChatScreenReader`) for the "Workspace not trusted. Run claude in ‹path›" line printed after a `/fork`.
- **Only for this case.** The bar offers Trust This Folder… only when all three hold:
  - the path in the line is the session's folder, or its repository's top folder;
  - that path has no `true` entry;
  - a folder above it has one, so Claude Code already trusts it from above.
  
  Otherwise the bar says "Claude Code doesn't trust ‹folder›. Run claude there once and answer its trust question." with OK only. *That wording is a stand-in (Q-232).*
- **Terminal session (Q2 A):** a console bar under the terminal, drawn as `ConsoleEndedBar` is:
  - `consoleBarHeight` 40, a 1 `consoleRule` above, padding 16, on `console`;
  - the message in `body` `consoleText`;
  - console buttons: Not Now, then **Trust This Folder…** (the default, `consoleText` edge, semibold).
  
  The terminal gives up 40 and reflows. The terminal keeps working and keeps focus; the bar takes no focus.
- **Chat:** Claude's line shows as any command's result (DL-143: the elbow, right-aligned under your bubble). The bar sits over the composer: `ground`, a 1 `rule` above, padding 10 20 (`size.notice`), sheet buttons.
- **The words:** "Claude Code doesn't trust ‹folder› yet, so /fork couldn't start." The folder is named by its last component; the full path goes in the sheet.
- **Narrow:** under about 560 the message cuts at the end; the buttons stay whole.
- **Not Now** hides the bar for this session; the next such line brings it back. Nothing is stored.
- **The bar goes by itself** when the folder becomes trusted some other way, or the session ends, or its tab closes.

## The action and its confirmation (`02`, Q1 A)

- **Trust This Folder… always asks first**, in a Duo question through `SheetCenter` (`DuoQuestion`), never a system alert. Trust Folder is the default (Return); Escape cancels. No setting or automation skips it.
- **The sheet:**
  - **Title:** "Trust "checkout" for Claude Code?"
  - **Text:** "Claude Code trusts your Home folder, but stops at a git repository when /fork starts a background session. checkout became a repository after this session started, so it needs its own trust." Then: "Duo will change one setting in Claude Code's file, the one Claude sets when you answer "Yes, I trust this folder":"
  - **A `pane` box in `mono`:**
    - Folder: the real path;
    - In ‹config›/.claude.json: `projects › …/‹folder› › hasTrustDialogAccepted: true`.
  - **A `text2` note:** "Only this folder. Claude Code will then use its settings, hooks and tools without asking, as it already does here in this session. Nothing else in the file changes."
  - **Buttons:** Cancel, **Trust Folder**.
  - **When the session runs in a subfolder**, the box's folder line names the repository's top folder ("checkout (the repository's top folder, which holds api/)"). *That line is a stand-in (Q-232).*
- **The write:**
  1. Take Claude's lock: make the directory `.claude.json.lock` beside the file. Retry briefly. Never remove a lock Duo didn't make.
  2. Read the whole file; parse it as JSON.
  3. Set only `projects[path].hasTrustDialogAccepted = true`, making the entry with that key alone if it is missing. Keep every other byte's meaning: key order and unknown keys.
  4. Write a temp file in the same folder, rename it over the file, and release the lock.
  
  The write never runs on a file Duo couldn't read whole and parse. It never touches another project's entry.
- **Logged:** one line in Duo's log, "trusted ‹path› for Claude Code (asked by you | duo2)".

## After (`03`, Q3 A)

- **The bar changes in place** (no slide): "Claude Code now trusts checkout." with **Fork Again** (default) and OK.
- **Fork Again:**
  - It types the same `/fork` line, read from the screen, with any prompt after it. Text and Return go as separate keystrokes (F-45).
  - It does this only while Claude is at its prompt with nothing typed. Otherwise the button is disabled, with the help "Finish what you're typing first".
  - Then the bar goes, and the fork's tab opens as DL-228 draws it.
  - In chat it sends the line through the composer.
- **When Duo can't write**, the bar says "Couldn't change Claude Code's settings: ‹why›." with **Try Again** and Not Now. The reasons:
  - "another Claude is saving them; try again in a moment" (the lock is still held);
  - "the file isn't readable as settings, so Duo left it alone";
  - "Duo can't write to ‹path›".
- **No Undo.** Untrusting is Claude Code's own, as for any folder trusted in Claude.
- *Chat's after-state and failure bar are worded here, not drawn (Q-232).*

## Keyboard, VoiceOver, duo2

- No new shortcut. The bar's buttons are in the key loop after the terminal; Return in the bar presses its default.
- VoiceOver announces the bar once when it appears ("/fork couldn't start: Claude Code doesn't trust checkout yet") and again when it changes.
- duo2 (DL-71; Q4 A):
  - `duo2 session trust-folder <id>` shows the same sheet in Duo and waits for the answer. It prints `trusted ‹path›` or `cancelled`. There is **no `--yes`**: Claude can ask, but can't trust a folder for itself.
  - `duo2 session show` lists a pending bar as `fork blocked: folder not trusted`.
  - Fork Again and Not Now are view actions on the bar. List them in `Parity.uiOnly` with why, or give them verbs (`session fork-again`, `session dismiss-notice`); the builder chooses and says so.

## For the build

- **Fixture states for `scripts/check-ui.sh`:** the bar under a terminal (screen text fed in, F-25: terminals draw blank in captures); the sheet; the after state; the failure; the chat bar. Compare at 720 and 480 wide.
- **DuoChecks:**
  - the line's reader on recorded 2.1.303/2.1.304 screens and the two other variants (no notice for those);
  - the "only for this case" rule;
  - the write against a scratch `.claude.json`: only the one key changes, unknown keys and order survive, `false` is flipped, a missing entry is added, an existing lock is waited on and never removed, invalid JSON is left alone, the real path and repository top are used;
  - duo2 has no `--yes`.
- **A scratch-config live check** (no turn), as in the facts above: after Trust Folder, `/fork` in the same session succeeds on 2.1.303.
- **Update** `docs/design/system/surfaces.md` and the ConsoleMessage component's README when it ships. The design-system artifact is the director's to publish.

## Open

Q-232's stand-ins: the never-trusted wording, the subfolder line, and chat's after-state and failure bar.
