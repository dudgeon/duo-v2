import SwiftUI

// The feed's lazy rows (DL-137, ENH-23a). A long agent turn is hundreds of steps; as one row of
// the lazy stack it was built, measured and thrown away whole, and the stack's estimate of the
// feed's height swung by hundreds of thousands of points. So a Claude turn is several rows: its
// `Claude · 9:42` line, then one row per section of its card (a reply, a thought, a run of tool
// calls on one thread), each drawn on its piece of the card. Pieces meet edge to edge, so the
// card reads as one: rounded at the top of the first piece and the bottom of the last.

struct ChatFeedRow: Identifiable {
    enum Kind {
        /// Anything but Claude's turn: drawn as it always was.
        case item(ChatItem)
        /// `Claude · 9:42` over the card.
        case who(Date?)
        /// One section of the card; `first` and `last` say which corners round.
        case section([ChatCardRow], lastAsked: String?, first: Bool, last: Bool)
    }

    let id: String
    let kind: Kind
    /// The space above it: 16 between items (and below Earlier turns), 4 from `Claude · 9:42` to its card.
    let gap: CGFloat

    /// Every row of the feed, in order. Sections hidden while their card is up (a question's list)
    /// are left out, as the card's stack left them out.
    @MainActor static func rows(_ items: [ChatItem], chat: ChatSession, leadingGap: Bool) -> [ChatFeedRow] {
        var out: [ChatFeedRow] = []
        out.reserveCapacity(items.count * 4)
        let asking = chat.cardUp && [.question, .questionReview].contains(chat.screen.kind)
        for item in items {
            let gap: CGFloat = out.isEmpty && !leadingGap ? 0 : 16
            guard case .claude(let turn) = item else {
                out.append(ChatFeedRow(id: item.id, kind: .item(item), gap: gap))
                continue
            }
            out.append(ChatFeedRow(id: turn.id, kind: .who(turn.time), gap: gap))
            let blocks = ChatRuns.blocks(turn.segments)
            let lastAsked = blocks.last { if case .asked = $0 { return true } else { return false } }?.id
            let sections = ChatClaudeCard.sections(blocks).filter { s in
                if asking, case .asked(let id, _) = s.first!, id == lastAsked { return false }
                return true
            }
            if sections.isEmpty {
                out.append(ChatFeedRow(id: turn.id + "|card", kind: .section([], lastAsked: lastAsked, first: true, last: true), gap: 4))
            }
            for (i, s) in sections.enumerated() {
                out.append(ChatFeedRow(id: turn.id + "|" + s.first!.id, kind: .section(s, lastAsked: lastAsked, first: i == 0, last: i == sections.count - 1),
                                       gap: i == 0 ? 4 : 0))
            }
        }
        return out
    }
}

struct ChatFeedRowView: View {
    let row: ChatFeedRow
    let chat: ChatSession

    var body: some View {
        content.padding(.top, row.gap)
    }

    @ViewBuilder var content: some View {
        switch row.kind {
        case .item(let item): ChatItemView(item: item, chat: chat)
        case .who(let time):
            ChatWho(who: "Claude", time: time)
                .padding(.trailing, DuoSpace.chatCardTrailing)
        case .section(let blocks, let lastAsked, let first, let last):
            Group {
                if blocks.isEmpty { Color.clear.frame(height: 0) } else { ChatCardSection(section: blocks, lastAsked: lastAsked, chat: chat) }
            }
            // The card's padding, 14 above and 16 below, 18 at the sides; 10 between sections.
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
            .padding(.trailing, DuoSpace.chatCardTrailing)
        }
    }
}
