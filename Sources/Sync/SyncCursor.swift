import Foundation

/// Persisted watermarks driving the sync loop — see SyncEngine.swift for how
/// they're used to derive "what's dirty" without a separate outbox table.
enum SyncCursor {
    private static let lastPushedKey = "sync.lastPushedAt"
    private static let lastPulledKey = "sync.lastPulledAt"

    static var lastPushedAt: Date {
        get { UserDefaults.standard.object(forKey: lastPushedKey) as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: lastPushedKey) }
    }

    static var lastPulledAt: Date {
        get { UserDefaults.standard.object(forKey: lastPulledKey) as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: lastPulledKey) }
    }
}
