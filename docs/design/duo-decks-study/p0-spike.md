# Duo Decks P0 spike: a Swift pptx writer

Question: can Duo's own Swift code turn the sample deck and the Northwind pack into a correct pptx, deterministically (DL-267, DL-268, DL-270; plan §3.1, §3.2, §6 P0)? **Yes.** No Python, no Node, no LibreOffice at export time.

## What was built

All in `Sources/DuoSearch/Deck/` (DuoSearch, so it runs with Duo closed and in Claude's sandbox), plus one check.

| File | Lines | Job |
|---|---|---|
| `ZipWriter.swift` | 76 | Zip writer: deflate (Compression ZLIB = raw DEFLATE) or stored, CRC-32 by table, DOS time fixed at 1980-01-01 00:00, no clock reads |
| `DeckParse.swift` | 247 | Deck parser (DL-267), anchor map, Review-mark stripping, pack loader with the small YAML subset (flow maps, ` #` comments) |
| `DeckCheck.swift` | 113 | Checker with the prototype's messages: `file:line: slide n (template), slot: message + fix` |
| `PptxWriter.swift` | 320 | The writer |
| `DeckInspect.swift` | 60 | Reads an exported pptx back (layout, placeholders by type and idx, notes, custom properties) for checks |
| `Sources/DuoChecks/DeckChecks.swift` | ~120 | The check: `DUO_CHECKS=deck swift run DuoChecks` (also in the full run). `DUO_DECK_OUT=<file>` keeps the export |

Writer behaviour: opens the pack's pptx with `Pptx.Zip`, copies every part in original order, adds one slide per deck slide on the layout the template names (found by `cSld name`), fills placeholders by idx with `<p:spPr/>` (no box), clones the layout's footer (text from the deck's `footer:`) and slide number as boxless placeholders, writes bullets with `a:pPr lvl`, `**bold**` runs, a table in a `graphicFrame` carrying the table placeholder, a picture as `p:pic` on the picture placeholder with a `srcRect` crop-to-fill from the placeholder aspect, notes as a notes slide, and a notes master (plus a copy of the theme) because the pack has none. Updates `sldIdLst`, `notesMasterIdLst`, the rels and `[Content_Types].xml`, sets `dc:title`, and stores `duoSourceSha` (sha-256 of the deck `.md`) in `docProps/custom.xml`. Colours come only from the layouts (scheme colours); the writer emits none.

Review marks (the lead's addition): `Review.parse` from DuoControl is reused (DuoSearch already depends on DuoControl, no cycle). Comments and highlight markers are stripped before parsing, newlines inside a mark kept so lines don't move. The anchor map holds each top-level mark (kind, line, lastLine, text) on its slot, or on the slide when it sits on the line after the marker or outside every slot.

## What passed

`DUO_CHECKS=deck`: **39 passed, 0 failed** (built and run under the shared GPU lock).
- 9 slides, each on its layout; placeholders by idx and none with its own box; footer text and slide number on all; kpi fills idx 0, 13, 14, 15, then 11, 12.
- Notes on slides 2 and 9 only; picture on slide 5 in placeholder 1; table 5x3 on slide 6 at the table placeholder; bullet levels; `duoSourceSha` equals the deck's sha-256.
- Checker: the sample is clean; a broken copy (7 bullets, 10-character value, unknown template `comparison`) gives exactly the three messages in `samples/pr/check-output.txt`, and export refuses it.
- Review fixture (slide comment, slot comment, highlight, substitution, pending insertion and deletion): export text has no marks and anchor lines are right (9, 12, 18).
- python-pptx opens the file: 9 slides, layout names, placeholder idx and types, footers, slide numbers, notes all as expected.
- LibreOffice renders all 9 slides.

## Determinism

Two exports in one run are byte-identical, and two separate processes give the same file:
`shasum -a 256 field-trial-review.swift.pptx` = `b1abdca13eb48997ab9d4177e61971f1c0c79d29ba4b6588b4d3e5d419af4b0a` (both runs).

Size and time: 44,047 bytes (the pack is 24,781; 61 parts, 121,890 bytes uncompressed). Export about 10 ms (parse, check, write; debug build).

## Against the Python prototype

Compared side by side at `img/p0-spike/compare-swift-left-python-right.png` (left Swift, right python-pptx, same LibreOffice render). All nine slides look the same: title, bullets with the second level, kpi, two columns, the cropped picture, quote, section, asks, footers and numbers. Differences:
- Empty placeholders: python-pptx leaves every unfilled layout placeholder on the slide ("Click to add text" in an editor); the Swift writer emits only filled ones. Not visible in renders. Open question whether an editor should see the empty ones.
- Table: the frame needs an explicit `xfrm` (schema), so it is copied from the layout; rows are 0.4 in (370,840 EMU) as python-pptx draws them. First attempt used the whole placeholder height and the rows were tall (`img/p0-spike/swift-slide-06.png` is the fixed render).
- Core properties: `lastModifiedBy` still says "Steve Canny" and `app.xml` says 0 slides, inherited from the pack; the pack's `sldSz type="screen4x3"` is wrong for 16:9 dimensions (renders fine). The pack's thumbnail is also kept. A pack builder should clean these.
- The slide-number field text is `‹#›`; renderers draw the number.

## What was not done

- Not opened in Duo's own pptx viewer (optional; no visible runs).
- Not uploaded to Google Slides (not part of P0).
- No `duo2 deck` verbs yet; the writer is an API plus the check.
- Table style is the built-in medium style 2 id; the pack's `tableStyles.xml` defines none, so fidelity depends on the app knowing it (LibreOffice and python-pptx's output agree).
- Charts, SmartArt, autofit, JPEG images only lightly exercised (PNG tested; JPEG size reader untested).
- Multi-paragraph text slots are joined into one paragraph, as the prototype does.

## Open problems and questions

1. **Pending suggestions export as the text before the change** (lead's choice): `{++x++}` as nothing, `{--x--}` as x, `{~~a~>b~~}` as a, `{==t==}` as t, comments dropped. Is that right, or should export refuse a deck with open suggestions, or take the new text? Needs Geoff.
2. A mark that spans two slots (a highlight across a blank line, a multi-paragraph comment) lands on the slide, not a slot.
3. A comment on its own line between slots, after a slot's last line, is the slide's; before it, the slot's heading line range.
4. Placeholders the deck leaves out are omitted (above). Required-slot rules belong in the checker, not the writer.
5. Google round trip is untouched: footers and slide numbers are boxless placeholders, which Google flattens (research §5).
