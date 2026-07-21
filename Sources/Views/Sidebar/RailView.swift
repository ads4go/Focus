import SwiftUI

/// The leftmost rail: always visible, never collapses (it's a plain sibling
/// next to the NavigationSplitView in ContentView, not one of its columns —
/// NavigationSplitView's standard collapse toggle only ever affects its own
/// leading column, which here is the projects/tags list one level in).
///
/// Laid out as icon-on-top/label-below tiles (matching OmniFocus's rail)
/// rather than a standard List with side-by-side Label rows.
struct RailView: View {
    let selection: RailItem?
    /// Called with the tapped item on every tap, including re-tapping the
    /// item that's already selected — the caller (ContentView) decides what
    /// that means (e.g. toggling the Projects list pane).
    let onSelect: (RailItem) -> Void
    /// nil hides the badge entirely (e.g. Projects/Tags, or a zero count);
    /// the caller (ContentView) owns what each count actually means.
    var badgeCount: (RailItem) -> Int? = { _ in nil }

    /// Drives the glassy border below: OmniFocus only shows it while its
    /// window is actually key (frontmost/focused), not when the app is
    /// merely open but some other window has focus.
    @Environment(\.controlActiveState) private var controlActiveState

    /// Matches OmniFocus's rail container color, picked directly from a
    /// screenshot of it: rgb(40, 40, 40).
    private static let containerColor = Color(red: 40 / 255, green: 40 / 255, blue: 40 / 255)
    private static let containerShape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        // ScrollView (not a plain VStack) so a short window makes the rail
        // scrollable to reach the cut-off buttons, rather than just
        // clipping them out of reach entirely.
        ScrollView {
            VStack(spacing: 2) {
                ForEach(RailItem.allCases) { item in
                    RailTile(item: item, isSelected: selection == item, badgeCount: badgeCount(item)) {
                        onSelect(item)
                    }
                }
            }
            .padding(.top, 4)
            .padding(.horizontal, 3)
            .padding(.bottom, 10)
        }
        .scrollIndicators(.hidden)
        .frame(width: 80)
        // A distinct gray card floating with a margin on all sides
        // (below), not chrome bleeding edge-to-edge.
        .background(Self.containerColor, in: Self.containerShape)
        .overlay {
            if controlActiveState == .key {
                // Subtler than before, and lit from the left rather than
                // directly overhead — matches OmniFocus's glassy edge,
                // which is brighter on its left side than its right.
                Self.containerShape
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.2), .white.opacity(0.04)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1
                    )
            }
        }
        .padding(8)
    }
}

private struct RailTile: View {
    let item: RailItem
    let isSelected: Bool
    let badgeCount: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                // Just a colorized glyph on a transparent background — not a
                // colored square badge — matching OmniFocus's rail icons.
                Image(systemName: item.systemImage)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(item.tint)
                    .frame(height: 24)
                    .overlay(alignment: .topTrailing) {
                        if let badgeCount {
                            Text("\(badgeCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 15, minHeight: 15)
                                .background(item.tint, in: Capsule())
                                .offset(x: 10, y: -6)
                        }
                    }
                Text(item.title)
                    .font(.caption2)
                    .foregroundStyle(Color(red: 155 / 255, green: 155 / 255, blue: 155 / 255))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11.5)
            .background(
                isSelected ? Color.secondary.opacity(0.25) : Color.clear,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            // Applied after .background (not before, which was the bug:
            // .background always sizes itself to its child's *reported*
            // size, and .padding restores the space it took when
            // reporting upward — so padding placed before .background was
            // invisible to it no matter the value). Placed after, it
            // shrinks the visible/colored box itself and adds a
            // transparent gutter around it, while the Button's own tap
            // target (one level further out) still spans the full row.
            .padding(.horizontal, 1)
        }
        .buttonStyle(.plain)
    }
}
