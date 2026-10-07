// What Launch Services would open for Duo, without opening anything (F-198):
//
//   swift scripts/ls-resolve.swift [bundle id] [url]     defaults: com.dudgeon.duo, duo2://session/x
//
// Prints `id-default <path>`, one `id <path>` per app with the bundle id, `url-default <path>` and one
// `url <path>` per app that claims the URL's scheme. scripts/check-launch-services.sh reads it.
import AppKit

let args = CommandLine.arguments.dropFirst()
let id = args.first ?? "com.dudgeon.duo"
let link = URL(string: args.dropFirst().first ?? "duo2://session/x")!
let ws = NSWorkspace.shared
if let u = ws.urlForApplication(withBundleIdentifier: id) { print("id-default \(u.path)") }
for u in ws.urlsForApplications(withBundleIdentifier: id) { print("id \(u.path)") }
if let u = ws.urlForApplication(toOpen: link) { print("url-default \(u.path)") }
for u in ws.urlsForApplications(toOpen: link) { print("url \(u.path)") }
