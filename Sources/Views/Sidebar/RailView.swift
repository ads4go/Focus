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
    /// screenshot of it: rgb(40, 40, 40) — but only while the window is
    /// inactive (some other app is frontmost). While Focus's window is
    /// actually key, the rail should read as a darker rgb(34, 34, 34)
    /// instead, same as the glassy edge above only lighting up while key.
    private var containerColor: Color {
        controlActiveState == .key
            ? Color(red: 34 / 255, green: 34 / 255, blue: 34 / 255)
            : Color(red: 40 / 255, green: 40 / 255, blue: 40 / 255)
    }
    private static let containerShape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
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
        .scrollIndicators(.never)
        .frame(width: 82)
        // A distinct gray card floating with a margin on all sides
        // (below), not chrome bleeding edge-to-edge.
        .clipShape(Self.containerShape)
        .background(containerColor, in: Self.containerShape)
        .overlay {
            if controlActiveState == .key {
                // Two localized corner hotspots (top-left, bottom-right)
                // over a faint base ring, instead of one straight diagonal
                // LinearGradient — this rail is tall and narrow, and a
                // corner-to-corner LinearGradient's unit-square axis
                // stretches to match that aspect ratio, so it comes out
                // nearly vertical in practice: both top corners end up
                // close to the bright end and the whole top edge reads as
                // too bright. Anchoring a RadialGradient at .topLeading /
                // .bottomTrailing instead keeps each highlight pinned to
                // its actual corner (a UnitPoint corner always maps to the
                // real pixel corner, whatever the aspect ratio) and lets
                // the top-right/bottom-left corners fall back to the dim
                // base ring untouched, matching OmniFocus's glassy edge.
                ZStack {
                    Self.containerShape
                        .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                    RadialGradient(
                        colors: [.white.opacity(0.35), .clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 50
                    )
                    .mask(Self.containerShape.stroke(lineWidth: 1))
                    RadialGradient(
                        colors: [.white.opacity(0.2), .clear],
                        center: .bottomTrailing,
                        startRadius: 0,
                        endRadius: 50
                    )
                    .mask(Self.containerShape.stroke(lineWidth: 1))
                }
                // Purely decorative — .mask() above only affects rendering,
                // not hit-testing, so without this the two RadialGradients'
                // full unclipped rectangles (they just *look* ring-shaped)
                // would sit on top of every tile underneath and swallow
                // clicks, which is what broke back-to-back tile selection.
                .allowsHitTesting(false)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 0)
        .padding(.vertical, 8)
    }
}

private struct RailTile: View {
    let item: RailItem
    let isSelected: Bool
    let badgeCount: Int?
    let action: () -> Void

    @Environment(\.controlActiveState) private var controlActiveState

    private var selectedFillColor: Color {
        controlActiveState == .key
            ? Color(red: 50 / 255, green: 50 / 255, blue: 51 / 255)
            : Color(red: 55 / 255, green: 55 / 255, blue: 56 / 255)
    }

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
            .padding(.top, 17)
            .padding(.bottom, 6)
            .background(
                isSelected ? selectedFillColor : Color.clear,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .padding(.horizontal, 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
