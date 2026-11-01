import AppKit
import DuoControl
import DuoDeck
import Foundation
import SwiftUI

// Duo Decks P3b (P3-4): the New Deck… and Convert to Duo Deck… sheets (DL-297, DL-294), Duo's own sheets
// (SheetOverlay), never a system alert.

/// A template pack a deck can use, as the pickers list it (project's first, then Home's, then built in).
public struct DeckPackChoice: Identifiable, Hashable, Sendable {
    public var name: String
    /// "this project", "Home" or "built in".
    public var scope: String
    public var templates: [String]
    public var id: String { name }
    public var count: Int { templates.count }
    public var detail: String { "\(scope) · \(count) template\(count == 1 ? "" : "s")" }
}

@MainActor @Observable public final class NewDeckForm {
    public var name: String
    /// A folder of the project, with its trailing slash (`decks/`).
    public var folder = "decks/"
    public var folders: [String]
    public var pack: String
    public var packs: [DeckPackChoice]
    /// Start with one slide of each template instead of a title slide.
    public var startAll = false
    public var error: String?

    public init(name: String = "", folders: [String], packs: [DeckPackChoice]) {
        self.name = name; self.folders = folders; self.packs = packs; self.pack = packs.first?.name ?? ""
        if !folders.contains(folder), let f = folders.first { folder = f }
    }
    public var chosen: DeckPackChoice? { packs.first { $0.name == pack } }
    /// The deck's file, project-relative: `decks/autumn-trial.md`.
    public var path: String { folder + DeckSheets.slug(name) + ".md" }
}

@MainActor @Observable public final class ConvertDeckForm {
    /// The pptx, project-relative.
    public var pptx: String
    /// A pack's name, or "" for a new pack made from this deck.
    public var pack: String
    public var packs: [DeckPackChoice]
    public var into: String

    public init(pptx: String, packs: [DeckPackChoice]) {
        self.pptx = pptx; self.packs = packs; self.pack = packs.first?.name ?? ""
        let base = ((pptx as NSString).lastPathComponent as NSString).deletingPathExtension
        into = "decks/" + DeckSheets.slug(base) + ".md"
    }
    public var fileName: String { (pptx as NSString).lastPathComponent }
}

public enum DeckSheets {
    /// `Autumn trial` → `autumn-trial`.
    public static func slug(_ name: String) -> String {
        let s = name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        let collapsed = s.replacingOccurrences(of: "-+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return collapsed.isEmpty ? "deck" : collapsed
    }

    /// The packs a deck living in `dir` can use: the project's, then Home's, then Duo's built-in one.
    public static func packChoices(near dir: URL) -> [DeckPackChoice] {
        let dirs = Deck.packDirs(near: dir)
        let (project, _) = DirectorPlace.resolve(from: dir)
        let projectPath = project.standardizedFileURL.path
        let builtIn = (try? Deck.builtInPackDir())?.standardizedFileURL.path
        return Deck.packs(in: dirs).compactMap { name, md in
            guard let pack = try? Deck.loadPack(name, in: dirs) else { return nil }
            let p = md.standardizedFileURL.path
            let scope = p.hasPrefix(projectPath + "/") ? "this project" : (builtIn.map { p.hasPrefix($0) } ?? false) ? "built in" : "Home"
            return DeckPackChoice(name: name, scope: scope, templates: pack.templates.map(\.name))
        }
    }

    /// The deck's text for New Deck…: a title slide, or one slide of each template.
    public static func newDeckText(title: String, pack: Deck.Pack, startAll: Bool) throws -> String {
        var text = Deck.newDeckText(title: title, pack: pack)
        if startAll {
            let first = pack.template("title") ?? pack.templates.first
            for t in pack.templates where t.name != first?.name { text = try Deck.insertSlide(source: text, template: t, after: nil) }
        }
        return text
    }

    /// The request Convert with Claude pastes: the ask, then the `duo2 deck import` line.
    public static func convertRequest(pptx: String, pack: String, into: String) -> String {
        let fileName = (pptx as NSString).lastPathComponent
        let target = pack.isEmpty ? "a new pack made from this deck" : "the \(pack) pack"
        let flag = pack.isEmpty ? "--new-pack \"\(DeckSheets.slug(((fileName as NSString).deletingPathExtension)))\"" : "--pack \"\(pack)\""
        return "Convert \(fileName) to a Duo deck on \(target). Group the slides, propose which template each becomes, and ask me before merging look-alike layouts. The pptx isn't changed.\n"
            + "duo2 deck import \"\(pptx)\" \(flag) --out \"\(into)\""
    }
}

extension AppModel {
    /// File › New › New Deck… and Files' + menu.
    public func showNewDeck(name: String = "") {
        guard let folder = projectFolder else { return info("Open a project first: a deck lives in one.") }
        closeSearch()
        var folders = ["decks/"]
        for d in ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted() where !d.hasPrefix(".") && d != "decks" && d != "templates" {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: folder.appending(path: d).path, isDirectory: &isDir), isDir.boolValue { folders.append(d + "/") }
        }
        newDeckForm = NewDeckForm(name: name, folders: folders, packs: DeckSheets.packChoices(near: folder))
    }

