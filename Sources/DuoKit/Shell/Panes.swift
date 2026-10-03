import SwiftUI

// Slice 1 placeholders: each pane has its final background and nothing else, so the comparison
// loop checks pane edges and the toolbar first. Slices 2 and 3 fill them in.

struct HomePane: View {
    var body: some View { DuoColor.console }
}

struct ProjectMapPane: View {
    var body: some View { DuoColor.pane }
}

struct ActionColumnPane: View {
    var body: some View { DuoColor.pane }
}

struct ProjectSidebarPane: View {
    var body: some View { DuoColor.pane }
}

struct ConsolePane: View {
    var body: some View { DuoColor.console }
}

struct RightPane: View {
    var body: some View { DuoColor.pane }
}
