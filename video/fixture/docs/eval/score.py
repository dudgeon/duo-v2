#!/usr/bin/env python3
"""Score eval/results.csv: accuracy, and the miss table by cause.

    python3 eval/score.py                 # all 1,240 photos
    python3 eval/score.py --cause glare   # only shelves that had at least one glare miss
"""
import argparse
import collections
import csv
import pathlib

ORDER = ["tilted", "glare", "thin", "stacked", "other"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", default=str(pathlib.Path(__file__).with_name("results.csv")))
    ap.add_argument("--cause", help="restrict to shelves with at least one miss of this cause")
    a = ap.parse_args()
    rows = list(csv.DictReader(open(a.csv, newline="")))
    if a.cause:
        # TODO(ravi): glass-door shelves should be a column, not inferred from the misses
        keep = {r["shelf_id"] for r in rows if r["cause"] == a.cause}
        rows = [r for r in rows if r["shelf_id"] in keep]
        print(f"subset: shelves with {a.cause} misses")
    shelves = {r["shelf_id"] for r in rows}
    right = sum(1 for r in rows if r["correct"] == "1")
    wrong = [r for r in rows if r["correct"] == "0"]
    print(f"{len(rows):,} photos, {len(shelves)} shelves")
    print(f"accuracy: {100 * right / len(rows):.1f}% ({right:,} / {len(rows):,})")
    print()
    print(f"misses: {len(wrong)}")
    by = collections.Counter(r["cause"] or "unlabelled" for r in wrong)
    print(f"{'cause':<10}{'count':>6}{'share':>8}")
    for c in sorted(by, key=lambda c: (ORDER.index(c) if c in ORDER else 99)):
        print(f"{c:<10}{by[c]:>6}{100 * by[c] / len(wrong):>7.0f}%")
    # TODO(ravi): per-neighbourhood breakdown; Elm Park looks better than Riverside


if __name__ == "__main__":
    main()
