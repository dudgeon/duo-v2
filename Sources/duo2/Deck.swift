import DuoControl
import DuoDeck
import Foundation

/// `duo2 deck …` (Duo Decks, DL-267 to DL-290): local verbs, so they run with Duo closed and inside
/// Claude's sandbox. They read and write files; none needs the app.
func runDeck(_ verb: String, _ argv: [String]) -> Int32 {
    func say(_ s: String) { print(s) }
    func err(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
    func usage(_ u: String) -> Int32 { err("usage: duo2 \(u)"); return 64 }

    var words: [String] = [], out: String?, after: Int?, template: String?
    var slidesArg: String?, pack: String?, newPack: String?, plan: String?
    var json = false, dryRun = false
    var i = 0
    while i < argv.count {
        switch argv[i] {
        case "--out": i += 1; out = argv.indices.contains(i) ? argv[i] : nil
        case "--after": i += 1; after = argv.indices.contains(i) ? Int(argv[i]) : nil
        case "--template": i += 1; template = argv.indices.contains(i) ? argv[i] : nil
        case "--slides": i += 1; slidesArg = argv.indices.contains(i) ? argv[i] : nil
        case "--pack": i += 1; pack = argv.indices.contains(i) ? argv[i] : nil
        case "--new-pack": i += 1; newPack = argv.indices.contains(i) ? argv[i] : nil
        case "--plan": i += 1; plan = argv.indices.contains(i) ? argv[i] : nil
        case "--json": json = true
        case "--dry-run": dryRun = true
        default: words.append(argv[i])
        }
        i += 1
    }
    func url(_ p: String) -> URL { URL(fileURLWithPath: p, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL }
    func dirs(for deck: URL) -> [URL] { Deck.packDirs(near: deck.deletingLastPathComponent()) }
    func read(_ u: URL) -> String? { try? String(contentsOf: u, encoding: .utf8) }
    /// A pack named by its .md, its folder, or its name (looked up from here).
    func packMD(_ arg: String) throws -> URL {
        let u = url(arg)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir) {
            if !isDir.boolValue, u.pathExtension == "md" { return u }
            let inner = u.appending(path: "\(u.lastPathComponent).md")
            if isDir.boolValue, FileManager.default.fileExists(atPath: inner.path) { return inner }
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if let f = Deck.packs(in: Deck.packDirs(near: cwd)).first(where: { $0.name == arg }) { return f.md }
        throw Deck.Failure(description: "no template pack \"\(arg)\": give its .md, its folder, or a name under templates/decks/")
    }

    do {
        switch verb {
        case "deck templates":
            if let d = words.first {
                let deck = url(d)
                guard let text = read(deck) else { err("duo2: can't read \(d)"); return 1 }
                let front = Deck.parse(text).front
                guard let name = front["template"], !name.isEmpty else { err("\(d):2: the frontmatter needs template: <pack>"); return 1 }
                say(Deck.catalogue(try Deck.loadPack(name, in: dirs(for: deck))))
            } else {
                let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                let found = Deck.packs(in: Deck.packDirs(near: cwd))
                for (n, (name, _)) in found.enumerated() {
                    if n > 0 { say("") }
                    say(Deck.catalogue(try Deck.loadPack(name, in: Deck.packDirs(near: cwd))))
                }
            }
            return 0

        case "deck check":
            guard let d = words.first else { return usage("deck check <deck>") }
            let deck = url(d)
            let checked = try Deck.check(deck: deck, packDirs: dirs(for: deck))
            say(Deck.report(d, checked.problems, notices: checked.notices))
            return checked.problems.isEmpty ? 0 : 1

        case "deck export":
            guard let d = words.first else { return usage("deck export <deck> [--out <dir>]") }
            let deck = url(d)
            let checked = try Deck.check(deck: deck, packDirs: dirs(for: deck))
            guard checked.problems.isEmpty else {
                err(Deck.report(d, checked.problems, notices: checked.notices))
                err("duo2: not exported: fix the problems above first")
                return 1
            }
            for n in checked.notices { err("\(d):\(n.line): notice: \(n.message)") }
            let e = try Deck.writeExport(deck: deck, packDirs: dirs(for: deck), dir: out.map(url))
            say("wrote \(e.url.path) (\(e.bytes) bytes)")
            for r in e.removed { say("removed the earlier export \(r.lastPathComponent)") }
            return 0

        case "deck insert":
            guard words.count >= 2 else { return usage("deck insert <deck> <template> [--after <n>]") }
            let deck = url(words[0])
            guard let text = read(deck) else { err("duo2: can't read \(words[0])"); return 1 }
            let parsed = Deck.parse(text)
            let pack = try Deck.loadPack(parsed.front["template"] ?? "", in: dirs(for: deck))
            guard let t = pack.template(words[1]) else {
                err("duo2: no template \"\(words[1])\" in \(pack.md.lastPathComponent); use one of \(pack.templates.map(\.name).joined(separator: ", "))")
                return 1
            }
            let new = try Deck.insertSlide(source: text, template: t, after: after)
            try new.write(to: deck, atomically: true, encoding: .utf8)
            say("added slide \((after ?? parsed.slides.count) + 1) (\(t.name)) to \(words[0]): fill in " + (t.slots.map(\.name).joined(separator: ", ")))
            return 0

        case "deck new":
            guard let p = words.first, let tpl = template else { return usage("deck new <path> --template <pack>") }
            let path = url(p)
            guard !FileManager.default.fileExists(atPath: path.path) else { err("duo2: \(p) already exists"); return 1 }
            let pack = try Deck.loadPack(tpl, in: dirs(for: path))
            var title = path.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
            title = title.prefix(1).uppercased() + title.dropFirst()
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Deck.newDeckText(title: title, pack: pack).write(to: path, atomically: true, encoding: .utf8)
            say("made \(p) on the \(pack.name) pack (\(pack.templates.count) templates). See them with: duo2 deck templates \(p)")
            return 0

        case "deck change":
            guard words.count >= 3, let n = Int(words[1]) else { return usage("deck change <deck> <n> <template>") }
            let deck = url(words[0])
            guard let text = read(deck) else { err("duo2: can't read \(words[0])"); return 1 }
            let pack = try Deck.loadPack(Deck.parse(text).front["template"] ?? "", in: dirs(for: deck))
            let c = try Deck.changeTemplate(source: text, slide: n, to: words[2], pack: pack)
            try c.text.write(to: deck, atomically: true, encoding: .utf8)
            say("slide \(n) is now \(words[2])")
            for m in c.remap.moves where m.from != m.to { say("  moved \(m.from) -> \(m.to)") }
            if !c.remap.unplaced.isEmpty {
                say("  moved to the speaker notes (\"Not placed after changing to \(words[2])\"): " + c.remap.unplaced.joined(separator: ", "))
            }
            let empty = c.remap.slots.filter { $0.name != "title" && $0.raw.isEmpty && $0.lines.isEmpty }.map(\.name)
            if !empty.isEmpty { say("  empty now: " + empty.joined(separator: ", ")) }
            return 0

        case "deck template inventory":
            guard let p = words.first else { return usage("deck template inventory <pptx> [--slides 3,7] [--json]") }
            guard FileManager.default.fileExists(atPath: url(p).path) else { err("duo2: can't read \(p)"); return 1 }
            let r = try TemplateInventory.read(url(p), slides: try slidesArg.map(TemplateInventory.parseSlides))
            say(json ? try TemplateInventory.json(r) : TemplateInventory.render(r))
            return 0

        case "deck template build":
            guard let p = words.first else { return usage("deck template build <pack>") }
            let md = try packMD(p)
            let r = try Deck.buildPack(md: md)
            let shown = md.lastPathComponent
            for pr in r.problems { err("\(shown):\(pr.line): \(pr.message)") }
            if !r.problems.isEmpty { err("duo2: not built: fix the problems above and run it again"); return 1 }
            say("built \(r.pptx.path) (\(r.bytes / 1024) KB)")
            for n in r.notes { say("  \(n)") }
            if r.definitionChanged { say("updated \(md.path): the # duo lines (layout, fingerprint, idx)") }
            for pr in r.fitProblems { say("\(shown):\(pr.line): \(pr.message)") }
            if !r.fitProblems.isEmpty { say("\(r.fitProblems.count) limit\(r.fitProblems.count == 1 ? "" : "s") too high: set max to the largest that fits, then build again") }
            return r.fitProblems.isEmpty ? 0 : 1

        case "deck template specimen":
            guard let p = words.first else { return usage("deck template specimen <pack> [--out <deck.md>]") }
            let md = try packMD(p)
            let r = try Deck.writeSpecimen(md: md, out: out.map(url))
            say("wrote \(r.deck.path)")
            say("wrote \(r.export.url.path) (\(r.export.bytes) bytes)")
            for x in r.export.removed { say("removed the earlier export \(x.lastPathComponent)") }
            for pr in r.fit { say("\(r.deck.lastPathComponent):\(pr.line): \(pr.message)") }
            if !r.fit.isEmpty { say("\(r.fit.count) slot\(r.fit.count == 1 ? "" : "s") overflow in the specimen: lower the limit named, then build and run specimen again") }
            return 0

        case "deck import":
            guard let p = words.first else { return usage("deck import <pptx> [--pack <p> | --new-pack <name>] [--plan <file>] [--out <deck.md>]") }
            let pptx = url(p)
            guard FileManager.default.fileExists(atPath: pptx.path) else { err("duo2: can't read \(p)"); return 1 }
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            guard let planPath = plan else {
                var pk: Deck.Pack?
                if let name = pack { pk = try Deck.loadPack(name, in: Deck.packDirs(near: cwd)) }
                let s = try DeckImportPlan.survey(pptx, pack: pk)
                say(json ? try DeckImportPlan.json(s) : DeckImportPlan.render(s))
                return 0
            }
            guard let planText = read(url(planPath)) else { err("duo2: can't read the plan \(planPath)"); return 1 }
            let o = try Deck.importDeck(pptx: pptx, plan: try DeckImportPlan.parse(planText), pack: pack, newPack: newPack, out: out.map(url), cwd: cwd)
            say("wrote \(o.deck.path)")
            say(o.report)
            return o.problems.isEmpty ? 0 : 1

        case "deck migrate":
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let root = DirectorPlace.resolve(from: cwd).project
            let ms = Deck.migrations(root: root, packDirs: Deck.packDirs(near: cwd), pack: pack)
            if ms.isEmpty { say("no deck in \(root.path) uses a slot name its pack has renamed"); return 0 }
            var n = 0
            for m in ms {
                let rel = m.deck.path.hasPrefix(root.path + "/") ? String(m.deck.path.dropFirst(root.path.count + 1)) : m.deck.path
                say(Deck.unifiedDiff(path: rel, old: m.before, new: m.after))
                n += m.changes.count
                if !dryRun { try m.after.write(to: m.deck, atomically: true, encoding: .utf8) }
            }
            say(dryRun ? "\(n) slot heading\(n == 1 ? "" : "s") would be renamed in \(ms.count) deck\(ms.count == 1 ? "" : "s") (dry run: nothing written)"
                       : "renamed \(n) slot heading\(n == 1 ? "" : "s") in \(ms.count) deck\(ms.count == 1 ? "" : "s")")
            return 0

        case "deck render":
            err("duo2: deck render isn't built yet: it needs Duo's viewer (WebKit). Export with `duo2 deck export` and open the pptx in Duo meanwhile.")
            return 2

        default:
            err("duo2: unknown deck verb \(verb)")
            return 64
        }
    } catch {
        err("duo2: " + ((error as? Deck.Failure)?.description ?? error.localizedDescription))
        return 1
    }
}
