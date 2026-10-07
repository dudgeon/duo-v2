# The Duo v2 guide

> **Duo v2 is an early beta and an experiment.** Things will change and some will break. Tell us what you find: open an [issue](https://github.com/dudgeon/duo-v2/issues), or use Help › Report an Issue… in Duo.

Duo is a Mac app for working with Claude Code across many pieces of work at once. This guide explains it one idea at a time. Each page says what the idea is, the problem it answers, and what Duo does about it, with a picture. The files, `duo2` commands and shortcuts that power users want sit in a section at the end of each page; you can skip them.

## The ideas, in order

1. [Sessions](sessions.md): a session is one conversation with Claude. Duo finds every one on your Mac, and keeps it.
2. [Projects](projects.md): a project is something you're trying to finish, kept in its own folder.
3. [Tasks](tasks.md) (optional): a to-do note that collects the sessions working on it.
4. [Where a session belongs](where-a-session-belongs.md): the project around the folder it ran in, and how to move one.
5. [Home](home.md): one folder for the projects you're working on, with its own Claude session.
6. [Topics](topics.md): a folder in Home for an area you own, holding its projects.
7. [Documents](documents.md): what Claude makes opens beside the conversation.
8. [What needs you](what-needs-you.md): the states a session can be in, and where Duo shows them.
9. [Getting around](getting-around.md): All projects, inside a project, and search.
10. [Plain files, and Claude driving Duo](plain-files.md).

Using Legacy Duo today? Read [Coming from Legacy Duo](coming-from-legacy-duo.md).

## Your first launch

1. Install Duo (see the [README](../../README.md#install)) and open it. It lists every Claude Code session on this Mac, grouped by the folder it ran in. Nothing to set up.
2. Optional: pick a Home folder with File › Choose Home Folder…. Make a new folder for it rather than using your Mac's home folder; [Home](home.md) says why.
3. Make your first project with **+ New project**, or turn a folder you already use into one with **Make a Project**.

The first time, Duo also offers to install the `duo2` command so Claude can use Duo (see [Plain files](plain-files.md)), and, if it finds Legacy Duo's instructions in Claude's settings, offers to turn them off.

## Words used in this guide

- **Claude Code**: Anthropic's Claude, running on your Mac and working in a folder. Duo runs it for you; you don't need to use a terminal.
- **Terminal**: the text window Claude Code runs in. Duo shows it in the middle of the window, or as a [chat](sessions.md#chat-mode).
- **Markdown**: plain text with light marks for headings, lists and bold, saved as a `.md` file. Duo opens it as a document.
- **Folder path**: where a folder is on your Mac, written like `~/claude-home/payments`. `~` means your Mac's home folder.
