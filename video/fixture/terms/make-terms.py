#!/usr/bin/env python3
"""Writes the recorded Claude Code screens the S2 demo's terminal tabs show (ANSI text, sample data only)."""
import pathlib
E_ = "\x1b["
dim, bold, rst = E_ + "2m", E_ + "1m", E_ + "0m"
orange, green, red, grey = E_ + "38;5;173m", E_ + "32m", E_ + "31m", E_ + "90m"
def header(cwd):
    return [f"{orange} ▐▛███▜▌{rst}   {bold}Claude Code{rst} v2.1.291", f"{orange}▝▜█████▛▘{rst}  Opus 5.5 · Claude Max", f"{orange}  ▘▘ ▝▝{rst}    {cwd}", ""]
def you(t): return [f"{grey}❯{rst} {t}", ""]
def say(*lines): return [f"{orange}⏺{rst} {lines[0]}"] + ["  " + l for l in lines[1:]] + [""]
def tool(name, arg, *res): return [f"{orange}⏺{rst} {bold}{name}{rst}({arg})"] + [f"  {grey}⎿{rst}  {r}" for r in res] + [""]
def footer(): return ["", grey + "─" * 94 + rst, f"{grey}❯{rst} ", grey + "─" * 94 + rst, f"  {dim}⏵⏵ accept edits on (shift+tab to cycle){rst}"]
def diff(*rows):
    out = []
    for kind, n, t in rows:
        c = green if kind == "+" else red if kind == "-" else dim
        out.append(f"      {dim}{n:>3}{rst} {c}{kind} {t}{rst}")
    return out
SHELF = "~/work/little-shared-library/shelf-scan"
screens = {
"tighten-prd.ans": header(SHELF) + you("Tighten the goals in docs/prd-v2.md: make each one measurable.")
  + tool("Read", "docs/prd-v2.md", "Read 30 lines")
  + say("The goals mix an outcome with a requirement. I'll lead with the wrong-books metric and move", "\"fix a miss in one tap\" down to Requirements, where it already lives.")
  + tool("Update", "docs/prd-v2.md", "Updated docs/prd-v2.md with 5 additions and 3 removals") + diff(
      (" ", 8, "## Goals"),
      ("-", 9, "1. Fewer wrong books."), ("+", 9, "1. Fewer than 3% wrong books in the catalog (19% today)."),
      ("-", 10, "2. Every scanned spine lands in the catalog with no extra taps."), ("+", 10, "2. 80% of scans end with a saved shelf (64% today)."),
      ("-", 11, "3. Fixing a missed book takes one tap."), ("+", 11, "3. A steward reviews a 14-book shelf in under 20 seconds."))
  + [""] + say("Done. Goal 1 now carries the baseline and the target. The old goal 2 was the v1 auto-add promise,", "so I replaced it with the saved-shelf rate. Want me to check the 19% against Ravi's eval?") + footer(),
"prototype-scan-review.ans": header(SHELF + "/prototype") + you("In scan-review.html, give the spines the model is unsure of an amber outline and a Fix chip.")
  + tool("Read", "scan-review.html", "Read 238 lines")
  + say("Adding an `unsure` state to the spine boxes, with a small Fix chip on its top-right corner.")
  + tool("Update", "scan-review.html", "Updated scan-review.html with 5 additions") + diff(
      (" ", 81, "  .summary { padding: 12px 2px 6px; }"),
      ("+", 83, "  .summary h3 .need { color: var(--amber); }"),
      ("+", 86, "  .sec.warn { color: var(--amber); }"),
      ("+", 109, "  .rc.lowish { color: var(--amber); }"),
      ("+", 113, "  .flag .cover { width: 28px; height: 38px; }"),
      ("+", 160, "          <div class=\"sec warn\">Needs a look <small>2</small></div>"))
  + [""] + tool("Bash", "open scan-review.html", "(no content)")
  + say("The two unsure spines (Persuasion and Ninety Bridges) now have an amber outline and a Fix chip.", "The other 12 keep their green boxes, and the header still reads \"14 found \u00b7 2 need a look\".") + footer(),
"synthesis.ans": header(SHELF + "/research") + you("Read the eight interview notes and write the synthesis: themes, two quotes, recommendations.")
  + tool("Read", "interviews/p1.md \u2026 p8.md", "Read 8 files (185 lines)")
  + say("Three of eight testers (P3, P6, P8) stopped scanning after a wrong book was added for them.", "Four themes come up again and again:", "", "  1. A wrong book costs trust fast (P3, P6, P8)", "  2. Glare from glass doors makes scanning unreliable (P3, P2)", "  3. Testers want to check the list before it is saved (P1, P4, P7)", "  4. Fixing a miss must take one tap (P4, P5, P7)")
  + tool("Write", "../docs/beta-interview-synthesis.docx", "Wrote 46 lines")
  + say("Written. I kept two quotes, P3 Denise and P8 Owen, and put the recommendation last: show what", "the scan found and let the steward review it before anything is added.") + footer(),
}
here = pathlib.Path(__file__).parent
for name, lines in screens.items():
    (here / name).write_text("\n".join(lines) + "\n")
