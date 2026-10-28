---
title: Tracked changes, comments and @claude in Markdown
status: research
task: tasks/markdown-review-intent.md
date: 2026-10-27
records: [F-370, F-371, C-112, Q-240, Q-241, Q-242, Q-243, Q-244, Q-245, Q-246, Q-247]
---

# Tracked changes, comments and @claude in Markdown

Research for Geoff's ask of 2026-10-27 (full words in `tasks/markdown-review-intent.md`): tracked changes in Markdown on a common convention, comments with authors that can be accepted or dismissed, no sidecar file, both Duo and Claude recognising them, and `@claude` in a comment reaching a Claude session as a turn that Claude answers in the thread.

The intent and decision page built from this is https://claude.ai/artifact/Jd28RDwpRJEzUigtjUxb9q (source: `markdown-review-samples/intent-page.html`). Nothing here is decided: the decisions are Geoff's to lock after user feedback, and the director records them as DL-n.

**In short.**
- CriticMarkup is the only plain-text convention for tracked changes that more than one tool reads. Its spec is frozen (last commit 2021) and has no author, date, id, reply or resolved state, so every tool that needs those adds its own signature. There is no standard signature to adopt; we pick one.
- A readable signature in the comment (`{>>@geoff 2026-10-27 #c2: …<<}`) is the one that tested best with Claude, stays legible on GitHub and in plain Obsidian, and lives in the file, so there's no sidecar.
- Claude (Haiku 5.5, tested) recognises every syntax we tried without being told, but left alone it "deals with" a review by accepting everything and deleting the comments. One convention paragraph in its context turns that around: it leaves marks pending, replies in the thread with the right id and proposes edits as marks. That paragraph is the main lever, and Duo can inject it without touching the user's project.
- Duo already intercepts Claude's edits (the pre-edit hook, DL-78) and diffs them into minimal changes. That is the natural place to turn Claude's edits into suggestions, so tracking doesn't depend on Claude obeying a convention.
- `@claude` needs a target session, a send rule that never lets a file from someone else start a turn on its own, and a reply path. The reply path exists already: Claude's Edit goes through the hook into the live buffer, so it merges with your typing.

## 1. Tracked changes in Markdown

### 1.1 CriticMarkup

