import AppKit
import DuoKit
import WebKit

// F-249: ⌘V (and the chat's other keys) with the editor's web view holding the keyboard went to the
// chat composer, because the check named the class "WKWebView" and the editor's is a subclass
// (EditorWebView / DuoWebView). A web view of any subclass, a text view and a terminal hold typing.

@MainActor func taskPaneKeyChecks() {
    print("who holds typing (F-249)")
    let web = DuoWebView(frame: .zero, configuration: WKWebViewConfiguration())
    check(holdsTyping(web), "a DuoWebView (the editor and viewer subclass it) holds typing, so ⌘V is its own")
    check(holdsTyping(NSTextView()), "a text view holds typing")
    check(!holdsTyping(nil) && !holdsTyping(NSView()), "no responder, or a plain view, doesn't")
}