    /// The sheet's Create: writes the deck (`duo2 deck new`'s file) and opens it in its split tab.
    @discardableResult
    public func commitNewDeck() -> String? {
        guard let f = newDeckForm, let folder = projectFolder else { return nil }
        let name = f.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { f.error = "Give the deck a name."; return f.error }
        let rel = f.path
        let url = folder.appending(path: rel)
        guard !FileManager.default.fileExists(atPath: url.path) else { f.error = "\(rel) already exists."; return f.error }
        do {
            let dirs = Deck.packDirs(near: url.deletingLastPathComponent())
            let pack = try Deck.loadPack(f.pack, in: dirs)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try DeckSheets.newDeckText(title: name, pack: pack, startAll: f.startAll).write(to: url, atomically: true, encoding: .utf8)
        } catch { f.error = "\(error)"; return f.error }
        newDeckForm = nil
        afterChange { [self] in
            openDocument(rel)
            openSplitView(rel)
        }
        return nil
    }

    /// Convert to Duo Deck… on a pptx (the viewer's bar, Files' right-click).
    public func showConvertDeck(_ path: String) {
        guard let folder = projectFolder else { return }
        closeSearch()
        convertDeckForm = ConvertDeckForm(pptx: path, packs: DeckSheets.packChoices(near: folder))
    }

    /// The sheet's Convert with Claude: the request and the import line, in Claude's prompt, no Return.
    public func commitConvertDeck() {
        guard let f = convertDeckForm else { return }
        convertDeckForm = nil
        sendDraft(DeckSheets.convertRequest(pptx: f.pptx, pack: f.pack, into: f.into))
    }

    /// Text into Claude's prompt without Return (as Send to Claude does): the session showing, else a new one.
    public func sendDraft(_ text: String) {
        if (try? sendTarget.get()) != nil, send(text) { return }
        sendToNewSession(text)
    }

    /// The names of the packs Add to Pack ⌄ offers (the project's and Home's; the built-in pack is read only).
    public func deckPackNames(near file: URL) -> [String] {
        DeckSheets.packChoices(near: file.deletingLastPathComponent()).filter { $0.scope != "built in" }.map(\.name)
    }

    /// Make Templates with Claude / Add to Pack: the request and the inventory line, in Claude's prompt.
    public func sendTemplatesRequest(file: URL, path: String, slides: [Int], pack: String?) {
        let name = file.lastPathComponent
        let list = slides.map(String.init).joined(separator: ",")
        let which = slides.count == 1 ? "slide \(list)" : "slides " + (slides.count == 2 ? slides.map(String.init).joined(separator: " and ") : list)
        let ask = pack.map { "add them to the pack \($0)." } ?? "make them templates in a pack."
        sendDraft("From \(name), \(which):\n\(ask)\nduo2 deck template inventory \"\(path)\" --slides \(list)")
    }
}

// MARK: The sheets

/// A pack's strip of template tiles (P3-4 1): 16:9 wireframes on `pane` with the template's name.
struct DeckPackStrip: View {
    let pack: DeckPackChoice?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array((pack?.templates ?? []).prefix(8).enumerated()), id: \.offset) { i, name in
                RoundedRectangle(cornerRadius: 2).fill(i == 1 ? DuoColor.text2.opacity(0.35) : DuoColor.pane)
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
                    .overlay(Text(name).font(.system(size: 6)).foregroundStyle(DuoColor.text2).lineLimit(1).padding(.horizontal, 2))
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .accessibilityLabel(name)
            }
        }
    }
}

/// A one-value dropdown in a sheet's row: 24 high, `rule` border, the value, a chevron.
struct DeckSheetPopup<Items: View>: View {
    let value: String
    var detail: String? = nil
    @ViewBuilder let items: () -> Items

    var body: some View {
        Menu { items() } label: {
            HStack(spacing: DuoSpace.gapGlyphToLabel) {
                Text(value).duoText(.body).lineLimit(1)
                Spacer(minLength: 8)
                if let detail { Text(detail).duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1) }
                Chevron(direction: .down)
            }
            .padding(.horizontal, DuoMetric.sheetFieldPaddingX)
            .frame(height: DuoMetric.sheetFieldHeight)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).fill(DuoColor.pane))
            .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
    }
}

