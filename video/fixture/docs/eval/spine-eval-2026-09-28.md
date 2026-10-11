# Spine eval, 2026-09-28

Ravi Menon. Model: spine-reader v1 (the one in the beta since Aug 24). Scrappy notes, not a report.

## Method

- 1,240 spine photos from 96 shelves (32 each in Elm Park, Northgate, Riverside). Photos came from the beta uploads, 12 to 16 per shelf.
- Labelled by hand: Tomás and I typed the title for each photo, blind to what the model said. Anything we couldn't read ourselves got dropped, so the set is slightly kind to the model.
- A read counts as correct only if the string matches the truth title exactly (case-insensitive). "Midd1emarch" is a miss even though a human would shrug. That is deliberate: the catalog match downstream is strict too.
- Each miss got one cause label from looking at the photo. One cause per photo, so shares add up. Borderline calls (tilted *and* thin) went to whichever looked worse.
- Scored with `eval/score.py` on `eval/results.csv`.

## Results

| | |
| --- | --- |
| Photos | 1,240 |
| Read correctly | 1,004 (81.0%) |
| Wrong | 236 |

Where the 236 misses come from:

| Cause | Misses | Share |
| --- | --- | --- |
| Tilted or leaning spines | 80 | 34% |
| Glare (glass or plastic doors) | 64 | 27% |
| Thin spines (under 1 cm) | 50 | 21% |
| Stacked or sideways books | 28 | 12% |
| Other (non-Latin titles, worn print) | 14 | 6% |

Confidence is not much help: wrong reads are spread from 0.35 to 0.86, and a few sit above 0.8. At the v1 auto-add setting that is how a wrong book gets in.

## Confusion examples

- *Persuasion* read as **Pervasion** (glare, Linden Street box). The catalog then matched "Pervasion" to *Pervasive Games: A Handbook*. This is the one Denise hit.
- *Ninety Bridges* read as **Ninety Brides** (thin spine). Two letters lost at the edge of the crop.
- *Middlemarch* read as **Midd1emarch** (worn print, the "l" looks like a 1).
- *Moby-Dick* read as **Mobv-Dick** (tilted).
- *Emma* read as **Erma** (short title, glare).

## Caveats

- The glare set is only 140 photos from 9 shelves, all glass or plastic doors. Needs more. Anything we say about glare is soft until we have more doors.
- Only 9 of 96 shelves have doors at all, but stewards of door boxes are the loudest in the interviews, so the beta mix may differ from this one.
- Labels are two people. No second pass for disagreement yet.
- The set is photos people chose to upload. Probably cleaner than what the camera sees in the field.

## Rerun

Reran on Oct 1 after fixing the crop-scale bug (it was off on a handful of shelves). Same 1,004 of 1,240, same table. Nothing to update.

## TODO

- [ ] Add 300+ photos from glass-door boxes, a few different times of day (glare moves).
- [ ] Add a `glass_door` column to `results.csv`, so `score.py --cause glare` stops guessing from the misses.
- [ ] Second labeller on the 236 misses.
- [ ] Per-neighbourhood numbers. Eyeballing says Riverside is worse.
- [ ] Try the polarising-filter trick Lena suggested for the door boxes. Probably a no for a phone app.

@Sam: the auto-add threshold is 95%. The v1 model is at 81%, so on these numbers auto-add shouldn't be on for anyone yet. If the review step gets users' fixed shelves to 97%, that is a different conversation. Your call for the PRD.
