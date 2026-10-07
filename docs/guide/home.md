# Home: your projects, and a chief of staff

**Home is one folder you choose, where the projects you're working on live. Its own Claude session is your chief of staff: tell it what's on your mind first, and it answers or hands the work to the right project.**

> **Not your Mac's home folder.** Duo's Home isn't the house-icon folder named after you. Make a new folder for it, like `claude-home`. Claude can read everything inside Home, and your Mac's home folder holds your Desktop, Documents and Downloads.

## The problem

Work arrives from everywhere: a Slack ask, a meeting note, an email from Legal. There's no one place to drop it and decide where it goes. Your projects live in five different folders, so there's no one place to see them. And every new Claude session starts knowing nothing about you, so you explain your role and priorities again and again.

## In Duo

Pick one folder as Home (File › Choose Home Folder…). Three things follow:

- **Your projects, first.** Projects in Home lead the map, and folders inside Home group them into [topics](topics.md). Everything else is listed after, under the folders it sits in.
- **A chief of staff.** Home's own Claude session sits on the left whenever you're at All projects. Tell it what just came in. It can see all your projects and can use Duo's `duo2` command, so it can say where something belongs, start or pick up a session in that project, or just answer.
- **Context, once.** Claude reads a `CLAUDE.md` file in the folder it starts in and in every folder above it. Write who you are, what you're working on and how you like to work in a `CLAUDE.md` at the top of Home, and every session in every project inside Home starts out knowing it.

Home is optional. Without one, Duo still lists every session, grouped by folder.

![All projects: Home's session on the left; on the map, Home's tile and its projects come first.](images/all-projects.png)

*Home's session on the left. On the map, Home's ★ tile comes first, then a column per topic.*

## Good to know

- Home is any folder you choose. Make a new one rather than using your Mac's home folder.
- **Move into Home…** moves a project's folder into Home, sessions and all.
- Home's session belongs to Home itself; sessions in Home's projects belong to those projects.

## A starter `CLAUDE.md` for Home

Duo gives Home's session no special instructions, so what it does is up to you. Here's a starter to copy into a `CLAUDE.md` at the top of Home and edit. Because every session in Home's projects reads this file too, the chief-of-staff part says it's only for the session in Home itself.

```markdown
## About me
I'm a product manager. I own payments (checkout, refunds) and onboarding.
This quarter: ship the checkout redesign; land the Q4 plan.
I like short answers, with the decision first.

## When you're running in this folder itself (not inside one of its projects)
You're my chief of staff. When I tell you about something new:
- If it's quick, answer it.
- If it belongs to a project (the folders here, each with a PROJECT.md),
  say which. With my OK, start a session there:
  duo2 session new --project <name> --prompt "<the ask>"
- Keep inbox.md: one line per ask, and where it went.
When I ask what's waiting on me, run duo2 needs-you and summarise it.
```

## For power users

Home is marked by a `HOME.md` at its top, with the same fields as a `PROJECT.md` (`goal`, `next`). Home's session is an ordinary Claude session in that folder. `duo2 home set <folder>`, `duo2 project move-into-home <project>`; <kbd>⇧⌘H</kbd> goes to Home, ready to type.

Next: [Topics](topics.md)
