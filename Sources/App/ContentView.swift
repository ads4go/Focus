import SwiftUI
import SwiftData
import Combine
import AppKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSessionStore.self) private var authStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var railSelection: RailItem? = .inbox
    /// Toggled by re-tapping the already-selected Projects rail button —
    /// animates the Projects-list pane's width down to 0 (see taskTier's
    /// .projects case). NavigationSplitView was tried here instead, since
    /// it gives real drag-resize for free, but its native "sidebar" chrome
    /// elevates the collapsing pane over its siblings (briefly covering the
    /// rail buttons) and bleeds into the title bar at small window sizes —
    /// both unavoidable side effects of its built-in transition. A plain
    /// HStack plus a hand-rolled divider (below) avoids both while keeping
    /// the same static-content wipe animation and adding real drag-resize.
    @State private var isProjectsListCollapsed = false
    /// User-adjustable width of taskTier (the "left pane") while it's paired
    /// with a middle pane — every rail except Inbox (.projects/.review/
    /// .tags/.forecast/.flagged) shares this one mechanism and state
    /// variable now; it used to be a native HSplitView divider for all but
    /// Projects, which let detailLeftPane get squeezed well below its own
    /// declared minWidth whenever detailPaneWidth grew from *outside* the
    /// HSplitView (HSplitView's minWidth enforcement isn't reliable against
    /// an ancestor-driven resize, only against dragging its own divider
    /// directly) — the custom ResizableDivider here doesn't have that gap,
    /// since maxLeftPaneWidth is recomputed and reapplied on every geometry
    /// change, not just while actively dragging.
    /// Also the width taskTier's own content renders at (so dragging
    /// reflows it normally), kept separate from whatever the Projects-only
    /// collapse animation is doing to that same pane's outer width, so a
    /// resize while expanded reflows live, while a collapse/reveal only
    /// clips a constant-width render (no reflow/jitter mid-animation).
    @State private var leftPaneWidth: CGFloat = 420
    /// Toggled by the "Inspect" toolbar button — same animated-clip +
    /// drag-resize mechanism as isProjectsListCollapsed/leftPaneWidth,
    /// mirrored to the trailing edge since this pane sits at the window's
    /// right end: content is trailing-aligned so collapsing sweeps the
    /// clip window's left edge rightward (covering it) and revealing
    /// sweeps it back leftward, matching a swipe closed/open to the right.
    @State private var isDetailPaneCollapsed = false
    @State private var detailPaneWidth: CGFloat = 380
    /// The left pane is a filter on the middle pane, not a navigation
    /// picker — matching OmniFocus, where selecting nothing shows every
    /// task and selecting one or more items (multi-select, via List's
    /// native Set-based selection) narrows to just those. Empty means "no
    /// filter" everywhere these are read, never "show nothing."
    @State private var selectedProjectIDs: Set<UUID> = []
    @State private var selectedTagIDs: Set<UUID> = []
    /// Separate from selectedTagIDs: Flagged's own left pane is a tag
    /// filter over flagged items specifically, independent of whatever's
    /// selected on the Tags tab.
    @State private var selectedFlaggedTagIDs: Set<UUID> = []
    @State private var selectedTaskID: UUID?
    @State private var isShowingQuickEntry = false
    @State private var pushDebounceTask: Task<Void, Never>?

    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil })
    private var allTasks: [TaskItem]
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil })
    private var allProjects: [Project]
    @Query(filter: #Predicate<Tag> { $0.deletedAt == nil })
    private var allTags: [Tag]

    private var rail: RailItem { railSelection ?? .inbox }

    /// Matches OmniFocus: hiding a pane lets the whole window shrink by
    /// that same pane's own minimum width, rather than a single static
    /// floor that assumes every pane is always expanded. Each collapsible
    /// pane contributes its own minimum plus its divider (8) only while
    /// it's actually visible. These three minimums are each shared across
    /// every tab where that pane appears — Self.leftPaneMinWidth,
    /// Self.middlePaneMinWidth, and Self.rightPaneMinWidth below are the
    /// single source of truth, also used by leftAndMiddleSection and the
    /// two ResizableDividers so the numbers can't drift apart again.
    private var minWindowWidth: CGFloat {
        let railFootprint: CGFloat = 96 // fixed 80pt rail + 8pt margin on each side
        let dividerWidth: CGFloat = 8

        var width = railFootprint
        switch rail {
        case .projects:
            width += isProjectsListCollapsed
                ? Self.middlePaneMinWidth
                : Self.leftPaneMinWidth + dividerWidth + Self.middlePaneMinWidth
        case .review, .tags, .forecast, .flagged:
            width += Self.leftPaneMinWidth + dividerWidth + Self.middlePaneMinWidth
        case .inbox:
            // Inbox has no middle pane of its own, but its single pane
            // shows the same kind of full task list the middle pane does
            // everywhere else — matches that width, not the left pane's.
            width += Self.middlePaneMinWidth
        }
        if !isDetailPaneCollapsed {
            width += dividerWidth + Self.rightPaneMinWidth
        }
        return width
    }

    /// taskTier's minimum width — the same on every tab. Matches
    /// OmniFocus's own left (outline) pane (omni.png), tuned slightly down
    /// from the raw pixel measurement (~240pt) per visual comparison.
    private static let leftPaneMinWidth: CGFloat = 230
    /// detailLeftPane's minimum width — already uniform across every tab
    /// where it appears (.projects/.review/.tags/.forecast). Matches
    /// OmniFocus's own middle pane (omni.png), tuned down slightly from
    /// the raw pixel measurement (~441pt). (Was briefly tied to
    /// leftPaneMinWidth to fix 100pt being unusable for real task-list
    /// content — see skinnyMiddlePane.png — but the two panes' actual
    /// reference widths differ, so each has its own measured value
    /// instead of one deriving from the other.)
    private static let middlePaneMinWidth: CGFloat = 430
    /// detailRightPane's minimum width — already uniform since it's a
    /// single top-level ResizableDivider shared by every tab, not
    /// duplicated per rail like the other two used to be. Matches
    /// OmniFocus's own right (inspector) pane (omni.png), tuned down
    /// slightly from the raw pixel measurement (~295pt).
    private static let rightPaneMinWidth: CGFloat = 285
    private static let dividerWidth: CGFloat = 8
    private static let railFootprint: CGFloat = 96

    /// How much leftAndMiddleSection needs right now, for the current rail
    /// and collapse state — reserved against the *actual* current
    /// leftPaneWidth (not just its minimum) whenever a middle pane is in
    /// play, since dragging detailPaneWidth wider must not encroach on
    /// space the left pane is genuinely occupying at that moment.
    private var leftAndMiddleSectionReserve: CGFloat {
        switch rail {
        case .projects:
            return isProjectsListCollapsed
                ? Self.middlePaneMinWidth
                : leftPaneWidth + Self.dividerWidth + Self.middlePaneMinWidth
        case .review, .tags, .forecast, .flagged:
            return leftPaneWidth + Self.dividerWidth + Self.middlePaneMinWidth
        case .inbox:
            return Self.leftPaneMinWidth
        }
    }

    /// The most detailPaneWidth may grow to without pushing anything else
    /// (rail included) out of the window that's actually available right
    /// now — as opposed to a static 600 that has no idea how wide the
    /// window currently is.
    private func maxDetailPaneWidth(totalWidth: CGFloat) -> CGFloat {
        let available = totalWidth - Self.railFootprint - leftAndMiddleSectionReserve - Self.dividerWidth
        return max(Self.rightPaneMinWidth, min(600, available))
    }

    /// Same idea, mirrored, for the left pane's own divider (used on every
    /// rail with a middle pane — .projects/.review/.tags/.forecast/
    /// .flagged) — reserves against detailRightPane's actual current width
    /// (its clamped effective width, not the raw dragged value, in case
    /// that's itself out of range for the current window size).
    private func maxLeftPaneWidth(totalWidth: CGFloat) -> CGFloat {
        let rightReserve = isDetailPaneCollapsed
            ? 0
            : Self.dividerWidth + min(detailPaneWidth, maxDetailPaneWidth(totalWidth: totalWidth))
        let available = totalWidth - Self.railFootprint - Self.dividerWidth - Self.middlePaneMinWidth - rightReserve
        return max(Self.leftPaneMinWidth, min(600, available))
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 0) {
                RailView(selection: railSelection, onSelect: handleRailTap, badgeCount: badgeCount)
                    // Higher priority than every other pane here (all
                    // default to 0): if the window ever gets too narrow for
                    // everything at once, SwiftUI shrinks the flexible
                    // task/detail panes first and leaves the rail's own
                    // fixed size alone, rather than clipping it. This is
                    // the backstop; maxDetailPaneWidth/maxLeftPaneWidth
                    // below are what actually keep things from getting
                    // that narrow in the first place while dragging.
                    .layoutPriority(1)
                leftAndMiddleSection(totalWidth: geometry.size.width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipped()
                if !isDetailPaneCollapsed {
                    ResizableDivider(
                        width: $detailPaneWidth,
                        minWidth: Self.rightPaneMinWidth,
                        maxWidth: maxDetailPaneWidth(totalWidth: geometry.size.width),
                        dragSign: -1
                    )
                }
                detailRightPane
                    // Same trick as taskTier's .projects case, mirrored:
                    // this frame tracks the live (clamped) drag width so
                    // resizing reflows content normally, while the one
                    // below only ever animates isDetailPaneCollapsed, never
                    // the width, so the collapse/reveal clips a static
                    // render instead of reflowing it. Clamping to
                    // maxDetailPaneWidth here (not just in the divider's
                    // drag handler) is what protects the rail if the
                    // window itself gets natively resized smaller after a
                    // wide drag, rather than only while actively dragging.
                    .frame(width: min(detailPaneWidth, maxDetailPaneWidth(totalWidth: geometry.size.width)))
                    .frame(maxHeight: .infinity, alignment: .top)
                    // Trailing-aligned (not leading, like taskTier): this pane
                    // sits at the window's right end, so the content that
                    // should stay put is its right edge, and the clip window's
                    // LEFT edge is what sweeps — right to cover it, left to
                    // reveal it.
                    .frame(
                        width: isDetailPaneCollapsed ? 0 : min(detailPaneWidth, maxDetailPaneWidth(totalWidth: geometry.size.width)),
                        alignment: .trailing
                    )
                    .clipped()
            }
        }
        .frame(minWidth: minWindowWidth, minHeight: 100)
        .sheet(isPresented: $isShowingQuickEntry) {
            QuickEntryPanel(defaultProjectID: defaultProjectIDForQuickEntry) {
                isShowingQuickEntry = false
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    isShowingQuickEntry = true
                } label: {
                    Label("New Action", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            ToolbarItem {
                Button {
                    Task { await SyncEngine.syncNow(context: modelContext) }
                } label: {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            ToolbarItem {
                Button("Sign Out") {
                    Task { await authStore.signOut() }
                }
            }
            ToolbarItem {
                Button {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        isDetailPaneCollapsed.toggle()
                    }
                } label: {
                    Label("Inspect", systemImage: "info")
                }
                .help("Inspect")
            }
        }
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

    /// Re-tapping the already-selected rail item is repurposed as a toggle
    /// (currently only meaningful for Projects, whose list pane it
    /// shows/hides); tapping a different item switches to it normally.
    private func handleRailTap(_ item: RailItem) {
        guard item == railSelection else {
            railSelection = item
            selectedProjectIDs = []
            selectedTagIDs = []
            selectedFlaggedTagIDs = []
            selectedTaskID = nil
            return
        }
        if item == .projects {
            withAnimation(.easeInOut(duration: 0.28)) {
                isProjectsListCollapsed.toggle()
            }
        }
    }

    // MARK: - Tiers
    //
    // App-wide layout:
    // - taskTier: mode content (Projects/Review/Tags/Inbox/Forecast/Flagged)
    // - detailLeftPane: selected list for Review/Tags/Forecast/Projects.
    // - detailRightPane: task details, collapsible via the toolbar's
    //   "Inspect" button.

    @ViewBuilder
    private var taskTier: some View {
        switch rail {
        case .projects:
            ProjectListView { ids in
                selectedProjectIDs = ids
                selectedTaskID = nil
            }
        case .review:
            // Single-select paging by design (see ReviewView) — wraps its
            // one ID into the shared multi-select state as a lone element.
            ReviewView { id in
                selectedProjectIDs = [id]
                selectedTaskID = nil
            }
        case .tags:
            TagListView { ids in
                selectedTagIDs = ids
                selectedTaskID = nil
            }
        case .inbox:
            TaskListView(perspective: .inbox, title: "Inbox", selectedTaskID: $selectedTaskID)
        case .forecast:
            ForecastCalendarView()
        case .flagged:
            // Flagged's left pane is a tag filter over flagged items, not
            // the flagged list itself — that now lives in detailLeftPane,
            // same shape as Tags/Projects (see leftAndMiddleSection).
            TagListView { ids in
                selectedFlaggedTagIDs = ids
                selectedTaskID = nil
            }
        }
    }

    /// Always shows a task list — an empty selectedProjectIDs means "no
    /// filter" (every task with a project), not "nothing to show", so
    /// there's no placeholder branch here (matches OmniFocus: the left
    /// pane filters the middle pane, it doesn't gate it).
    @ViewBuilder
    private var projectsDetail: some View {
        TaskListView(
            perspective: .projects(selectedProjectIDs),
            title: projectsDetailTitle,
            selectedTaskID: $selectedTaskID
        )
    }

    /// The Projects tab's header always reads "Projects" — each selected
    /// project now gets its own dropdown section in the list below (see
    /// TaskListView's projectSections), so the header no longer needs to
    /// name the single selected project the way it used to. Review still
    /// pages one project at a time, so it keeps naming the project it's
    /// currently reviewing.
    private var projectsDetailTitle: String {
        guard rail == .review else { return "Projects" }
        guard selectedProjectIDs.count == 1, let id = selectedProjectIDs.first else {
            return "Review"
        }
        return allProjects.first { $0.id == id }?.name ?? "Project"
    }

    /// Everything left of the (now top-level, universally collapsible)
    /// detailRightPane: taskTier plus, for rails where it applies,
    /// detailLeftPane. Split out per rail exactly as before detailRightPane
    /// moved out — Inbox still has no left pane, so taskTier sits directly
    /// beside detailRightPane with no empty middle section reserved for it.
    /// Every other rail shares one HStack + ResizableDivider structure (not
    /// HSplitView — see leftPaneWidth's doc comment for why); only Projects
    /// additionally supports collapsing its left pane to width 0.
    @ViewBuilder
    private func leftAndMiddleSection(totalWidth: CGFloat) -> some View {
        switch rail {
        case .projects, .review, .tags, .forecast, .flagged:
            let effectiveWidth = min(leftPaneWidth, maxLeftPaneWidth(totalWidth: totalWidth))
            let isCollapsed = rail == .projects && isProjectsListCollapsed
            HStack(alignment: .top, spacing: 0) {
                taskTier
                    .frame(width: effectiveWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .frame(width: isCollapsed ? 0 : effectiveWidth, alignment: .leading)
                    .clipped()
                if !isCollapsed {
                    ResizableDivider(
                        width: $leftPaneWidth,
                        minWidth: Self.leftPaneMinWidth,
                        maxWidth: maxLeftPaneWidth(totalWidth: totalWidth)
                    )
                }
                detailLeftPane
                    .frame(minWidth: Self.middlePaneMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipped()
            }
        case .inbox:
            // No middle pane of its own here, but this single pane shows
            // a full task list like the middle pane does everywhere else
            // — matches that width, not the (narrower) left pane's.
            taskTier
                .frame(minWidth: Self.middlePaneMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
        }
    }

    @ViewBuilder
    private var detailLeftPane: some View {
        switch rail {
        case .projects, .review:
            projectsDetail
        case .tags:
            TaskListView(
                perspective: .tags(selectedTagIDs),
                title: tagsDetailTitle,
                selectedTaskID: $selectedTaskID
            )
        case .forecast:
            ForecastView(selectedTaskID: $selectedTaskID)
        case .flagged:
            // taskTier holds the tag-filter list for this rail now; this
            // is the actual flagged task list, filtered by it.
            TaskListView(
                perspective: .flagged(tagIDs: selectedFlaggedTagIDs),
                title: "Flagged",
                selectedTaskID: $selectedTaskID
            )
        case .inbox:
            Color.clear
        }
    }

    private var tagsDetailTitle: String {
        guard selectedTagIDs.count == 1, let id = selectedTagIDs.first else {
            return "Tags"
        }
        return allTags.first { $0.id == id }?.name ?? "Tag"
    }

    @ViewBuilder
    private var detailRightPane: some View {
        if let task = selectedTask {
            TaskDetailView(task: task) { projectID in
                railSelection = .projects
                selectedProjectIDs = [projectID]
                selectedTaskID = nil
            }
        } else {
            ContentUnavailableView("No Action Selected", systemImage: "checklist")
        }
    }

    private var selectedTask: TaskItem? {
        selectedTaskID.flatMap { id in allTasks.first { $0.id == id } }
    }

    private var defaultProjectIDForQuickEntry: UUID? {
        guard rail == .projects || rail == .review, selectedProjectIDs.count == 1 else { return nil }
        return selectedProjectIDs.first
    }

    /// Rail badge counts. nil hides the badge (Projects/Tags never show
    /// one; the others hide it specifically at a zero count, matching
    /// badges.png's reference where empty perspectives show no badge at
    /// all rather than a "0").
    private func badgeCount(for item: RailItem) -> Int? {
        let count: Int
        switch item {
        case .inbox:
            // Matches Perspectives.tasks(for: .inbox, ...)'s own filter.
            count = allTasks.filter { $0.deletedAt == nil && $0.projectID == nil && !$0.completed }.count
        case .forecast:
            let endOfToday = Calendar.current.date(
                bySettingHour: 23, minute: 59, second: 59, of: Date()
            ) ?? Date()
            count = allTasks.filter { task in
                guard task.deletedAt == nil, !task.completed, let due = task.dueDate else { return false }
                return due <= endOfToday
            }.count
        case .flagged:
            // "Projects or tasks, but not subtasks" — parentTaskID == nil
            // excludes subtasks; Project has no flagged concept in this
            // model, so only top-level tasks count.
            count = allTasks.filter { $0.deletedAt == nil && $0.flagged && !$0.completed && $0.parentTaskID == nil }.count
        case .review:
            count = allProjects.filter { $0.deletedAt == nil && !$0.isCompleted && $0.isDueForReview }.count
        case .projects, .tags:
            return nil
        }
        return count > 0 ? count : nil
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

/// A thin draggable divider standing in for HSplitView's own — used where a
/// pane also needs to animate its collapse/reveal, which HSplitView can't do
/// (see isProjectsListCollapsed's doc comment). Drag deltas are applied
/// relative to the width at gesture start rather than added continuously, so
/// they can't compound if a drag ends mid-frame.
private struct ResizableDivider: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    /// +1 when the pane being resized is on this divider's leading side (so
    /// dragging right widens it — the Projects pane's case), -1 when the
    /// pane is on the trailing side instead (dragging right narrows it —
    /// detailRightPane's case, since its divider sits on its leading edge).
    var dragSign: CGFloat = 1

    @State private var widthAtDragStart: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 8)
            .contentShape(Rectangle())
            .overlay(Divider())
            .onHover { isHovering in
                if isHovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let base = widthAtDragStart ?? width
                        widthAtDragStart = base
                        width = min(max(base + dragSign * value.translation.width, minWidth), maxWidth)
                    }
                    .onEnded { _ in
                        widthAtDragStart = nil
                    }
            )
    }
}
