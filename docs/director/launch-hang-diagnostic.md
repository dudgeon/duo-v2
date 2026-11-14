# Duo 0.2.23 won't launch: a diagnostic for the user's own Claude

Paste everything below the line into Claude Code on the Mac that has the problem. The commands only read.
Claude sends back a short summary that leaves out file contents, project names and paths under the home folder,
so nothing private leaves the Mac. Relay the summary to Geoff.

---

Duo (a Mac app at /Applications/Duo.app) bounces in the Dock forever when opened from Finder or the Dock, but
opened from a terminal it starts (and later crashed). Please help diagnose it. Run only the read-only commands
below, don't change or delete anything, and don't paste file contents back. Answer each numbered item in a line or
two. Replace project names, file names and anything under the home folder with `…`.

1. Which command opened it from the terminal that time? (`open -a Duo`, `open /Applications/Duo.app`, or
   `/Applications/Duo.app/Contents/MacOS/Duo` run directly?) Ask me if you don't know. (It's a clue, not a fix:
   Duo has to open from /Applications.)
2. With Duo not open in any way, run `pgrep -lf Duo.app`. List each process (pid, and whether it's
   `Contents/MacOS/Duo` or a helper). Then run `ps -o pid,stat,lstart,etime,%cpu -p <pid>` for each. Is any Duo
   left over from before (started long ago, state `U`, `T` or `Z`, or 0% CPU)?
3. Now open Duo from the Dock and let it bounce for 20 s. Run `pgrep -lf Duo.app/Contents/MacOS/Duo` again: is
   there a new process, or only the old one? For the newest pid, run `sample <pid> 5 -file /tmp/duo-sample.txt`
   and give me the first ~40 lines of the main thread's stack (the block under `com.apple.main-thread`): function
   and library names only.
4. `ls ~/Library/Logs/DiagnosticReports/ | grep -i duo`: for the newest Duo report, give me the exception type,
   the termination reason, and the top 15 frames of the crashed thread (names only).
5. `ls -la ~/Library/Application\ Support/Duo/logs/`: is `hangs.jsonl` there, and how big and how new is it? If
   it has lines from today, give `version`, `ms`, `ongoing` and the first 15 entries of `samples[0]` of the last
   three lines (they are code addresses, not data).
6. The login shell, as Finder starts it: run
   `time env -i HOME=$HOME USER=$USER /bin/zsh -lc 'command -v claude' </dev/null`
   and say how long it took, and whether it printed a path (just say yes or no). Also run `command -v claude` and
   `claude --version`.
7. `system_profiler SPDisplaysDataType | grep -iE "resolution|looks like|main display"`, and the Mac model
   (`sysctl -n hw.model`) and the macOS version (`sw_vers -productVersion`).
8. `log show --last 15m --style compact --predicate 'process == "Duo" OR (eventMessage CONTAINS[c] "com.dudgeon.duo")' | tail -60`:
   summarise anything that mentions launch, quarantine, syspolicy, translocation, code signing, "denied", "not
   responding" or a crash. Leave out lines that carry project or file names.
9. `ls ~/Library/Saved\ Application\ State/ | grep -i duo`: is there a `com.dudgeon.duo.savedState` folder?
10. Is any security or device-management software running that checks new apps (for example CrowdStrike, Santa,
    Jamf Protect, Microsoft Defender)? `ls /Library/SystemExtensions/*/ 2>/dev/null | head` and
    `systemextensionsctl list | head -20` help.

Then try this and say what happens: quit every Duo (Force Quit in Activity Monitor for each process named Duo),
wait 5 s, and open Duo from /Applications by double-clicking it.
