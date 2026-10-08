# Source links for downloaded Google files

Status: **decided, DL-163** (Geoff, 2026-10-08). Research sprint, 2026-10-08. The designs are on the canvas listed in `docs/design/source-links-study/README.md`. Records: F-238 to F-241, Q-154 to Q-157, C-70, ENH-55 to ENH-57.

**What Geoff decided (DL-163).** A thin bar under the viewer's bar offers Add Source (one click when the browser's record knows the Google link). The first source in a folder creates `_sources.md` there, and later ones add a line. In later sessions the bar carries the link. Newer downloads, compare and replace work for any file, with or without a source. Replace sends the old copy to the Trash, with Undo. Where this page's proposals differ (§4's note beside each file, recording on arrival), DL-163 wins.

Geoff, 2026-10-08: "at work, we are primarily a google apps shop; but duo and claude cannot access google docs (not allowed by browser, not possible by mcp); so I will often download slides or a google doc as a pptx or docx; but it is useful to know where that file came from (ie the canonical url) … adding the url, clicking the url to open it in the default browser; replacing one snapshot of a file with a more recent download, etc; maybe even watching the downloads folder for recent downloads of an existing snapshot, and duo offering a visual side-by side and offering to replace the existing in-project file with the freshly downloaded one".

Marks: **[V]** verified here, either by an experiment on this Mac (macOS 27.0, Chrome 155.0.8059.40) or by reading a primary source. **[U]** unverified: secondhand, from memory, or not tested. **[P]** a proposal.

## The answer in short

1. **Google's export writes no metadata at all.** A `.docx` or `.pptx` from `…/export` has no `docProps/core.xml`, `app.xml` or `custom.xml`, so it carries no title, author or source id [V]. The file can't say where it came from.
2. **The browser records it.** Chrome sets `com.apple.metadata:kMDItemWhereFroms` on the download. The first entry is the final export URL on `googleusercontent.com`, and it ends in the document's id (`…/*/<ID>?format=docx`). The second entry is only the referrer's origin, `https://docs.google.com/` [V]. The canonical link, `https://docs.google.com/<kind>/d/<ID>/edit`, follows from that id and the host [V]. Spotlight indexes the attribute, so one query finds every download of the same document [V].
3. **That record is fragile.** It survives `cp`, `mv`, `ditto`, `FileManager.copyItem`, tar and Finder's Compress. It is lost through git, `zip`/`unzip`, `cp -X` and any app save that writes a new file and renames it over the old one [V]. So Duo should read it once, when the file arrives, and keep it somewhere sturdier.
4. **Writing it into the file works by the spec but mutates the file.** OPC allows `dc:identifier`. `custom.xml` can carry a named text property that Word and PowerPoint show. But the file's hash changes, git sees a change, Google's re-import probably drops it [U], and the view-only paths (DL-121, DL-162) must never write.
5. **Decided (DL-163):** read WhereFroms to *offer* the link in a thin bar under the viewer's bar. When the user adds it, write a line to the folder's `_sources.md`. Spot newer downloads of any .pptx or .docx through Spotlight, by name, and by Google id when known; offer a side-by-side compare and Replace with Undo. **Get Latest** opens the export link in the default browser for files with a Google source. Duo never lists ~/Downloads by itself.

## 1. What OOXML can hold

### Core properties (`docProps/core.xml`, ECMA-376 Part 2, OPC)

