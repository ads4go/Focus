import SwiftUI

/// Per-perspective accent colors, matching RailItem.tint / TaskListView's
/// accentColor on macOS (Sources/Views/Sidebar/RailItem.swift). Duplicated
/// rather than shared since RailItem.swift lives in a macOS-only source
/// folder not included in the FocusIOS target — see the plan's precedent
/// for FocusIOSApp/RootView (small enough that duplicating beats reshaping
/// the Mac target's source layout).
enum PerspectiveTint {
    static let inbox = Color(red: 90 / 255, green: 90 / 255, blue: 128 / 255)
    static let projects = Color.blue
    static let forecast = Color.red
    static let review = Color(red: 109 / 255, green: 124 / 255, blue: 255 / 255)
}
