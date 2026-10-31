---
type: deck-template
title: Northwind Labs
pptx: northwind.pptx
slide-size: 16:9
heading-font: Avenir Next
body-font: Inter
google-heading-font: Nunito Sans
footer: Northwind Labs · Internal
---

# Northwind Labs deck templates

Made from `northwind.pptx` (a synthetic sample). Every slide in a Northwind deck uses one of the templates below. Each template is a layout in `northwind.pptx`; its slots are that layout's placeholders.

Lines marked `# duo` are written by `duo2 deck template build` from the pptx and are checked against it. The rest (names, purpose, limits) is written by Claude or a person and can be edited freely.

## title

The opening slide: the deck's name and who it's from. Once per deck, first.

```yaml
layout: Title                          # duo
fingerprint: ctrTitle@0 subTitle@1     # duo
slots:
  title:    {idx: 0, kind: text, max: 60, lines: 2}
  subtitle: {idx: 1, kind: text, max: 80, lines: 1, default: true}
```

## section

A divider between parts of the deck. A short title, and optionally the part's number.

```yaml
layout: Section                        # duo
fingerprint: title@0 body@1            # duo
slots:
  title:  {idx: 0, kind: text, max: 40, lines: 1}
  number: {idx: 1, kind: text, max: 3}
```

## bullets

A heading and up to six points. Two levels at most. If the points don't fit, split the slide; never shorten the font.

```yaml
layout: Title + Bullets                # duo
fingerprint: title@0 body@1            # duo
slots:
  title: {idx: 0, kind: text, max: 60, lines: 1}
  body:  {idx: 1, kind: bullets, items: 6, levels: 2, max: 110, default: true}
```

## two-column

Two lists side by side: before and after, options, pros and cons.

```yaml
layout: Two Column                     # duo
fingerprint: title@0 body@1 body@2     # duo
slots:
  title: {idx: 0, kind: text, max: 60, lines: 1}
  left:  {idx: 1, kind: bullets, items: 5, levels: 1, max: 70}
  right: {idx: 2, kind: bullets, items: 5, levels: 1, max: 70}
```

## kpi

One number that matters, what it measures, and one line of context. Not for comparing numbers; use a table.

```yaml
layout: Big Number                     # duo
fingerprint: title@0 body@13 body@14 body@15   # duo
slots:
  title:   {idx: 0, kind: text, max: 40, lines: 1}
  value:   {idx: 13, kind: number, max: 7}
  label:   {idx: 14, kind: text, max: 45, lines: 1}
  context: {idx: 15, kind: text, max: 140, lines: 2, default: true}
```

## quote

Someone's words, and who said them.

```yaml
layout: Quote                          # duo
fingerprint: body@13 body@14           # duo
slots:
  quote: {idx: 13, kind: text, max: 200, lines: 4, default: true}
  who:   {idx: 14, kind: text, max: 60, lines: 1}
```

## image

One picture with a caption. The picture is cropped to fill its box (about 3:2).

```yaml
layout: Image + Caption                # duo
fingerprint: title@0 pic@1 body@2      # duo
slots:
  title:   {idx: 0, kind: text, max: 50, lines: 1}
  image:   {idx: 1, kind: image, aspect: 1.52}
  caption: {idx: 2, kind: text, max: 220, lines: 6, default: true}
```

## table

A small table: up to 6 rows and 5 columns, a header row first.

```yaml
layout: Table                          # duo
fingerprint: title@0 tbl@1             # duo
slots:
  title: {idx: 0, kind: text, max: 60, lines: 1}
  table: {idx: 1, kind: table, rows: 7, cols: 5, default: true}
```
