import SwiftUI
import SwiftData

/// The iPhone Review tab — one project at a time (matching the reference
/// screenshots' pager), with up/down paging and a "Mark Reviewed" pill that
/// advances the queue. The dueProjects computation and markSelectedReviewed
/// queue-advance algorithm (capture the pre-mutation ordered id list before
/// marking reviewed, since that immediately drops the project out of
/// dueProjects) are ported verbatim from ReviewView.swift's logic.
struct ReviewScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.sortOrder)
    private var allProjects: [Project]
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil })
    private var allTasks: [TaskItem]
    @Query(filter: #Predicate<Tag> { $0.deletedAt == nil })
    private var allTags: [Tag]
    @Query(filter: #Predicate<TaskTag> { $0.deletedAt == nil })
    private var allTaskTags: [TaskTag]

    @State private var selection: UUID?
    @State private var isShowingQueue = false
    /// Drives a sheet-presented TaskEditSheet — matches Inbox/Forecast/
    /// ProjectTaskListScreen's identical choice so tapping an action item
    /// looks and behaves the same everywhere in the app.
    @State private var selectedTaskForDetail: TaskItem?

    private var dueProjects: [Project] {
        allProjects
            .filter(\.isDueForReview)
            .sorted { ($0.nextReviewDate ?? .distantPast) < ($1.nextReviewDate ?? .distantPast) }
    }

    private var selectedIndex: Int? {
        guard let selection else { return nil }
        return dueProjects.firstIndex { $0.id == selection }
    }

    private var selectedProject: Project? {
        selection.flatMap { id in allProjects.first { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            perspectiveHeader
            content
        }
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if selectedProject != nil {
                controlBar
            }
        }
        .sheet(isPresented: $isShowingQueue) {
            NavigationStack {
                reviewQueueList
                    .navigationTitle("Review")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isShowingQueue = false }
                        }
                    }
            }
        }
        .sheet(item: $selectedTaskForDetail) { task in
            NavigationStack {
                TaskEditSheet(task: task, tint: PerspectiveTint.review)
                    .navigationTitle("Action")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { selectedTaskForDetail = nil }
                        }
                    }
            }
        }
        .onAppear {
            if selection == nil {
                selection = dueProjects.first?.id
            }
        }
    }

    // Big colored perspective title, matching Inbox/Projects/Forecast's own
    // header — title and the queue-list button share one line, instead of
    // a separate native toolbar button above a plain small nav title.
    private var perspectiveHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Review")
                .font(.largeTitle.bold())
                .foregroundStyle(PerspectiveTint.review)
            Spacer()
            Button {
                isShowingQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.title3.weight(.semibold))
            }
            // Explicit, not inherited — see InboxScreen's header for why.
            .foregroundStyle(PerspectiveTint.review)
            .disabled(dueProjects.isEmpty)
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var content: some View {
        if let project = selectedProject {
            VStack(alignment: .leading, spacing: 0) {
                header(for: project)
                Divider()
                taskList(for: project)
            }
        } else {
            ContentUnavailableView("Nothing Due for Review", systemImage: "checkmark.seal")
        }
    }

    private func header(for project: Project) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let selectedIndex {
                Text("Project \(selectedIndex + 1) of \(dueProjects.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(project.name)
                .font(.title.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private func taskList(for project: Project) -> some View {
        let tasks = Perspectives.tasks(for: .projects([project.id]), allTasks: allTasks, allTaskTags: allTaskTags)
        return List {
            ForEach(tasks) { task in
                NavigationLink {
                    TaskDetailView(task: task)
                } label: {
                    MobileTaskRow(
                        task: task,
                        tagNames: Perspectives.tags(for: task, allTags: allTags, allTaskTags: allTaskTags).map(\.name),
                        onToggleComplete: { Mutations.toggleCompleted(task, in: modelContext) }
                    )
                }
            }
        }
        .listStyle(.plain)
    }

    private var reviewQueueList: some View {
        List(dueProjects) { project in
            Button {
                selection = project.id
                isShowingQueue = false
            } label: {
                HStack {
                    Image(systemName: "circle.grid.3x3.fill")
                        .foregroundStyle(PerspectiveTint.review)
                    Text(project.name)
                        .foregroundStyle(.primary)
                    Spacer()
                    if project.id == selection {
                        Image(systemName: "checkmark")
                            .foregroundStyle(PerspectiveTint.review)
                    }
                }
            }
        }
    }

    private var controlBar: some View {
        HStack {
            HStack(spacing: 16) {
                Button { selectAdjacent(-1) } label: { Image(systemName: "chevron.up") }
                    .disabled((selectedIndex ?? 0) <= 0)
                Button { selectAdjacent(1) } label: { Image(systemName: "chevron.down") }
                    .disabled(selectedIndex.map { $0 >= dueProjects.count - 1 } ?? true)
            }
            .font(.body.weight(.semibold))
            // Explicit, not inherited — see InboxScreen's header for why.
            .foregroundStyle(PerspectiveTint.review)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.15), in: Capsule())

            Spacer()

            Button(action: markSelectedReviewed) {
                Label("Mark Reviewed", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .tint(PerspectiveTint.review)
            .disabled(selection == nil)
        }
        .padding()
        .background(.bar)
    }

    private func selectAdjacent(_ delta: Int) {
        guard let selectedIndex else { return }
        let newIndex = selectedIndex + delta
        guard dueProjects.indices.contains(newIndex) else { return }
        selection = dueProjects[newIndex].id
    }

    /// Advances to whichever project is next in the (pre-mutation) queue —
    /// computed before marking reviewed, since marking it changes
    /// dueProjects (the just-reviewed project drops out immediately).
    private func markSelectedReviewed() {
        guard let selection, let project = allProjects.first(where: { $0.id == selection }) else { return }
        let orderedIDs = dueProjects.map(\.id)
        guard let index = orderedIDs.firstIndex(of: selection) else { return }
        project.lastReviewedAt = Date()
        project.updatedAt = Date()
        let remainingIDs = orderedIDs.filter { $0 != selection }
        self.selection = index < remainingIDs.count ? remainingIDs[index] : remainingIDs.last
    }
}
