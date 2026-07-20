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

    var body: some View {
        VStack(spacing: 2) {
            Text("TEMP MARKER: RAIL")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.gray, in: Capsule())
                .padding(.top, 2)
            ForEach(RailItem.allCases) { item in
                RailTile(item: item, isSelected: selection == item) {
                    onSelect(item)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .padding(.horizontal, 6)
        .frame(width: 92)
        // Matches OmniFocus's lighter-gray sidebar chrome instead of the
        // near-black window background bleeding all the way through.
        .background(.regularMaterial)
    }
}

private struct RailTile: View {
    let item: RailItem
    let isSelected: Bool
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
                Text(item.title)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                isSelected ? Color.secondary.opacity(0.25) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}
