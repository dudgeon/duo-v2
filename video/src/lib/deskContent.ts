import content from '../../fixture/docs/content.json';

// S1's desk text, from fixture/docs/content.json (owned by the demo-fixtures session; SCENARIO.md is
// the bible). `desk` holds what the drawn windows show; the defaults below are the old checkout world,
// used only until content.json carries a `desk` block.

export type TLine =
  | {k: 'box'; cwd: string} | {k: 'user'; text: string} | {k: 'tool'; name: string; arg: string}
  | {k: 'out'; text: string} | {k: 'diff'; n: number; sign: '+' | '-' | ' '; text: string} | {k: 'say'; text: string} | {k: 'gap'};

type Desk = {
  finder: {parent: string; folders: [string, string][]; hero: string};
  terms: {term1: TLine[]; term2: TLine[]};
  zsh: {user: string; host: string; lastLogin: string; wrongCd: string; rightCd: string};
  clock: string; prd: string; url: string;
};

const c = content as unknown as {project: string; folder: string; desk?: Partial<Desk>;
  markdown: {file: string}; prototype: {file: string; title: string}; deck: {file: string}; doc: {file: string}; terminals: {session: string; cwd: string}[]};

const DEFAULTS: Desk = {
  finder: {parent: 'payments', hero: 'checkout-redesign', folders: [['api-deprecations', 'Sep 29'], ['checkout-redesign', 'Today'], ['fraud-rules-review', 'Sep 22'], ['onboarding-v3', 'Oct 6'], ['pricing-experiment-q4', 'Oct 2'], ['refunds-api-spec', 'Yesterday'], ['vendor-review', 'Aug 30']]},
  terms: {
    term1: [
      {k: 'box', cwd: c.terminals[0].cwd},
      {k: 'user', text: 'tighten the goals in docs/prd-v2.md'},
      {k: 'tool', name: 'Update', arg: 'docs/prd-v2.md'},
      {k: 'out', text: 'Updated docs/prd-v2.md with 2 additions and 2 removals'},
      {k: 'diff', n: 8, sign: ' ', text: '## Goals'},
      {k: 'diff', n: 9, sign: ' ', text: 'Cut guest-checkout abandonment 15% by Q1.'},
      {k: 'diff', n: 10, sign: '-', text: 'Let a guest finish checkout in one screen on mobile.'},
      {k: 'diff', n: 10, sign: '+', text: 'Guest checkout fits one mobile screen.'},
      {k: 'diff', n: 11, sign: '-', text: 'Take the plan to exec review on Oct 14.'},
      {k: 'diff', n: 11, sign: '+', text: 'Present the plan at exec review, Oct 14.'},
    ],
    term2: [
      {k: 'user', text: 'add express pay above the email field in checkout.html'},
      {k: 'tool', name: 'Read', arg: 'checkout.html'},
      {k: 'out', text: 'Read 148 lines'},
      {k: 'tool', name: 'Update', arg: 'checkout.html'},
      {k: 'out', text: 'Updated checkout.html with 9 additions'},
      {k: 'diff', n: 61, sign: '+', text: '<div class="express">'},
      {k: 'diff', n: 62, sign: '+', text: '  <div class="btn-pay apple">Apple Pay</div>'},
      {k: 'diff', n: 63, sign: '+', text: '  <div class="btn-pay google">Google Pay</div>'},
      {k: 'diff', n: 64, sign: '+', text: '  <div class="btn-pay paypal">PayPal</div>'},
      {k: 'say', text: 'Express pay now sits above the email field.'},
    ],
  },
  zsh: {user: 'geoff', host: 'macbook', lastLogin: 'Tue Oct 14 09:38:12 on ttys004', wrongCd: 'cd ~/work/paymnts/chekout', rightCd: 'cd ~/work/payments/checkout-redesign'},
  clock: 'Tue 9:41',
  url: 'localhost:3000/checkout',
  prd: `# Checkout redesign: PRD v2

## Problem
Guests abandon checkout at the payment step far more often than signed-in customers. Interviews and funnel data point to too many fields and no way to reuse a card.

## Goals
Cut guest-checkout abandonment 15% by Q1.
Let a guest finish checkout in one screen on mobile.
Take the plan to exec review on Oct 14.

## What we heard
Two of six interviewees named saved cards as the reason they abandon guest checkout.
Four of six wanted to skip the shipping form when an address autofills.
Nobody asked for more payment methods.`,
};

export const desk: Desk = {...DEFAULTS, ...(c.desk ?? {}),
  finder: {...DEFAULTS.finder, ...(c.desk?.finder ?? {})}, terms: {...DEFAULTS.terms, ...(c.desk?.terms ?? {})}, zsh: {...DEFAULTS.zsh, ...(c.desk?.zsh ?? {})}};
const base = (p: string) => p.split('/').pop()!;
/** File names and the project, as the windows' title bars show them. */
export const files = {project: c.project, folder: c.folder, markdown: base(c.markdown.file), prototype: c.prototype.file, deck: base(c.deck.file), doc: base(c.doc.file)};
