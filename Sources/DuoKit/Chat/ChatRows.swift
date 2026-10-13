import SwiftUI

// The lazy feed's rows (C-85, ENH-23a). A lazy row that is a whole Claude turn of a long agent
// session holds hundreds of steps: on screen, changing or building it cost 0.3–0.8 s. So a long
// turn is several rows, pieces of a fixed number of card sections, drawn on pieces of the card
// that meet edge to edge. A short turn stays one row. Each turn's rows are kept until the turn
// changes, so an event rebuilds only the turn it touched (F-160's prototype rebuilt every row).

struct ChatFeedRow: Identifiable, Equatable {
    enum Kind: Equatable {
        /// Drawn as it always was.
        case item(ChatItem)
        /// A piece of a long Claude turn; `Claude · 9:42` over the first. `first` and `last` say which corners round.
        case piece(time: Date?, sections: [[ChatCardRow]], lastAsked: String?, first: Bool, last: Bool)
    }

    let id: String
    let kind: Kind
    /// The space above it: 16 between items, none between pieces of a turn.
    let gap: CGFloat
}

enum ChatFeedRows {
    /// Card sections per piece. Measured on the heavy session with the window drawn every frame
    /// (C-85): 4, 8 and 16 all removed the stalls; 8 keeps the row count near the item count.
    static let size = Int(ProcessInfo.processInfo.environment["DUO_FEED_PIECE"] ?? "") ?? 8

    /// For measuring and proving only, from `DUO_FEED`: `whole` draws the lazy feed's turns whole,
    /// as before C-85, to measure against; `proof` draws the plain feed in pieces too, so the chat
    /// boards show the pieces look exactly like whole cards. Unset in use.
    enum Mode { case pieces, whole, proof }
    static let mode: Mode = switch ProcessInfo.processInfo.environment["DUO_FEED"] {
    case "whole": .whole
    case "proof": .proof
    default: .pieces
    }

    /// A turn's rows, kept while its segments, its place and whether a question card is up are the same.
    struct Kept { var segments: [ChatSegment]; var gap: CGFloat; var asking: Bool; var rows: [ChatFeedRow] }

    @MainActor static func rows(_ chat: ChatSession) -> [ChatFeedRow] {
        let items = chat.log.items
        var out: [ChatFeedRow] = []
        out.reserveCapacity(items.count + 64)
        var kept: [String: Kept] = [:]
        // While a question is up, its card shows the questions, so the turn's list of them isn't drawn.
        let asking = chat.cardUp && [.question, .questionReview].contains(chat.screen.kind)
        for (i, item) in items.enumerated() {
            let gap: CGFloat = i == 0 && !chat.log.earlierHidden ? 0 : 16
            guard case .claude(let turn) = item else {
                out.append(ChatFeedRow(id: item.id, kind: .item(item), gap: gap))
                continue
            }
            if let k = chat.feedRows[turn.id], k.gap == gap, k.asking == asking, k.segments == turn.segments {
                out += k.rows
                kept[turn.id] = k
                continue
            }
            let rows = pieces(turn, item: item, gap: gap, asking: asking)
            out += rows
            kept[turn.id] = Kept(segments: turn.segments, gap: gap, asking: asking, rows: rows)
        }
        chat.feedRows = kept
        return out
    }

    /// For DuoChecks: turns whose rows were rebuilt.
    nonisolated(unsafe) static var built = 0

    static func pieces(_ turn: ChatTurn, item: ChatItem, gap: CGFloat, asking: Bool) -> [ChatFeedRow] {
        built += 1
        let blocks = ChatRuns.blocks(turn.segments)
        let lastAsked = blocks.last { if case .asked = $0 { return true } else { return false } }?.id
        // A section the card leaves out (the questions while their card is up) gets no piece: an
        // empty piece would still bring its padding.
        let sections = ChatClaudeCard.sections(blocks).filter { s in
            if asking, case .asked(let id, _) = s.first!, id == lastAsked { return false }
            return true
        }
        guard sections.count > size else { return [ChatFeedRow(id: turn.id, kind: .item(item), gap: gap)] }
        let count = (sections.count + size - 1) / size
        return (0..<count).map { k in
            let part = Array(sections[k * size..<min(sections.count, (k + 1) * size)])
            return ChatFeedRow(id: k == 0 ? turn.id : "\(turn.id)|\(k)",
                               kind: .piece(time: turn.time, sections: part, lastAsked: lastAsked, first: k == 0, last: k == count - 1),
                               gap: k == 0 ? gap : 0)
        }
    }
}

/// For DuoChecks only: the rows as plain values (the row types are internal).
public enum ChatFeedProof {
    public struct Row {
        public let id: String, gap: Double, isItem: Bool, first: Bool, last: Bool
        public let sections: [[ChatCardRow]]
    }
    public static var size: Int { ChatFeedRows.size }
    /// Turns whose rows were rebuilt, ever.
    public static var built: Int { ChatFeedRows.built }
    @MainActor public static func rows(_ chat: ChatSession) -> [Row] {
        ChatFeedRows.rows(chat).map { r in
            switch r.kind {
            case .item: Row(id: r.id, gap: Double(r.gap), isItem: true, first: true, last: true, sections: [])
            case .piece(_, let s, _, let f, let l): Row(id: r.id, gap: Double(r.gap), isItem: false, first: f, last: l, sections: s)
            }
        }
    }
    /// The card's sections, whole.
    public static func sections(_ turn: ChatTurn) -> [[ChatCardRow]] { ChatClaudeCard.sections(ChatRuns.blocks(turn.segments)) }
}

struct ChatFeedRowView: View, Equatable {
    let row: ChatFeedRow
    let chat: ChatSession

    nonisolated static func == (a: Self, b: Self) -> Bool { a.chat === b.chat && a.row == b.row }

    var body: some View {
        content.padding(.top, row.gap)
    }

    @ViewBuilder var content: some View {
        switch row.kind {
        case .item(let item): ChatItemView(item: item, chat: chat)
        case .piece(let time, let sections, let lastAsked, let first, let last):
            VStack(alignment: .leading, spacing: 4) {
                if first { ChatWho(who: "Claude", time: time) }
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(sections, id: \.first!.id) { section in
                        ChatCardSection(section: section, lastAsked: lastAsked, chat: chat).equatable()
                    }
                }
                // The card's padding: 14 above and 16 below, 18 at the sides; 10 between sections.
                .padding(EdgeInsets(top: first ? 14 : 10, leading: 18, bottom: last ? 16 : 0, trailing: 18))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(alignment: .top) {
                    let r = DuoMetric.radiusChatCard
                    UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(topLeading: first ? r.topLeading : 0, bottomLeading: last ? r.bottomLeading : 0,
                                                                              bottomTrailing: last ? r.bottomTrailing : 0, topTrailing: first ? r.topTrailing : 0))
                        .fill(DuoColor.pane)
                        // A point under the next piece, so no seam shows where they meet.
                        .padding(.bottom, last ? 0 : -1)
                }
            }
            .padding(.trailing, DuoSpace.chatCardTrailing)
        }
    }
}
