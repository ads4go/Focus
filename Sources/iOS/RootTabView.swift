import SwiftUI
import SwiftData

/// The iPhone app's 4-tab shell — Inbox, Projects, Forecast, Review (Tags,
/// Flagged, and Nearby are explicitly excluded per the mobile app's scope).
/// Each tab owns its own NavigationStack; unlike the Mac rail+pane layout,
/// nothing here needs cross-tab shared selection state.
struct RootTabView: View {
    private enum Tab {
        // Review hidden for now — uncomment (here and below) to restore.
        case inbox, projects, forecast // , review
        /// Not a real tab with content — selecting it opens menuSheet
        /// (Sync Now / Log Out) and immediately reverts to whichever tab
        /// was active before, so it never actually "shows" as selected.
        case menu
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: Tab = .inbox
    @State private var isShowingMenu = false
    /// Mirrors ContentView's own schedulePush on macOS — debounces a
    /// push-only sync after a local SwiftData save so edits made on the
    /// phone reach Supabase quickly, without waiting for the 25s pull loop.
    @State private var pushDebounceTask: Task<Void, Never>?

    /// A plain per-NavigationStack .tint() colors that stack's own content
    /// (buttons, links) but doesn't reach TabView's own tab-bar chrome —
    /// the selected tab's icon/label only follow a .tint() applied to the
    /// TabView itself, so this drives that one dynamically off the current
    /// selection instead, matching each tab's RailItem.tint equivalent.
    private var currentTint: Color {
        switch selectedTab {
        case .inbox: return PerspectiveTint.inbox
        case .projects: return PerspectiveTint.projects
        case .forecast: return PerspectiveTint.forecast
        // case .review: return PerspectiveTint.review
        case .menu: return .gray
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                InboxScreen()
            }
            .tabItem { Label("Inbox", systemImage: "tray.fill") }
            .tag(Tab.inbox)

            NavigationStack {
                ProjectsScreen()
            }
            .tabItem { Label("Projects", systemImage: "circle.grid.3x3.fill") }
            .tag(Tab.projects)

            NavigationStack {
                ForecastScreen()
            }
            .tabItem { Label("Forecast", systemImage: "calendar") }
            .tag(Tab.forecast)

            // Review hidden for now — uncomment (here and above) to restore.
            // NavigationStack {
            //     ReviewScreen()
            // }
            // .tabItem { Label("Review", systemImage: "checkmark.seal.fill") }
            // .tag(Tab.review)

            // Blank content — selecting this tab never actually shows it,
            // see onChange(of: selectedTab) below.
            Color.clear
                .tabItem { Label("Menu", systemImage: "line.3.horizontal") }
                .tag(Tab.menu)
        }
        .tint(currentTint)
        .onChange(of: selectedTab) { oldValue, newValue in
            guard newValue == .menu else { return }
            isShowingMenu = true
            selectedTab = oldValue
        }
        .sheet(isPresented: $isShowingMenu) {
            MenuSheet()
        }
        // Sync was never wired up anywhere in the iOS target before this —
        // ContentView.swift is where macOS starts it, and nothing here
        // mirrored that. Same three triggers as ContentView: a recurring
        // pull/push loop tied to this view's lifetime, an immediate sync on
        // returning to the foreground, and a debounced push after every
        // local save (see schedulePush below).
        .task {
            while !Task.isCancelled {
                await SyncEngine.syncNow(context: modelContext)
                try? await Task.sleep(for: .seconds(25))
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await SyncEngine.syncNow(context: modelContext) }
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave, object: modelContext)) { _ in
            schedulePush()
        }
    }

    private func schedulePush() {
        pushDebounceTask?.cancel()
        pushDebounceTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await SyncEngine.pushAll(context: modelContext)
        }
    }
}
