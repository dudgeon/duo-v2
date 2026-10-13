import Darwin

// duo-exec <program> <argv0> [args…] (DL-185, F-302): becomes <program> in place, with macOS's
// "responsible process" disclaimed. A terminal's process is then responsible for itself, so a
// privacy prompt raised by a Claude session's tools names that program, not Duo, and Duo doesn't
// collect access it never uses. Same pid, terminal and environment: posix_spawn with SETEXEC
// replaces this image, as execve would. Darwin only, so it starts in a millisecond.

@_silgen_name("responsibility_spawnattrs_setdisclaim")
func responsibility_spawnattrs_setdisclaim(_ attr: UnsafeMutablePointer<posix_spawnattr_t?>, _ disclaim: Int32) -> Int32

let args = CommandLine.arguments
guard args.count > 2 else { fputs("usage: duo-exec <program> <argv0> [args…]\n", stderr); exit(64) }
var attr: posix_spawnattr_t?
posix_spawnattr_init(&attr)
posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETEXEC))
_ = responsibility_spawnattrs_setdisclaim(&attr, 1)
let argv = args.dropFirst(2).map { strdup($0) } + [nil]
var pid: pid_t = 0
let err = posix_spawn(&pid, args[1], nil, &attr, argv, environ)
// Only reached when the spawn failed: run it the plain way rather than not at all.
fputs("duo-exec: \(args[1]): \(String(cString: strerror(err))); starting it without the disclaimer\n", stderr)
execve(args[1], argv, environ)
fputs("duo-exec: \(args[1]): \(String(cString: strerror(errno)))\n", stderr)
exit(126)