The spec, from the CriticMarkup toolkit README (https://github.com/CriticMarkup/CriticMarkup-toolkit/blob/master/README.md):

| Mark | Syntax |
|---|---|
| Addition | `{++ text ++}` |
| Deletion | `{-- text --}` |
| Substitution | `{~~ old ~> new ~~}` |
| Highlight | `{== text ==}`, usually followed by a comment |
| Comment | `{>> note <<}` |

What the spec says, and doesn't:
- **Paragraphs.** Additions and deletions may span paragraphs, with the markers at the boundary; the README recommends avoiding newlines inside marks "as much as possible". Substitutions treat newlines by side.
- **Markdown inside marks.** One rule: wrap Markdown pairs completely (don't split `*italic*` across a marker).
- **Nesting, code spans, escaping.** Not covered. Implementations disagree: pymdownx.critic warns the marks "can alter the actual source" and view mode can emit invalid HTML around lists (https://facelessuser.github.io/pymdown-extensions/extensions/critic/); pancritic warns nesting "might have unexpected behavior" (https://pypi.org/project/pancritic/); pandoc's maintainer raised the precedence of code inside an insertion in December 2025 (https://github.com/jgm/pandoc/issues/2873).
- **No author, date, id, threads or resolved state.** Every tool that needs them extends the syntax (§1.2).
- **Activity.** The toolkit has 851 stars and its last commit was 2021-02-27 (GitHub API, measured 2026-10-27). It is frozen; the activity is downstream.

### 1.2 Extensions and implementations

| Tool | What it does with CriticMarkup | Signature format | Source |
|---|---|---|---|
| MultiMarkdown 6 | Renders; library flags accept / reject | none | https://github.com/fletcher/MultiMarkdown-6 (deprecated for MMD 7) |
| Marked 2, nvUltra, MultiMarkdown Composer | Render, accept/reject | none | https://markedapp.com/help/CriticMarkup.html, https://nvultra.com/help/preferences-criticmarkup |
| Python-Markdown (pymdownx.critic) | `view` / `accept` / `reject` modes | none | facelessuser link above |
| Pandoc | **No native support.** #2873 open since 2016; #5430 (pass-through) open | — | https://github.com/jgm/pandoc/issues/2873, /5430 |
| Quarto | Community Lua filter `mloubout/critic-markup` (HTML only) | none | https://github.com/mloubout/critic-markup |
| Obsidian **Commentator** (Fevol, 262★, beta via BRAT, not in the official directory) | Suggestion mode, accept/reject, replies | JSON before `@@`: `{++{"author":"Fevol"}@@text++}`; replies are adjacent comments `{>>a<<}{>>reply<<}` | https://github.com/Fevol/obsidian-criticmarkup/releases, https://forum.obsidian.md/t/new-plugin-commentator/66013 |
| Obsidian **Inkling** (Commentator fork, 210 downloads) | Adds a **resolved** state, stored once on the thread's base; option to delete on resolve | Legacy JSON, or a trailing attribute block `{>>note<<}{author="Andrew" time=1791819807}` | https://community.obsidian.md/plugins/inkling-markup |
| Obsidian **Review Comments** (3,005 downloads) | Threads by repeated id; resolve **moves the thread to a monthly file** (a sidecar) | `{>>id\|author\|date\|TYPE: comment<<}` | https://community.obsidian.md/plugins/review-comments |
| Review Comments AI (161) | Sends open threads to the local `claude` CLI, writes answers back as CriticMarkup | as above | https://www.obsidianstats.com/plugins/review-comments-ai |
| Track Changes (3,590), Review Critic (2,146) | Side panel to accept, reject or reply | not inspected | Obsidian directory |
| Redline (2,867) | Comments in a sibling `.review.md` **sidecar** | — | Obsidian directory |
| Basic Memory | Plain CriticMarkup in the body; ids, authors, threads and resolve **kept outside** the Markdown; tells assistants to use a `review_note` tool rather than write markup | — | https://docs.basicmemory.com/cloud/comments-and-suggestions |
| Adeu | Word → CriticMarkup for an LLM, the model's edits back into Word tracked changes | — | https://github.com/dealfluence/adeu |
| **Legacy Duo** (Electron) | Inline CriticMarkup with metadata in the comment: `{>>id:…\|author:…\|ts:…\|reply-to:…\|body<<}` | pipe-delimited | `docs/research/legacy-duo-architecture-review.md:250`, `stack-editor-and-webview.md:28` |

Downloads for the JavaScript parsers are tiny (npm, 30 days to 2026-10-26: `markdown-it-criticmarkup` 42, `markdown-it-critic` 25, `remark-critic-markup` 16). The Obsidian ecosystem has more than ten review plugins, each under about 4,000 downloads, none in agreement on a signature.

**What this means.** CriticMarkup's five marks are the shared floor. Above it there is no standard: we pick a signature, and the honest goal is "every CriticMarkup tool still sees valid marks", not "every tool understands our authors".

### 1.3 Other approaches

- **Pandoc spans.** Pandoc's docx reader with `--track-changes=all` emits spans with classes `insertion`, `deletion`, `comment-start`, `comment-end` and `author`/`date` attributes (https://pandoc.org/MANUAL.html; AST confirmed in pandoc's test fixtures `track_changes_insertion_all.native`, `comments.native`). In Markdown that's `[text]{.insertion author="x" date="…"}`. It is an interchange format, not one people write; GitHub and Obsidian show it as literal brackets and braces.
- **HTML `<ins>`/`<del>`** with `cite`/`datetime`. GitHub renders them (underline, strikethrough) and keeps the elements (measured with GitHub's render API). No authors shown, no comments, and raw HTML is outside the GFM subset DL-123 keeps for Google Docs.
- **HTML comments** `<!-- … -->`. Hidden on GitHub (measured) and, as expected, in Obsidian's reading view (not tested here: Q-246). Good for invisible notes; bad for review, because the reader of the rendered page never sees them.
- **Obsidian `%%comments%%`.** Hidden in Obsidian's reading view, literal on GitHub (measured).
- **Footnotes as comments.** `text[^c1]` with `[^c1]: **Geoff** (2026-10-27): …`. Renders well everywhere (GitHub draws a numbered note list, measured). It is what DL-123's converter does with Word comments today. Anchors are a point, not a range; threads are one long footnote line.
- **iA Writer Authorship** stores who wrote which ranges (human or AI) in a hash-checked block at the end of the file, visible in other editors and stripped on export (https://ia.net/writer/support/editor/authorship/authorship-mac; format proposal https://talk.commonmark.org/t/markdown-annotations/4549). It's attribution, not review: no proposals, no comments. A user reported the trailing block broke a GitHub-to-Hugo pipeline.
- **Ulysses** has its own markup (`++comment++`, `%%` comment paragraphs, `{annotation}`); plain Markdown export loses it (https://help.ulysses.app/dive-into-editing/comments-notes-annotations).
- **GitHub suggested changes** are a ```` ```suggestion ```` block in a PR review comment, tied to diff lines; applying one commits it with the reviewer as co-author (https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/incorporating-feedback-in-your-pull-request). Not a file format.
- **Exports.** Google Docs' Markdown download (July 2024) is not documented to keep suggestions or comments, and one source says the export URL drops both (unverified: Q-247). Notion's Markdown export drops comments. Pandoc's docx reader accepts changes by default and drops comments. So almost every route into Markdown today loses the review.

### 1.4 What's actually used

CriticMarkup's five marks, read by a handful of Markdown apps and a cluster of small Obsidian plugins, each with its own signature or a sidecar. Agent tools for review mostly work out of band (Plannotator, 9.7k★, on Claude Code's plan step; MCP tools; CLI bridges). Nobody owns "review in a Markdown file between a person and Claude"; Duo would be early.

## 2. Comments with authors, in the file

Geoff: "I really want to avoid a sidecar." Every option below keeps everything in the `.md` file.

| Convention | Example | GitHub (measured) | Obsidian, no plugin | Notes |
|---|---|---|---|---|
| **CriticMarkup + readable signature** | `{==We store nothing.==}{>>@geoff 2026-10-27 #c1: True for crash reports?<<}` | literal text, readable; `@geoff` is not linked in a file view (it is in issue/PR comments) | literal braces, `==…==` inside braces likely drawn as a highlight (Q-246) | Tested best with Claude (§3). |
| CriticMarkup + JSON (Commentator) | `{>>{"author":"geoff","time":1793000000}@@True for crash reports?<<}` | literal, noisy | literal, noisy | Readable by Commentator; epoch times aren't readable by people. |
| CriticMarkup + trailing attributes (Inkling, Pandoc-like) | `{>>True for crash reports?<<}{author="geoff" date=2026-10-27 id=c1}` | literal | literal | The attribute block is outside the mark, so a CriticMarkup-only tool shows it as stray text. |
| Pipe fields (Review Comments, legacy Duo) | `{>>c1\|geoff\|2026-10-27\|True for crash reports?<<}` | literal | literal | Compact; fragile to a `\|` in the body. |
| HTML comments | `<!-- c1 geoff 2026-10-27: True for crash reports? -->` | hidden | hidden in reading view (expected) | Invisible to anyone reading the rendered doc. |
| Footnote threads | `We store nothing.[^c1]` … `[^c1]: **Geoff** (2026-10-27): …` | rendered as notes | rendered as notes | Point anchors; a thread is one paragraph; resolve = delete two places. |

**Threads, ids and edits.** A reply is a comment written right after its parent (Commentator's rule) and carries the parent's id with a suffix (`#c1.1`). Adjacency alone breaks if someone types between them; the id keeps the thread together. Ids are short and per file (`c1`, `s3`), chosen by whoever writes the comment (Duo picks the next free number; Claude is told to do the same). Duplicate ids after a merge are repaired by Duo on open (renumber the later one), never by deleting.

**How they survive edits.**
- *By people in Duo:* the marks are text in the buffer, so they move with the text. Duo hides the delimiters, so a person can't half-delete one by accident; Source mode shows them raw.
- *By people elsewhere* (Obsidian, GitHub, a text editor): plain text, so they survive unless someone deletes them. A partly deleted mark (`{++ never closed`) must degrade to plain text, not swallow the rest of the paragraph (the prototype checks this, §4.1).
- *By Claude:* tested (§3.3). With no convention, an unrelated edit kept every mark and comment intact. With the convention, Claude went further and tracked its own edit as a signed suggestion.
- *By Duo's three-way merge* (DL-77): marks are text, so they merge like text; a sidecar wouldn't merge at all.

## 3. How Claude reads each syntax today (experiments)

**Method.** Five versions of the same one-page doc (inputs in `docs/research/markdown-review-samples/input/`): A plain CriticMarkup; B CriticMarkup with signatures and a reply thread; C HTML `<ins>/<del>` and HTML comments; D footnote threads; E pandoc spans. Each has a substitution, two insertions, a question on a sentence with a teammate's reply, and a comment asking "@claude can you tighten this paragraph?". Each was handed to a fresh Haiku 5.5 agent (Claude Code's own agent harness, no prior context) with Geoff's words: "I've reviewed the doc at … Please go through the review and deal with it, then save the file." Two more ran with a short convention paragraph first (A1, B1), and two (Bx0, Bx1) were asked for an unrelated edit to see whether marks survive. Outputs are in `…/after/`. Small sample, one run each: read it as direction, not measurement.

### 3.1 Recognition: all five syntaxes understood, unprompted

Every run listed every item correctly, with authors where the file had them (B, C, D, E) and "author unknown" where it didn't (A). Claude understood that `{>>@sam … #c1.1<<}` was a reply to `#c1`, that `@claude` addressed it, and that `{~~30~>10~~}` meant 30 became 10. **Recognition is not the problem.**

### 3.2 Behaviour without a convention: "deal with it" means accept everything and delete the comments

| Run | Changes | Comments | Replied where |
|---|---|---|---|
| A0 plain CriticMarkup | accepted all | deleted all | chat only |
| B0 signed CriticMarkup | accepted all, **including its own earlier proposal** | deleted all | chat only |
| C0 HTML | **left pending** | kept; replied in the file as `<!-- reply to=c1 author=claude … -->` | file |
| D0 footnotes | (none pending) | kept; appended "**Response**" to the footnote | file |
| E0 pandoc spans | accepted all | deleted all | chat only |

So the syntax changes behaviour: comments that look like discussion (HTML comments, footnotes) were kept and answered; CriticMarkup was treated as a to-do list to clear. In the CriticMarkup runs the review history vanished, and Claude accepted suggestions nobody had approved.

### 3.3 With a convention paragraph: pending stays pending, replies land in the thread

The paragraph used (B1):

> Review marks in Markdown use CriticMarkup with a signature: {++added++}, {--deleted--}, {~~old~>new~~}, {==highlight==}, each followed by {>>@author date #id: note<<}. Marks are suggestions awaiting a person's decision: never accept or reject one unless asked. To propose an edit, write it as a mark signed @claude instead of changing text. Reply to a comment by adding {>>@claude date #id.n: reply<<} right after it; don't delete or rewrite anyone's comment. A comment that names @claude is addressed to you.

- **B1:** accepted nothing, replied to `#c2` with a correctly formed `{>>@claude 2026-10-27 #c2.1: …<<}`, and, because "this paragraph" was ambiguous (it's one sentence), asked which paragraph rather than guessing. It also flagged that Sam's reply contradicted the highlighted sentence, without editing it.
- **A1** (plain variant): left marks pending, answered the question in the thread (after checking the repo), and proposed its tightening as a substitution mark rather than editing.
- **Bx1** (unrelated edit, convention on): wrote its own edits as signed suggestions: `{~~November~>December~~}{>>@claude 2026-10-27 #s4: …<<}`, and a new section as `{++## Pricing⏎⏎Duo is free.++}`, an addition that **spans paragraphs**. That's legal CriticMarkup but the hard case for parsers (§4.1).
- **Bx0** (unrelated edit, no convention): edited plain text and kept every mark and comment untouched.

**Conclusions.**
1. A short convention paragraph is enough to get the behaviour we want from Claude, even Haiku. This is the cheapest and most important part of the design.
2. It must be in the session's context, not left to chance: Duo's session context hook (DL-116, `duo2 hook context`) can add it without writing to the user's CLAUDE.md (Q-243 covers sessions outside Duo and hooks turned off).
3. Relying on Claude to write the marks is not enough for "Claude's edits become suggestions": a model can still edit plainly. Duo should make the suggestion itself from the edit it already intercepts (§5.2). The convention then matters for replies and for sessions running outside Duo.
4. Without a convention, "deal with the review" destroys the review. Even with Suggest mode, Accept All / Reject All belong to the person.

## 4. Recognition by Duo

### 4.1 The editor

Facts from the code (survey, 2026-10-27):
- CodeMirror 6 is vendored in `Vendor/codemirror/` (`src/duo-editor.js`, bundled to `dist/cm6.js` by `build.sh`), with `@lezer/markdown` 1.7.2. The language is `markdown({ base: markdownLanguage })` at `duo-editor.js:2167` with no `extensions:` yet, so a CriticMarkup inline extension slots in there.
- Live preview hides marks off the caret's line (`buildDecorations`, `:137`) and draws widgets. A review layer is one more StateField beside `addedField` and `changesField`, and joins the `previewLive` compartment so Source mode (DL-167) shows the raw text.
- Claude's edits today: the PreToolUse hook (`duo2 hook pre-edit`, DL-78) sends each Edit to Duo, which applies it to the live buffer as minimal diff hunks (`agentEdit`, `:2408`), highlights them (`claudeEdit`, DL-186) and records them for Revert until your next edit. The hook carries the session id (`CLAUDE_CODE_SESSION_ID`), but Duo doesn't store it. Nothing about Claude's changes persists in the file.
- Outside writes arrive through a watcher on the open file and its folder (`DocumentEditor.swift:551`), debounced 150 ms, and a line-based three-way merge (`merge3`, `:2335`, DL-77). Only the open document is watched.

The parsing prototype (on this branch's scratch, results in §4.1a) tests the inline extension against the edge cases: code spans and fences, emphasis inside marks, an unclosed mark, GFM strikethrough inside a substitution, list items and table cells, and a paragraph-spanning addition.

### 4.1a Prototype results

A throwaway inline extension against the vendored versions (`@lezer/markdown` 1.7.2, `lang-markdown` 6.5.2); code in `docs/research/markdown-review-samples/prototype/` (`critic.mjs`, about 65 lines; `node test.mjs` after `npm ci` in `Vendor/codemirror`). **15 of 16 cases pass**:
- all five marks; a signed comment with an `@claude` mention, and a reply signed `@claude` that is *not* a mention;
- emphasis inside a mark; `~~x~~` inside a substitution; plain `~~gone~~` still strikethrough;
- marks in a list item and a table cell; a comment containing `<<` and `}`;
- nothing parsed inside inline code or a fenced block; an unclosed `{++` stays plain text.

**The one failure is the paragraph-spanning addition** Claude wrote in Bx1: inline parsing works one paragraph at a time, so `{++## Pricing⏎⏎It is free.++}` comes out as two plain paragraphs. It needs a document-level decoration pass (a StateField over the raw text that skips code ranges from the syntax tree), about 40 to 80 more lines. The whole layer is about 150 lines in a new `src/critic.js` plus one line of wiring, no new dependency. Two edges to handle: a `|` inside a comment in a table row splits the cell (GFM splits cells before inline parsing; Duo writes `\|` there), and comments are opaque (no Markdown inside), which is what we want.

Alternatively Duo could steer around the hard case: when Duo writes a multi-paragraph suggestion it can write one mark per paragraph, all with the same id (`{++## Pricing++}{>>@claude #s5<<}` ⏎⏎ `{++It is free.++}{>>@claude #s5<<}`). Claude's own hand-written marks may still span paragraphs, so the pass is still needed to read them.

### 4.2 Previews and elsewhere

- **GitHub** (measured with GitHub's render API, `mode: markdown` as for files): every CriticMarkup mark shows as literal text, readable and unhighlighted. `{~~old~>new~~}` is **not** struck through, but a substitution with a `~~…~~` pair inside (`{~~a ~~x~~ b~>c~~}`) or a bare `{~~x~~}` is. `@names` aren't linked in file views (they are in the issue/PR comment mode). HTML comments vanish; `<ins>/<del>` render; footnotes render as a notes list.
- **Obsidian, no plugins:** `==x==` is Obsidian's highlight and `~~x~~` its strikethrough (https://help.obsidian.md/edit-and-read), so `{==x==}` is expected to show braces around a highlight; the other marks show literally. With Commentator or Inkling installed, the five marks render as review marks; our readable signature shows as comment text. Not checked in the app here (Q-246).
- **OKF** (Google Cloud's Open Knowledge Format, v0.1, June 2026) is folders of Markdown with YAML frontmatter (https://hjarni.com/docs/open-knowledge-format.md). In-body marks survive as text; nothing goes in frontmatter, so line 1 stays `---` for Duo's properties block. A trailing machine block like iA's would be the thing to avoid.
- **Duo's other renderers.** Chat mode's Markdown (`ChatMarkdown.swift`) would show marks literally in a quoted message; that's fine. There's no Markdown Quick Look or HTML export in Duo today.

## 5. Fit with what exists

### 5.1 Word documents (DL-162, DL-123, Q-62)

- The docx viewer already draws a review layer: author colours (`reviewAuthor1…5`), insertions underlined and deletions struck in each author's colour, comments as cards under their paragraph with nested replies and resolved threads folded, a hover label ("Casey Counsel inserted · 7 Sep"), and a Markup menu (All Markup, Simple Markup, No Markup, Original). The Markdown review should look the same: one review language in Duo.
- The model is already there: `Docx.Change {kind, author, date, text}` and `Docx.Comment {id, author, date, text, parent, thread, resolved}` (`Sources/DuoSearch/DocxOutline.swift:8`).
- DL-123's converter accepts tracked changes and turns comments into endnotes. With a Markdown review syntax, Convert to Markdown can keep both: changes as signed marks, comments as signed threads, resolved ones dropped (or kept, per the resolve decision). That answers Q-62. The converter already reads both sides of each change.

### 5.2 Claude's edits (DL-5, DL-186)

DL-5 named this path in v1: "Later: tracked suggestions (CriticMarkup)". Today's highlight is temporary and in memory. A per-document **Suggest Edits** switch can change what the pre-edit hook does: instead of applying Claude's edit, Duo writes the same minimal hunks as signed marks (`{~~old~>new~~}{>>@claude … #s4<<}`), so they persist and wait for Accept or Reject. Off, today's behaviour stands. Your own typing could follow the same switch (Word's Track Changes). Legacy's lessons hold (`legacy-requirements.md` LR-42): Reject All must give back the old document exactly, Accept All the new one.

### 5.3 Send to Claude (⌘D) and the chat mode

- ⌘D pastes the selection into the session showing in the console (DL-67 to DL-69), never presses Return. Sending a selection that contains marks should send the clean text plus the marks in words, as the docx Select Text does (`SendFormat+Docx.swift`).
- `@claude` is a different act: you're asking from inside the doc and expect the answer there. Its delivery needs Return pressed, which only `duo2 director send` does today, with guards (idle, empty prompt, no typing for 2 minutes). The same guards apply.
- In the chat mode, an `@claude` turn shows as your message (with the comment quoted) and Claude's reply as usual; the thread in the file gets the reply as an edit.

## 6. @claude in a comment

Worked through here and, for a read not anchored on this one, separately by a Fable 5.1 study given the same facts. Where they differ, both are on the decision page.

**Framing.** An `@claude` comment is a message with an address. The comment in the file is the record; delivery (queued, sent, replied) is Duo's state, kept out of the file so it doesn't churn git.

### 6.1 Which session catches it

| Candidate | For | Against |
|---|---|---|
| The session that last edited the file | It wrote the doc and has the context (the PM-review story) | Duo doesn't record it yet (the id is at `.docEdit`, unused); often a finished worker, now stopped; the doc's author isn't always the right reviewer |
| The session showing in the console | Matches ⌘D (DL-69); the user is looking at it | Arbitrary when the user has been hopping between sessions |
| The document's task session (`sessions:` in the task note) | Ties the doc to its work | Only some docs belong to a task; a task can have several sessions |
| A session the user picks | Never wrong | A question every time |
| A new session | Clean, never busy | Loses the doc's context; a session per comment clutters the list |
| The project's director | Routes work | A director delegates; an answer should come from the doer |

**Proposed rule (recommendation).** Show the target before sending, as a chip on the comment ("→ Offline one-pager · at prompt ⌄") with the same list as Send To. Its first guess, in order: the session this thread already went to (replies go back where the answer came from); the session the user chose last time for this document; the session that last edited the document through Duo, if live or resumable; the session showing in the console; else New Session. Sending to the chip as shown is consent. The choice is remembered per document in Duo's own state.

The Fable study proposes the same chip but stores the binding in the file's frontmatter (`claude-session:`) and leaves "last editor" out. Keeping the binding out of the file avoids writing a machine-local session id into a shared document that teammates, GitHub and Obsidian see (Q-241).

**Hard cases.**
- *The target is stopped.* Resume it (`claude --resume <id>`, in the background), then deliver. On the work Mac's 2.1.219 a transcript written elsewhere can't be resumed (F-208): the chip says "can't resume here" and offers New Session.
- *Several live, none chosen.* The chip's guess is visible; one click changes it.
- *None running.* New Session in the project, with the file named in the turn; the chip said so before sending.
- *The target is working or waiting on a permission prompt, or has unsent text in its prompt.* Don't type into it. The comment shows "Queued: waits for *X* to be ready" and sends at the next idle-with-empty-prompt, the guard `duo2 director send` uses (DL-199). Never append to or clear a person's draft.
- *Work Mac, 2.1.219.* Delivery is paste then Return, which 2.1.219 takes (external-editor handover needs 2.1.269; F-208 and `ChatScreen.swift`). Readiness comes from the Beacon status files, which 2.1.219's hooks write.

### 6.2 When it goes

- **Posting the comment in Duo sends it.** The user typed `@claude` to a target they can see; waiting for ⌘S adds a pending state nobody will model.
- **A batch is an option**: "Hold for review" collects `@claude` comments, and **Send Review** sends them as one turn (a better prompt when there are eight comments).
- **Comments that arrive from disk never send on their own** (C-112): a teammate's comment pulled from git, written in Obsidian, or written by another Claude. They show as "Not sent · from Sam" with a Send button and the chip. Reasons: a file from someone else would otherwise start a turn with your session's tool permissions (prompt injection by document); the user would see Claude start work with no action of theirs; two Macs with the same file would both send.

### 6.3 What the turn says, and how the reply lands

The turn is plain text, so it pastes on 2.1.219 too:

```
@claude comment in docs/offline.md, line 9 (thread c2), from Geoff, 27 Oct 14:02
On: "Launch is planned for early November."
> can you tighten this paragraph? It reads long.
Reply in the thread: duo2 comment reply c2 "<text>"   (add --suggest to propose an edit)
```

It carries the path, the line at send time, the thread id, the anchor's text (lines move; the text is the stable handle), the comment, and the thread so far if it's short. The comment is quoted, as data: Claude answers it; it isn't a system instruction.

**The reply.** Two routes, both through code that exists:
1. `duo2 comment reply <id> <text> [--suggest]` (new verb): Duo writes the reply with Claude's signature and the next id, into the live buffer if the doc is open (the `agentEdit` path, so it merges with typing), else to disk; the watcher's three-way merge handles the rest. This is the route the turn names.
2. Claude edits the file by hand, following the convention (§3.3): the pre-edit hook routes the Edit into the live buffer as today. Works with Duo absent too.

Anchor drift: re-anchor by text before every write; a thread whose anchor text is gone stays at its last place, marked "text changed", never dropped.

### 6.4 Status

On the comment: **Queued** (waits for *X*), **Sent to *X*** · time, **Claude is replying** (X turned working after the send), **Replied**, **Not delivered** (*X* ended / couldn't resume here) with Send To…, Retry, Open Session. The session's row in the list can carry the same note so the user can find who's on their comment.

### 6.5 duo2 verbs (DL-71)

- `duo2 comment add <path> --at <line|text> [--reply-to <id>] <text>` (what the composer does; sends when it names @claude)
- `duo2 comment list <path> [--open|--unsent|--resolved]`
- `duo2 comment reply <id> <text> [--suggest]`
- `duo2 comment send <id|--all> [--to <session>|--new]` (Send on a comment from disk, and Send Review)
- `duo2 comment resolve <id> [--dismiss]`, `duo2 comment status <id>`
- `duo2 suggestion list|accept|reject <id|--all>`
- `duo2 doc review on|off` (the Suggest Edits switch), `duo2 doc markup all|simple|none|original` (the existing docx verb, extended)

### 6.6 The riskiest failures

1. **A turn started by someone else's text** (C-112). Covered by: never sending from disk; quoting the comment as data; logging who sent what.
2. **Return pressed into a session that isn't ready** (a permission prompt, the user's draft). Covered by the idle-and-empty-prompt guard re-read just before typing; if it fails after the paste, don't press Return and say "pasted into *X*, not sent", which is ⌘D's behaviour users know.
3. **The reply clobbers typing or lands in the wrong place.** Covered by the live-buffer path and re-anchoring by thread id.
4. **Two Macs, one file.** Status is per Duo, so a comment could be sent twice. Accepted: two replies in the thread, visible and cheap.

## 7. Records

- **F-370** Claude reads every review syntax unprompted, but without a convention it clears a CriticMarkup review (accepts all, deletes comments); one convention paragraph fixes it (§3).
- **F-371** CriticMarkup on GitHub and in Duo's editor: literal on GitHub except `~~` pairs inside marks; Lezer inline extension feasibility and the paragraph-spanning case (§4).
- **C-112** An `@claude` comment arriving from disk (a teammate, git, Obsidian) could start a Claude turn with tool permissions: prompt injection by document. Only comments the user posts in Duo send on their own (§6).
- **Q-240 to Q-247** open questions (in `docs/plan/concerns-and-questions.md`).
