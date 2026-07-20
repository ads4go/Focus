import SwiftUI
import SwiftData

struct TaskListView: View {
    let perspective: Perspective
    let title: String
    @Binding var selectedTaskID: UUID?

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil })
    private var allTasks: [TaskItem]
    @Query(filter: #Predicate<TaskTag> { $0.deletedAt == nil })
    private var allTaskTags: [TaskTag]
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.name)
    private var allProjects: [Project]

    @State private var subtaskParent: TaskItem?
    @State private var isAddingInboxTask = false

    private var nodes: [TaskNode] {
        Perspectives.taskTree(for: perspective, allTasks: allTasks, allTaskTags: allTaskTags)
    }

    /// Mirrors RailItem.tint so a perspective's task list carries the same
    /// accent color as its rail entry (Project/Tag detail lists use the
    /// rail color for the whole category rather than a per-item color).
    private var accentColor: Color {
        switch perspective {
        case .inbox: return .purple
        case .flagged: return .orange
        case .projects, .project: return .blue
        case .tag: return .pink
        }
    }

    /// A project breadcrumb only makes sense where tasks from multiple
    /// projects are mixed together — Inbox tasks have no project by
    /// definition, and a single project's own view makes it redundant.
    private var showsProjectBreadcrumb: Bool {
        switch perspective {
        case .flagged, .tag: return true
        case .inbox, .projects, .project: return false
        }
    }

    private var itemCountLabel: String {
        let count = nodes.count
        let noun: String
        switch perspective {
        case .inbox: noun = "inbox item"
        case .flagged: noun = "flagged item"
        case .projects, .project: noun = "action"
        case .tag: noun = "item"
        }
        return "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(accentColor)
                    Text(itemCountLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if perspective == .inbox {
                    Button {
                        isAddingInboxTask = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New Inbox Task")
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 6)

            // `List(data, children:)` — the tree convenience initializer —
            // doesn't support `.onMove`, and `.dropDestination` inside a List
            // doesn't fire on macOS, so nested drag-to-reorder needs manual
            // ForEach+DisclosureGroup recursion (via TaskRow, a real
            // recursive View type) with `.onMove` at each level.
            List(selection: $selectedTaskID) {
                ForEach(nodes) { node in
                    TaskRow(
                        node: node,
                        selectedTaskID: selectedTaskID,
                        allProjects: allProjects,
                        modelContext: modelContext,
                        showsProjectBreadcrumb: showsProjectBreadcrumb,
                        onAddSubtask: { subtaskParent = $0 }
                    )
                }
                .onMove { offsets, destination in
                    Mutations.reorder(nodes.map(\.task), fromOffsets: offsets, toOffset: destination)
                }
            }
            .listStyle(.inset)
            .overlay {
                if nodes.isEmpty {
                    ContentUnavailableView("No Tasks", systemImage: "checkmark.circle")
                }
            }
        }
        // Deliberately no .navigationTitle: on macOS, NavigationSplitView
        // surfaces a content/detail column's navigationTitle as a second,
        // redundant plain-text title crammed into the toolbar above the
        // custom colored header below it — OmniFocus doesn't show a
        // duplicate title like that, only the styled header.
        .sheet(item: $subtaskParent) { parent in
            QuickEntryPanel(defaultProjectID: parent.projectID, parentTaskID: parent.id) {
                subtaskParent = nil
            }
        }
        .sheet(isPresented: $isAddingInboxTask) {
            QuickEntryPanel(defaultProjectID: nil, parentTaskID: nil) {
                isAddingInboxTask = false
            }
        }
    }
}

/// A task row that recursively renders its own subtasks — a real `View`
/// struct rather than a function, since a function returning `some View`
/// can't call itself (the opaque type would reference itself).
private struct TaskRow: View {
    let node: TaskNode
    let selectedTaskID: UUID?
    let allProjects: [Project]
    let modelContext: ModelContext
    let showsProjectBreadcrumb: Bool
    let onAddSubtask: (TaskItem) -> Void

    var body: some View {
        if let children = node.children {
            DisclosureGroup {
                ForEach(children) { child in
                    TaskRow(
                        node: child,
                        selectedTaskID: selectedTaskID,
                        allProjects: allProjects,
                        modelContext: modelContext,
                        showsProjectBreadcrumb: showsProjectBreadcrumb,
                        onAddSubtask: onAddSubtask
                    )
                }
                .onMove { offsets, destination in
                    Mutations.reorder(children.map(\.task), fromOffsets: offsets, toOffset: destination)
                }
            } label: {
                rowContent
            }
        } else {
            rowContent
        }
    }

    private var projectName: String? {
        guard showsProjectBreadcrumb, let projectID = node.task.projectID else { return nil }
        return allProjects.first { $0.id == projectID }?.name
    }

    private var rowContent: some View {
        let task = node.task
        return TaskRowView(task: task, isSelected: task.id == selectedTaskID, projectName: projectName) {
            Mutations.toggleCompleted(task, in: modelContext)
        }
        .tag(task.id)
        // Without this, DisclosureGroup's label flattens the row (including
        // the checkbox button) into a single generic accessibility element
        // whenever the row has children — this keeps the checkbox and title
        // independently reachable for VoiceOver on parent rows too.
        .accessibilityElement(children: .contain)
        .contextMenu {
            Button("Add Subtask") {
                onAddSubtask(task)
            }
            Button("Duplicate") {
                Mutations.duplicateTask(task, in: modelContext)
            }
            Divider()
            Button(task.flagged ? "Unflag" : "Flag") {
                task.flagged.toggle()
                task.updatedAt = Date()
            }
            Button(task.completed ? "Mark Incomplete" : "Complete") {
                Mutations.toggleCompleted(task, in: modelContext)
            }
            Menu("Move to Project") {
                Button("Inbox") {
                    task.projectID = nil
                    task.updatedAt = Date()
                }
                ForEach(allProjects) { project in
                    Button(project.name) {
                        task.projectID = project.id
                        task.updatedAt = Date()
                    }
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                Mutations.deleteTask(task, in: modelContext)
            }
        }
    }
}
