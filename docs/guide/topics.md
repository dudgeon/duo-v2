# Topics: one folder per area you own

**A topic is a folder in Home for an area you own, like payments or growth: one per hat you wear. It never finishes; it holds the projects that do.**

## The problem

Fifteen projects in one list is a wall. And some of what you do never finishes: you'll own payments for years, while checkout and refunds come and go inside it.

## In Duo

Make a folder in [Home](home.md) for each area you own, and put its projects inside. Duo shows each one as a column on the map, labelled with the folder's name. There's nothing to set up: a folder that holds projects but isn't a project itself is a topic. Projects sitting directly in Home share the first, unlabelled column.

```
claude-home/                 ← Home
├── HOME.md
├── q4-plan/                 ← a project directly in Home: first column
├── payments/                ← a topic: its own column
│   ├── checkout/            ← a project
│   └── refunds/             ← a project
└── growth/                  ← a topic
    └── onboarding/          ← a project
```

*The map is your folders, drawn: Home first, a column per topic, a tile per project, then every other folder where you've used Claude.*

## Good to know

- Rename or reorganise topic folders in Finder; the map follows.
- Outside Home, folders are grouped by the folder they sit in, so `~/Desktop/board-deck` appears under `~/Desktop`.
- On a narrow window, topics pack into fewer columns.
- If you use PARA (Projects, Areas, Resources, Archives), topics are your areas, not what PARA calls topics, which are reference shelves.

## For power users

A project inside another project's folder appears beside it on the map, not under it; sessions still belong to the closest project. Duo looks up to four folders deep. Topic labels are the folder's real name, never recapitalised. `duo2 project new <name> --into <topic folder>`.

Next: [Documents](documents.md)
