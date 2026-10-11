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
screens = {
"tighten-prd.ans": header("~/work/payments/checkout-redesign") + you("Tighten the goals in docs/prd-v2.md: one measurable goal first, and drop anything that is really a requirement.")
  + tool("Read", "docs/prd-v2.md", "Read 31 lines")
  + say("The goals mix an outcome with two requirements. I'll lead with the metric and move the", "rest into Requirements.")
  + tool("Update", "docs/prd-v2.md", f"Updated docs/prd-v2.md with 2 additions and 2 removals") + diff((" ", 9, "## Goals"), ("-", 10, "Cut guest-checkout abandonment 15% by Q1."), ("+", 10, "Cut guest-checkout abandonment 15% by Q1 (38% today; target 32%)."), (" ", 11, "Let a guest finish checkout in one screen on mobile."), ("-", 12, "Take the plan to exec review on Oct 14."), ("+", 12, "Exec review Oct 14: decision on one-page guest checkout."))
  + [""] + say("Done. Goal 1 now carries the baseline and the target; goal 3 names the decision we need.", "Want me to cross-check the numbers against the funnel export?") + footer(),
"prototype-express-pay.ans": header("~/work/payments/checkout-redesign/prototype") + you("Add an express-pay row above the email field in checkout.html: Apple Pay, Google Pay, PayPal.")
  + tool("Read", "checkout.html", "Read 214 lines")
  + say("Adding an `express` block above the form, with an \"or pay by card\" divider under it.")
  + tool("Update", "checkout.html", "Updated checkout.html with 14 additions") + diff((" ", 62, '<main class="checkout">'), ("+", 63, '  <section class="express" aria-label="Express checkout">'), ("+", 64, '    <button class="pay apple">Apple Pay</button>'), ("+", 65, '    <button class="pay google">Google Pay</button>'), ("+", 66, '    <button class="pay paypal">PayPal</button>'), ("+", 67, '  </section>'), ("+", 68, '  <p class="divider">or pay by card</p>'), (" ", 69, '  <form id="details">'))
  + [""] + tool("Bash", "open checkout.html", "(no content)")
  + say("The row sits above the fold at 390 px wide. The buttons are 48 px tall, so they stay tappable.") + footer(),
"synthesis.ans": header("~/work/payments/checkout-redesign/research") + you("Read the six interview notes and write the synthesis: themes, two quotes, recommendations.")
  + tool("Read", "interviews/p1.md … p6.md", "Read 6 files (412 lines)")
  + say("Five of six shoppers abandoned a checkout last month because it asked for an account.", "Three themes come up again and again:", "", "  1. Account creation feels like a trap (P2, P3, P5)", "  2. Card entry on mobile is the slowest step (P1, P2, P4)", "  3. Express pay builds trust when it is offered first (P4, P6)")
  + tool("Write", "docs/interview-synthesis.docx", "Wrote 38 lines")
  + say("Written. I kept two quotes, P2 and P5, and put the recommendation last: move account", "creation after purchase, lead with express pay, and remember cards for returning guests.") + footer(),
}
here = pathlib.Path(__file__).parent
for name, lines in screens.items():
    (here / name).write_text("\n".join(lines) + "\n")