| Property | Allowed | Notes |
|---|---|---|
| `dc:title`, `dc:creator`, `dc:description`, `dc:subject`, `dc:language`, **`dc:identifier`** | yes | Dublin Core elements that OPC allows. `dc:identifier` is optional and a plain string [V: schema quoted in python-pptx's analysis; Microsoft's property list]. |
| `dcterms:created`, `dcterms:modified` | yes | The only two that take `xsi:type="dcterms:W3CDTF"` [U: from the SC34 list, not read in ECMA's text]. |
| `cp:keywords`, `cp:category`, `cp:contentStatus`, `cp:version`, `cp:revision`, `cp:lastModifiedBy`, `cp:lastPrinted` | yes | `cp:` namespace [V]. |
| **`dc:source`, `dc:relation`** | **no** | Not in OPC's subset of Dublin Core [V by absence from the list]. Writing them makes the package invalid by the schema. Word's tolerance for that is untested [U]. |

The most fitting slot is `dc:identifier`. Word's Advanced Properties dialog doesn't show it [U], so a user wouldn't see it.

### Extended properties (`docProps/app.xml`)

`HyperlinkBase` is "the base string used for evaluating relative hyperlinks in this document" (ISO/IEC 29500-1 §22.2.2.21) [V]. Word and PowerPoint show it as "Hyperlink base" on the Summary tab [U]. **It is not a free-text field.** Setting it to the Google URL would change where every relative link in the document resolves. Google's exports use absolute links, so the risk is small, but it is the wrong field.

### Custom properties (`docProps/custom.xml`)

Each `<property fmtid="{D5CDD505-2E9C-101B-9397-08002B2CF9AE}" pid="2…" name="…"><vt:lpwstr>…</vt:lpwstr></property>` is a named, typed value [V: the structure; U: the fmtid constant and pid≥2 are standard practice, not read in the spec]. Word and PowerPoint show these under File › Properties › Custom, typed Text, Date, Number or Yes/No [U]. There is no URL type. The `linkTarget` attribute ("Link to content") points at a bookmark, not a URL [V]. A property such as `Source = https://docs.google.com/presentation/d/…/edit` is the most visible in-file option.

### Round trips

| Through | identifier / keywords / custom | Status |
|---|---|---|
| Word, PowerPoint (save) | kept | [U]: standard behaviour, not tested (neither app is installed here) |
| Upload to Google Docs or Slides, then export | lost: Google's export writes no `docProps` at all | [V] for export (§2); the import side is moot, because whatever survives import isn't exported |
| Pages, Keynote (export to .docx/.pptx) | unknown | [U]: not tested; both apps are installed but would show windows (needs Geoff's OK) |
| LibreOffice | custom kept; an identifier was reported cleared (6.4.6) | [U]: Ask LibreOffice thread |

**So an in-file link survives Office but not the trip back through Google.** For Geoff's flow (Google → download → Duo), the in-file link would only ever live in Duo's copy.

## 2. What Google's export writes [V]

These are public samples downloaded without signing in: the Docs API quickstart document `195j9eDD3ccgjQRttHhJPymLJUCOUjs-jmwTrekvdjFE` and the Slides API sample deck `1EAYk18WDjIG-zp_0vLm3CsfQh_i8eXc67Jo2O9C6Vuc`. Script and files: the session scratchpad. The raw outputs are summarised below.

- **No `docProps/` at all.** The .docx has 9 parts (document, styles, numbering, settings, fontTable, theme, rels, content types). The .pptx has 76 parts. Neither has core, app or custom properties. Nothing in either package names the document, its id, its owner or Google, except as below.
- **The .pptx names shapes `Google Shape;<n>;<pageId>`.** Notes pages carry the slide's page object id: `Google Shape;24;ge63a4b4_1_0:notes` belongs to slide 1, which is linked from `slide1.xml.rels` to `notesSlide1.xml`. That id is the one in Slides' own link, `…/edit?slide=id.ge63a4b4_1_0#slide=id.ge63a4b4_1_0`. **So Duo can link each slide straight to the same slide in Google Slides.** It can also match slides between two downloads of the same deck by page id, even after they are reordered.
- **The file's name is the document's title.** `Content-Disposition: attachment; filename="DocsAPIQuickstart.docx"; filename*=UTF-8''Docs%20API%20Quickstart.docx`. Chrome saved it as `Docs API Quickstart.docx`.
- **The same document downloaded twice is not byte-identical.** Zip entries carry the export time, so the file hashes differ. In the deck, `ppt/media/imageN.png` numbering and the slide rels shuffle between exports, while the XML of the slides themselves is identical. In the document, every part was identical. **"Has it changed?" therefore has to compare normalized contents (each part's text, and images as a set of hashes), not the file hash.**
- **The export redirects.** `docs.google.com/document/d/<ID>/export?format=docx` answers with a 307 to `doc-0g-3o-docstext.googleusercontent.com/export/<token>/<token>/<time>/<number>/*/<ID>?format=docx`. Slides goes to `doc-04-bs-slides.googleusercontent.com/…/*/<ID>?exportFormat=pptx`. The path holds short-lived tokens and a long number. The number differed between the two documents, so it looks like the owner's account id [U]. **Duo must never store or show this URL, only the canonical one.**

## 3. macOS provenance

### What Chrome records [V]

Headless Chrome 155 was run with a scratch profile whose download folder was a scratch folder; nothing touched ~/Downloads or a Google account.

| Download | `kMDItemWhereFroms` | `com.apple.quarantine` |
|---|---|---|
| Typed export URL | `[<googleusercontent final URL>]` | `0081;<time>;Chrome;<UUID>` |
| Clicked from the document's `/edit` page | `[<googleusercontent final URL>, "https://docs.google.com/"]` | same |
| Via DevTools `Browser.setDownloadBehavior` | **none** | `0081;…;Chrome;` (no UUID) |

- The first entry is the **final** URL after redirects, which still ends in the id.
- The referrer is cut to its origin by the page's referrer policy, so the `/edit` URL is never recorded. The kind (document or presentation) comes from the host (`docstext`, `slides`) or the export's path.
- Downloads driven by automation through DevTools get no WhereFroms. That matters only for tests.
- The quarantine UUID keys a row in LaunchServices' QuarantineEventsV2 database, which also holds the URLs. Duo shouldn't read it: it is private to the user, and the xattr already says the same thing.

### Other browsers

| Browser | WhereFroms | Status |
|---|---|---|
| Chrome | `[source, referrer]`, at most two entries, written by `AddOriginMetadataToFile` in `components/services/quarantine/quarantine_mac.mm`. URLs left empty "e.g. files downloaded in Incognito mode" aren't written | [V] by test and source |
| Edge, Arc, Brave | the same code (Chromium) | [U]: not installed here |
| Firefox | `AddOriginMetadataToFile` is called only `if (pathCFStr && !aIsPrivate)`, so a private window writes neither WhereFroms nor quarantine | [V] source (`toolkit/components/downloads/DownloadPlatform.cpp`); not installed here |
| Safari | `[download URL, page URL]` | [U]: not tested, because a test would change Safari's own download folder setting |

### What survives [V]

The test file was a Chrome download carrying WhereFroms.

| Operation | WhereFroms |
|---|---|
| `cp`, `mv`, `ditto`, `FileManager.copyItem` (what Duo's own move and copy use), `tar` | kept |
| Finder's Compress (`ditto -c -k --sequesterRsrc`), then Finder's expand (`ditto -x -k`) | kept (`__MACOSX/._name`) |
| `zip` then `unzip` | **lost** |
| `cp -X` | **lost** |
| git: commit then clone, or delete then checkout | **lost** (git keeps no xattrs) |
| An app-style save (write a temp file, rename it over the original) | **lost** |
| iCloud Drive, AirDrop, a Word or PowerPoint save | [U]: AirDrop adds its own quarantine and WhereFroms, per Eclectic Light |

`com.apple.provenance`, an 11-byte attribute, is on every file this session's processes wrote. It identifies the app that wrote the file, not a URL, so it is no use here [V that it's present; U what it means].

### Spotlight [V]

`kMDItemWhereFroms` is indexed. `mdfind -onlyin <folder> 'kMDItemWhereFroms == "*<ID>*"'` found the deck in an indexed scratch folder under home, and the folder was deleted afterwards. `/private/tmp` isn't indexed. **One query by document id finds every download of that document**, wherever the browser put it, without Duo listing a folder. Two things are untested [U] (Q-155):
- whether an `NSMetadataQuery` run by Duo returns items inside ~/Downloads without the Downloads privacy prompt;
- whether reading such a file afterwards asks.

## 4. Where Duo keeps the link: the alternatives

| | A · Sidecar note [P] (recommended) | B · One sources file per folder | C · Duo's own state | D · Inside the file | E · WhereFroms only |
|---|---|---|---|---|---|
| What | `Q3 plan.pptx.md` beside the deck, with frontmatter | `SOURCES.md` listing each file and its link | a record in Duo's support folder | `custom.xml` `Source`, plus `dc:identifier` | read the xattr each time |
| Writes the file? | no | no | no | **yes** (hash, git diff, mtime) | no |
| Survives git, zip, another Mac | yes | yes | no | yes | **no** |
| Survives a rename in Finder | no: Duo heals it when it sees the rename; Obsidian renames neither | no | if Duo sees it | yes | yes (until a save) |
| Obsidian, OKF | a note; Properties show `source` as a link; the body links the file | a table, less native | invisible | invisible | invisible |
| Claude sees it | reads it like any file; `duo2 file source` | yes | only via `duo2` | via the docx/pptx readers | via `duo2` |
| Seen in Word or PowerPoint | no | no | no | yes (Custom tab) | no |
| Clutter | one note per snapshot | one file per folder | none | none | none |
| Allowed in view-only paths | yes | yes | yes | **no** (DL-162) | yes |

**Decided: B** (DL-163): one `_sources.md` per folder, as one Markdown list line per file, written only when the user adds a source:

```markdown
---
type: sources
---

# Sources

- [Q3 plan.pptx](./Q3%20plan.pptx): [Q3 plan](https://docs.google.com/presentation/d/1EAY…/edit) · Google Slides · downloaded 2026-09-30
```

E (WhereFroms) only feeds the bar's one-click offer. The recommendation was A: D is an explicit, later action ("Write Source into File", ENH-56) for someone who sends the file on and wants the link to travel inside it.

### The sidecar (proposed, not chosen)

The name is `<file name>.md`, e.g. `Q3 plan.pptx.md`. Obsidian lists it as a note called "Q3 plan.pptx" beside the deck, and a plain sort keeps the two together.

```markdown
---
type: snapshot
title: Q3 plan
source: https://docs.google.com/presentation/d/1EAYk18WDjIG-zp_0vLm3CsfQh_i8eXc67Jo2O9C6Vuc/edit
snapshot_of: "[Q3 plan.pptx](./Q3%20plan.pptx)"
downloaded: 2026-10-08T15:24
snapshots:
  - 2026-10-08T15:24
  - 2026-09-30T09:12
---

Snapshot of [Q3 plan](https://docs.google.com/presentation/d/1EAYk18WDjIG-zp_0vLm3CsfQh_i8eXc67Jo2O9C6Vuc/edit) in Google Slides, downloaded 8 Oct 2026.
```

- **Keys already in use:** `type` and `title` (OKF), `source` (Web Clipper, and Duo's capture, `second-brains.md` §5). `downloaded` and `snapshots` are new, and OKF consumers must keep keys they don't know.
- **Links:** `snapshot_of` uses a Markdown link, which both Obsidian and OKF read. A wikilink is Obsidian-only.
- **What it never holds:** the raw WhereFroms, the export URL or anything from the user's account. Only the canonical link.
- **Rename and move:** Duo moves or renames the sidecar with its file (its own Rename, Move, Trash). When it sees a rename it didn't do, it matches by `snapshot_of` and the old name, then heals the link.
- **Folders that aren't Google files:** the same note works for any file with any `source:` (a PDF from a web page, a CSV from a dashboard). Google files get the extras: the slide links, Get Latest and compare.

## 5. Getting the newer download

**Decided (DL-163): with or without a source.** A download is a newer copy of a project file when all of these hold:
- its name matches, once the browser's copy marks (` (1)`, `-2`) are stripped;
- it has a "Where from", so it really was downloaded;
- it is newer than the project copy;
- where either side knows a Google id, the ids agree.

Spotlight finds such downloads by name [V, F-241]. The rows below are how Get Latest and the fallbacks work.

Reading ~/Downloads asks macOS's privacy question the first time (F-28). Duo never walks into it on its own (`ProtectedFolders`), and never raises a system alert on its own. Four ways:

| | How Duo learns of the new file | Privacy question | Status |
|---|---|---|---|
| **1 · Get Latest + Spotlight [P] (recommended)** | Get Latest opens `…/d/<ID>/export?format=docx` (or `/export/pptx`) in the default browser, where the user is signed in. Duo runs a live Spotlight query for `kMDItemWhereFroms` containing the id for a few minutes. When the file lands, a notice offers Compare | Only when the user clicks Compare and Duo reads the file, if at all (Q-155) | Spotlight finding it [V]; the question not tested [U] |
| 2 · Replace with File… | an Open panel, starting in Downloads, filtered to the same kind; the newest file with the same id is preselected | none expected: a file the user picks in the Open panel counts as consent [U] | always works; the fallback when Spotlight is off |
| 3 · Check Downloads | a button that lists recent downloads with the same id | the first click asks | user-initiated, so acceptable, but a prompt |
| 4 · Watch Downloads (opt-in in Settings) | FSEvents on ~/Downloads | asked when the user turns it on | later (ENH-57), if 1 isn't enough |

Get Latest is the one move that skips the hunt entirely: the user never goes to the browser's File › Download.

## 6. Compare and replace

- **Decks:** match slides by Google page id (§2), then by position. Each pair is marked same, changed, new or removed, with a "Changed only" filter. They are drawn side by side in two narrow columns with the pptx renderer (DL-121).
- **Documents:** paragraphs are compared on the text from Duo's docx reader. Changes show as a redline, with an Old | New | Both toggle in the docx viewer (DL-162). Side-by-side pages are a fallback.
- **Same:** if the normalized contents match (§2), the notice says "No changes since 30 Sep" and offers no compare.
- **Replace:** the new file takes the old name in the project, so links, tasks' `references:` and Claude's memory of the path still hold. The old copy goes to the Trash, and the notice offers Undo. The sidecar adds the date to `snapshots:`. The download stays where it was; Duo doesn't touch ~/Downloads.
- **History:** git, if the project is a repo; otherwise the Trash. Keeping old snapshots beside the file (`Q3 plan (30 Sep).pptx`) is an option for Geoff (Q-156).

## 7. What Claude sees, and `duo2`

- The sidecar is a file in the project, so Claude can read it. `duo2 file source <path>` returns the link, the title, the kind and the snapshot dates as JSON.
- Anything Duo hands to Claude about the file names the source. That covers Send to Claude, a picked slide or shape (DL-125 D), and the docx reader. For example: "Q3 plan.pptx is a snapshot of https://docs.google.com/presentation/d/…/edit (Google Slides), downloaded 8 Oct. Slide 2 in Slides: …/edit#slide=id.ge63a4b4_1_9."
- Duo's teaching text (`cli-teaching.md`) says Claude can't open the link itself. It can tell the user where the file came from and ask for a newer download (`duo2 file latest`).
- New verbs (DL-71) [P]:

| Verb | Does | UI |
|---|---|---|
| `duo2 file source <path> [--set <url> \| --clear \| --open]` | show, set or clear the link; `--open` opens it in the default browser | the bar's link, Set Source…, Remove Source |
| `duo2 file newer [<path>]` | lists newer downloads of one file, or of every .pptx and .docx in the project; works without a source | the bar's "A newer download" |
| `duo2 file latest <path>` | opens the export link in the default browser and watches for the download | Get Latest |
| `duo2 file compare <path> [<newer>]` | opens the compare, with the newest matching download by default | Compare |
| `duo2 file replace <path> <newer> [--keep-old]` | replaces, sending the old copy to the Trash (or keeping a dated copy) | Replace |
| `duo2 file snapshots <path>` | lists the dates in the sidecar | the source popover's history |

## 8. Risks and open questions

- **C-70:** WhereFroms is fragile (§3), so a file that reaches the project through git, a zip, Claude's `curl` or an app's Save As arrives with no link. Set Source… is the fallback. The arrival rule must read the attribute before anything rewrites the file.
- **Q-154:** answered by DL-163: one `_sources.md` per folder.
- **Q-155:** does Spotlight return a ~/Downloads item to Duo without the privacy prompt, and does an Open-panel pick read without one? Testing either changes Duo's privacy grants, which belong to the shared bundle id (com.dudgeon.duo), so it needs Geoff's OK, or a test bundle id (ENH-25).
- **Q-156:** answered by DL-163: the Trash, with Undo.
- **Q-157:** answered by DL-163: offered in the bar in one click; nothing is written until then.
- **Untested [U]:** Safari, Firefox, Edge and Arc on this Mac; Pages, Keynote and Office round trips; iCloud Drive; Sheets (`docs.google.com/spreadsheets/d/<ID>/export?format=xlsx` is the same pattern, but there's no xlsx viewer yet); multi-account `…/u/1/…` links (the canonical link opens in the browser's current account, which may be the wrong one).

## Sources

- Experiments: this session, macOS 27.0 (26A428), Chrome 155.0.8059.40, public samples above. The download and inspection scripts are in the session scratchpad and aren't kept.
- python-pptx, core properties analysis (quotes the OPC schema): https://python-pptx.readthedocs.io/en/stable/dev/analysis/pkg-coreprops.html
- Microsoft, document properties (XPS / OPC): https://learn.microsoft.com/en-us/previous-versions/windows/desktop/dd372040(v=vs.85)
- Microsoft, `HyperlinkBase` (ISO/IEC 29500-1 §22.2.2.21): https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.extendedproperties.hyperlinkbase
- Microsoft, `CustomDocumentProperty`: https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.customproperties.customdocumentproperty
- Chromium, `quarantine_mac.mm`: https://chromium.googlesource.com/chromium/src/+/HEAD/components/services/quarantine/quarantine_mac.mm
- Firefox, `DownloadPlatform.cpp`: https://github.com/mozilla/gecko-dev/blob/master/toolkit/components/downloads/DownloadPlatform.cpp
- `copyfile(3)`: https://www.manpagez.com/man/3/copyfile/
- Ask LibreOffice, custom properties cleared: https://ask.libreoffice.org/t/libre-office-writer-is-clearing-my-custom-properties/56628
- Eclectic Light, AirDrop and quarantine: https://eclecticlight.co/2019/10/24/airdrop-and-quarantine-flags/
- Obsidian Web Clipper templates: https://obsidian.md/help/web-clipper/templates
