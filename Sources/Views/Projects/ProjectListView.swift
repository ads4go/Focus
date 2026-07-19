import SwiftUI
import SwiftData

struct ProjectListView: View {
    let onSelectProject: (UUID) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.sortOrder)
    private var projects: [Project]
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil })
    private var allTasks: [TaskItem]

    @State private var isAddingProject = false
    @State private var newProjectName = ""
    @State private var selection: UUID?

    private var itemCountLabel: String {
        "\(projects.count) project\(projects.count == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Matches the bold-title + count-subtitle header every other
            // list (Inbox, Forecast, Flagged, a project/tag's own tasks)
            // uses, so this browse list doesn't look like a different app.
            VStack(alignment: .leading, spacing: 2) {
                Text("Projects")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.blue)
                Text(itemCountLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 6)

            // A selection binding (matching TaskListView, where drag-reorder
            // is confirmed working) — macOS's native list drag-reorder ties
            // into the same row-selection plumbing, so a List with no
            // selection at all doesn't reliably initiate reorder drags.
            List(selection: $selection) {
                ForEach(projects) { project in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(project.name)
                            Text("\(remainingCount(project)) remaining")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if project.isCompleted {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(project.id)
                    .contextMenu {
                        Menu("Review Interval") {
                            Button("Daily") { setReviewInterval(project, 1) }
                            Button("Weekly") { setReviewInterval(project, 7) }
                            Button("Monthly") { setReviewInterval(project, 30) }
                            Button("Never") { setReviewInterval(project, nil) }
                        }
                        Divider()
                        Button("Delete Project", role: .destructive) {
                            Mutations.deleteProject(project, in: modelContext)
                        }
                    }
                }
                .onMove { offsets, destination in
                    Mutations.reorder(projects, fromOffsets: offsets, toOffset: destination)
                }
                if isAddingProject {
                    TextField("Project name", text: $newProjectName)
                        .onSubmit(commitNewProject)
                }
            }
            .listStyle(.inset)
            .overlay {
                if projects.isEmpty && !isAddingProject {
                    ContentUnavailableView("No Projects", systemImage: "folder")
                }
            }
        }
        // Deliberately no .navigationTitle — this view is embedded inline
        // inside the content column now, not a standalone NavigationSplitView
        // column; see TaskListView's comment for why that matters on macOS.
        .onChange(of: selection) { _, newValue in
            if let newValue {
                onSelectProject(newValue)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    isAddingProject = true
                } label: {
                    Label("New Project", systemImage: "plus")
                }
            }
        }
    }

    private func remainingCount(_ project: Project) -> Int {
        allTasks.filter { $0.projectID == project.id && !$0.completed }.count
    }

    private func setReviewInterval(_ project: Project, _ days: Int?) {
        project.reviewIntervalDays = days
        project.updatedAt = Date()
    }

    private func commitNewProject() {
        let trimmed = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        newProjectName = ""
        isAddingProject = false
        guard !trimmed.isEmpty else { return }
        modelContext.insert(Project(name: trimmed))
    }
}
