# Shelf scan v2: PRD

Sam · Oct 13, 2026 · for the team review on Thu Oct 15

## Problem
Shelf scan reads about four spines in five correctly, and v1 adds every spine it reads to the catalog. So one book in five on a scanned shelf is wrong. Neighbours walk to a box for a book that isn't there, and stewards stop trusting the scan.

## Goals
1. **Fewer than 3% wrong books** in the catalog (19% today).
2. 80% of scans end with a saved shelf (64% today).
3. A steward reviews a 14-book shelf in under 20 seconds.

## What we heard
Three of eight testers (P3, P6, P8) stopped scanning after a wrong book was added for them.
Glare from glass-door boxes caused 27% of wrong reads. Gerald (P2) and Denise (P3) both report it; Denise's Persuasion went into her box's catalog as “Pervasive Games: A Handbook”.
With a [review step](../prototype/scan-review.html) in the prototype, testers fixed every miss: 97% of books right, median 18 s a shelf.
Owen (P8) stopped after two wrong books in two scans; he'd scan again if the app showed him the list first.

## Requirements
After a scan, show every spine found on the photo, and flag the ones the model is unsure of.
Fixing a flagged book takes one tap: pick from the top three matches, or type the title.
Nothing is added to the catalog until the steward taps "Add".
Warn about glare before the photo is taken, and suggest opening the door.

## Non-goals
1. A new spine-recognition model; Ravi's model work runs separately.
2. Scanning by neighbours who aren't the box's steward.

## Open questions
Q1. Auto-add: keep it for stewards whose scans are 95%+ accurate, or remove it until the model reaches 95%?
Q2. Do we keep v1's wrong books, or ask stewards to re-scan?
- Do stewards want the glare warning before every scan, or only at glass-door boxes?
