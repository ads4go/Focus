import SwiftUI

/// The six top-level entries in the always-visible rail. Colors follow the
/// same "colored icon, standard-color text" convention as Reminders/OmniFocus
/// (e.g. Forecast is red, Flagged is orange) so the rail is scannable at a glance.
enum RailItem: String, CaseIterable, Hashable, Identifiable {
    case inbox, projects, tags, forecast, flagged, review

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: return "Inbox"
        case .forecast: return "Forecast"
        case .flagged: return "Flagged"
        case .projects: return "Projects"
        case .tags: return "Tags"
        case .review: return "Review"
        }
    }

    var systemImage: String {
        switch self {
        case .inbox: return "tray.fill"
        case .forecast: return "calendar"
        case .flagged: return "flag.fill"
        case .projects: return "folder.fill"
        case .tags: return "tag.fill"
        case .review: return "checkmark.seal.fill"
        }
    }

    /// Matches OmniFocus 4's actual perspective-color mapping (Inbox is
    /// purple, Projects is blue — easy to get backwards since Reminders
    /// uses the opposite convention).
    var tint: Color {
        switch self {
        case .inbox: return .purple
        case .forecast: return .red
        case .flagged: return .orange
        case .projects: return .blue
        case .tags: return .pink
        case .review: return .teal
        }
    }
}
