# When something fails (§11 in full)

A failure, a complaint from the user, or your second hand-fix of the same thing. Fixing the one case isn't enough, and neither is writing a memory: a fix for the last symptom doesn't touch the mechanism. The fix itself goes to a worker, as any work does (§4).

1. **Open a task first**, titled `Failure: <what happened>`, with the user's words in `## Request` and a `check_by`, before you touch anything else. It gets chased like any other work.
2. **Cause:** the mechanism, not the symptom. Not "switch this run to Auto" but "why did it start in Default?"
3. **Duty:** which one in SKILL.md's table it breached, or which is missing. A missing one matters most.
4. **Change:** the smallest change that stops it recurring: a check, a verb, a procedure. A rule alone counts only if no check could see the failure. In this project, a rule goes in its Director section, on the user's yes (§7).
5. **Eval:** a case that fails before the change and passes after. In a project with no harness, write it in the task note: the situation, and what a good director does.
6. **Tell the user, in the same turn, even while the change is only proposed:** what failed, the cause, which duty it breached (by name), the change, the eval case, and how you'd know if it came back. "Sorry, fixed" isn't that message. Write the same in the task note.

If the fix belongs in this skill or in Duo, and you can't change those from here, offer to file the case as an issue at https://github.com/dudgeon/duo-v2/issues, with private details removed, and only on the user's yes for that item (Never 2 and 3).

**None of this becomes a memory.** How a director should behave goes through these steps, and a standing rule the user states goes in a Director section by asking (§7). Claude's memory holds only what neither of those does, such as an address.
