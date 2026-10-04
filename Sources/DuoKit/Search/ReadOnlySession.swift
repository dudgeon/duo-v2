import DuoSearch
import SwiftUI

/// A session opened read-only from search, at its matched turn (search-handoff §4,
/// `search-open-session`): a right-pane tab with a `read-only` pill and a Resume button.
public struct ReadOnlySession: Equatable, Sendable {
    public static let tabKey = "search:read-only"
    public var item: SearchItem
    public var turns: [SearchItem.Turn]

    init(item: SearchItem) {
        self.item = item
        let matched = Int(item.location.split(separator: " ").last ?? "") ?? 0
        if let path = item.path, FileManager.default.fileExists(atPath: path) {
            turns = SessionSource.read(path).turns.map { t in
                let parts = t.text.components(separatedBy: "\n\nClaude: ")
                let you = parts.first.map { $0.hasPrefix("You: ") ? String($0.dropFirst(5)) : $0 }
                return .init(number: t.index, you: you, claude: parts.count > 1 ? parts[1] : nil, matched: t.index == matched)
            }
        } else {
            turns = item.turns
        }
    }

    var title: String { item.title + (item.location.isEmpty ? "" : " · \(item.location)") }
}

struct ReadOnlySessionView: View {
    @Environment(AppModel.self) private var model
    let session: ReadOnlySession

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        SearchIcon(kind: .session).frame(width: 12, height: 12)
                        Text(session.item.title).duoText(.title).foregroundStyle(DuoColor.text).lineLimit(1)
                        Pill(text: "read-only")
                        Spacer(minLength: 8)
                        Button("Resume") { model.goTo(session.item) }.buttonStyle(.duo)
                    }
                    ForEach(session.turns, id: \.number) { t in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                SectionLabel(text: "Turn \(t.number)")
                                Spacer(minLength: 8)
                                if t.matched { Text("from search").duoText(.body).foregroundStyle(DuoColor.text2) }
                            }
                            if let y = t.you { TurnLine(who: "You", text: y, words: session.item.matchedWords) }
                            if let c = t.claude { TurnLine(who: "Claude", text: c, words: session.item.matchedWords) }
                        }
                        .padding(t.matched ? DuoMetric.searchPreviewBlockPadding : EdgeInsets())
                        .overlay(RoundedRectangle(cornerRadius: DuoMetric.searchPreviewBlockRadius)
                            .strokeBorder(t.matched ? DuoColor.text : .clear, lineWidth: 1.5))
                        .padding(.horizontal, t.matched ? -12 : 0)
                        .id(t.number)
                    }
                }
                .padding(EdgeInsets(top: 16, leading: 32, bottom: 24, trailing: 32))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear { if let m = session.turns.first(where: \.matched) { proxy.scrollTo(m.number, anchor: .center) } }
        }
    }
}

/// Where a file result landed in the fixture's placeholder document (search-open-file).
public struct SearchLanding: Equatable, Sendable {
    public var section: String
    public var label: String
}
