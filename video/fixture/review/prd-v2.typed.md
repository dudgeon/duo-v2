---
suggest-edits: true
---

# Shelf scan v2: PRD

Sam · Oct 13, 2026 · for the team review on Thu Oct 15

## Problem
Shelf scan reads about four spines in five correctly, and v1 adds every spine it reads to the catalog. So one book in five on a scanned shelf is wrong. Neighbours walk to a box for a book that isn't there, and stewards stop trusting the scan.

## Goals
1. Fewer than 3% wrong books in the catalog (19% today).
2. {~~80% of scans~>85% of scans~~}{>>@sam 2026-10-13 #s3<<} end with a saved shelf (64% today).
3. A steward reviews a 14-book shelf in under {~~20~>15~~}{>>@jo 2026-10-12 #s1: Lena's prototype did 18 s, so 15 is the stretch.<<} seconds.

## What we heard
Three of eight testers (P3, P6, P8) stopped scanning after a wrong book was added for them.
Glare from glass-door boxes caused 27% of wrong reads; Denise (P3) can't scan her box at all after 4pm.
With a review step in the prototype, testers fixed every miss{++ in their first two scans++}{>>@ravi 2026-10-12 #s2<<}: 97% of books right, median 18 s a shelf.

## Requirements
After a scan, show every spine found on the photo, and {==flag the ones the model is unsure of==}{>>@ravi 2026-10-12 #c2: Unsure means confidence under 0.6 on the eval set.<<}.
{==Fixing a flagged book takes one tap==}{>>@sam 2026-10-13 #c3: Lena, can you mock the one-tap fix for Thursday?<<}: pick from the top three matches, or type the title.
Nothing is added to the catalog until the steward taps "Add".
{==Before the photo, warn when glare covers more than a tenth of the frame, and suggest opening the door.==}{>>@sam 2026-10-13 #c4: @claude can you make this one testable? Denise's feedback is in research/feedback.<<}{>>@claude 2026-10-13 #c4.1: Made it testable: a tenth of the frame is about where Denise's 4pm photos stop reading. Ravi's glare cases can check it.<<}

## Non-goals
1. A new spine-recognition model; Ravi's model work runs separately.
2. Scanning by neighbours who aren't the box's steward.

## Open questions
Q1. Auto-add: keep it for stewards whose scans are 95%+ accurate, or remove it until the model reaches 95%?
Q2. Do we keep v1's wrong books, or ask stewards to re-scan?