/// New Deck… (P3-4 1): Name, Folder, Template pack with its thumbnails, Start with.
struct NewDeckSheet: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: NewDeckForm

    var body: some View {
        VStack(alignment: .leading, spacing: DuoMetric.sheetRowGap) {
            Text("New Deck").duoText(.bodyEmphasis)
            SheetRow("Name") {
                SheetField(text: form.name, focus: true, submit: { model.commitNewDeck() }, cancel: model.cancelSheet) { form.name = $0 }
            }
            SheetRow("Folder", center: true) {
                DeckSheetPopup(value: form.folder) {
                    ForEach(form.folders, id: \.self) { f in Button(f) { form.folder = f } }   // not an action: picks a field's value
                }
            }
            SheetRow("Template pack") {
                VStack(alignment: .leading, spacing: 6) {
                    DeckSheetPopup(value: form.pack, detail: form.chosen?.detail) {
                        ForEach(form.packs) { p in Button("\(p.name) · \(p.detail)") { form.pack = p.name } }   // not an action: picks a field's value
                    }
                    DeckPackStrip(pack: form.chosen)
                }
            }
            SheetRow("Start with", center: true) {
                HStack(spacing: 16) {
                    radio("A title slide", on: !form.startAll) { form.startAll = false }
                    radio("One slide of each template", on: form.startAll) { form.startAll = true }
                }
            }
            if let e = form.error { SheetRow("") { Text(e).duoText(.control).foregroundStyle(DuoColor.diffDelText) } }
            SheetButtons(confirm: "Create", topGap: 4, cancel: model.cancelSheet) { model.commitNewDeck() }   // action: deck new
        }
        .foregroundStyle(DuoColor.text)
        .padding(DuoMetric.sheetPadding)
        .frame(width: DuoMetric.sheetMoveWidth - 2 * DuoMetric.borderHairline, alignment: .leading)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: DuoMetric.radiusPopover, bottomTrailingRadius: DuoMetric.radiusPopover).fill(DuoColor.ground))
        .padding([.horizontal, .bottom], DuoMetric.borderHairline)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: DuoMetric.radiusPopover, bottomTrailingRadius: DuoMetric.radiusPopover).fill(DuoColor.rule))
        .compositingGroup()
        .duoPopoverShadow()
        .onExitCommand { model.cancelSheet() }
        .accessibilityLabel("New Deck")
    }

    private func radio(_ label: String, on: Bool, _ pick: @escaping () -> Void) -> some View {
        HStack(spacing: 5) {
            Circle().strokeBorder(DuoColor.text, lineWidth: DuoMetric.borderHairline).frame(width: 10, height: 10)
                .overlay(Circle().fill(DuoColor.text).frame(width: 5, height: 5).opacity(on ? 1 : 0))
            Text(label).duoText(.control)
        }
        .contentShape(Rectangle())
        .onActivate(pick)   // not an action: picks a field's value
    }
}

/// Convert to Duo Deck… (P3-4 2): Template pack (or a new pack from this deck) and Into.
struct ConvertDeckSheet: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: ConvertDeckForm

    var body: some View {
        VStack(alignment: .leading, spacing: DuoMetric.sheetRowGap) {
            Text("Convert \(form.fileName) to a Duo deck").duoText(.bodyEmphasis)
            Text("Claude groups the slides, proposes which template each becomes, and asks before merging look-alike layouts. The pptx isn’t changed.")
                .duoText(.control, lineHeight: DuoTextStyle.body.spec.lineHeight).foregroundStyle(DuoColor.text2).fixedSize(horizontal: false, vertical: true)
            SheetRow("Template pack", center: true) {
                DeckSheetPopup(value: form.pack.isEmpty ? "A new pack from this deck" : form.pack, detail: form.packs.first { $0.name == form.pack }?.scope) {
                    ForEach(form.packs) { p in Button("\(p.name) · \(p.detail)") { form.pack = p.name } }   // not an action: picks a field's value
                    Divider()
                    Button("A new pack from this deck") { form.pack = "" }   // not an action: picks a field's value
                }
            }
            SheetRow("") { Text("Also: another pack, or a new pack from this deck").duoText(.pill).foregroundStyle(DuoColor.text2) }
            SheetRow("Into", center: true) {
                SheetField(text: form.into, focus: false, submit: { model.commitConvertDeck() }, cancel: model.cancelSheet) { form.into = $0 }
            }
            SheetButtons(confirm: "Convert with Claude", topGap: 4, cancel: model.cancelSheet) { model.commitConvertDeck() }   // action: deck import
        }
        .foregroundStyle(DuoColor.text)
        .padding(DuoMetric.sheetPadding)
        .frame(width: DuoMetric.sheetMoveWidth - 2 * DuoMetric.borderHairline, alignment: .leading)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: DuoMetric.radiusPopover, bottomTrailingRadius: DuoMetric.radiusPopover).fill(DuoColor.ground))
        .padding([.horizontal, .bottom], DuoMetric.borderHairline)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: DuoMetric.radiusPopover, bottomTrailingRadius: DuoMetric.radiusPopover).fill(DuoColor.rule))
        .compositingGroup()
        .duoPopoverShadow()
        .onExitCommand { model.cancelSheet() }
        .accessibilityLabel("Convert to Duo Deck")
    }
}
