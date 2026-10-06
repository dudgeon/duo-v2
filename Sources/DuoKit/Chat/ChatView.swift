import AppKit
import SwiftUI

// The chat pane (chat-mode-handoff `window`): the transcript on `chatGround`, your messages on the
// right in `chatYou`, Claude's replies on white cards, the composer at the bottom, or a review
// card docked in its place while Claude waits on you.

struct ChatPane: View {
    @Environment(AppModel.self) private var model
    let chat: ChatSession

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(chat.log.items) { item in
                            ChatItemView(item: item).id(item.id)
                        }
                    }
                    .padding(EdgeInsets(top: 20, leading: DuoSpace.chatColumnInset, bottom: 12, trailing: DuoSpace.chatColumnInset))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(height: 1).id(ChatPane.bottom)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: chat.log.items.count) { proxy.scrollTo(ChatPane.bottom, anchor: .bottom) }
            }
            ChatComposerStandIn()
                .padding(EdgeInsets(top: 0, leading: DuoSpace.chatColumnInset, bottom: 14, trailing: DuoSpace.chatColumnInset))
        }
        .background(DuoColor.chatGround)
    }

    static let bottom = "chat-bottom"
}

/// One transcript entry.
struct ChatItemView: View {
    let item: ChatItem

    var body: some View {
        switch item {
        case .you(let y): ChatYouBubble(you: y)
        }
    }
}

/// Your message: right-aligned, `chatYou`, at most 440 wide, its bottom-right corner sharp.
struct ChatYouBubble: View {
    let you: ChatYou

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ChatWho(who: "You", time: you.time)
            Text(you.text).duoText(.chatBody).foregroundStyle(DuoColor.text)
                .padding(EdgeInsets(top: 9, leading: 14, bottom: 9, trailing: 14))
                .background(UnevenRoundedRectangle(cornerRadii: DuoMetric.radiusChatBubble).fill(DuoColor.chatYou))
                .frame(maxWidth: DuoSpace.chatBubbleMax, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// `You · 9:41`, `Claude · 9:42`.
struct ChatWho: View {
    let who: String
    let time: Date?

    var body: some View {
        Text(time.map { "\(who) · \(ChatWho.clock.string(from: $0))" } ?? who)
            .duoText(.chatMeta).foregroundStyle(DuoColor.text2)
    }

    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "H:mm"
        return f
    }()
}

/// The composer's look until it works (phase 4): Claude's prompt as a field.
struct ChatComposerStandIn: View {
    var body: some View {
        Text("Reply to Claude").duoText(.chatBody).foregroundStyle(DuoColor.text2)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
            .background(RoundedRectangle(cornerRadius: DuoMetric.radiusComposer).fill(DuoColor.pane))
            .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusComposer).strokeBorder(DuoColor.controlEdge, lineWidth: DuoMetric.borderHairline))
    }
}
