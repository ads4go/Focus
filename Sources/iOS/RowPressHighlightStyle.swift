import SwiftUI

/// A colored flash on tap-down that fades back out, used on project/task
/// rows across the iPhone app instead of relying on each row's default
/// press styling — NavigationLink's own default is a dull system gray, and
/// `.buttonStyle(.plain)` (used where a plain Button drives navigation
/// instead of NavigationLink, e.g. ProjectTaskListScreen's rows) shows no
/// press feedback at all. This stays visible for a moment as the row fades
/// while the next screen pushes in, instead of disappearing the instant a
/// finger lifts.
struct RowPressHighlightStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? tint.opacity(0.18) : Color.clear)
            .animation(.easeOut(duration: 0.25), value: configuration.isPressed)
    }
}
