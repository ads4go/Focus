import SwiftUI
import SwiftData

struct ProjectListView: View {
    /// Called with the full selection set on every change, including back
    /// down to empty — the caller treats an empty set as "no filter, show
    /// everything" rather than "nothing to show" (see Perspective.projects).
    let onSelectionChange: (Set<UUID>) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.sortOrder)
    private var projects: [Project]

    @State private var isAddingProject = false
    @State private var newProjectName = ""
    /// A Set binding (not a single UUID?) is what gives List its native
    /// multi-select — Cmd/Shift-click work for free, matching Finder.
    @State private var selection: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // A selection binding (matching TaskListView, where drag-reorder
            // is confirmed working) — macOS's native list drag-reorder ties
            // into the same row-selection plumbing, so a List with no
            // selection at all doesn't reliably initiate reorder drags.
            List(selection: $selection) {
                ForEach(projects) { project in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(.blue)
                        EditableNameText(name: nameBinding(for: project))
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
                    .listRowSeparator(.hidden)
                }
                .onMove { offsets, destination in
                    Mutations.reorder(projects, fromOffsets: offsets, toOffset: destination)
                }
                if isAddingProject {
                    TextField("Project name", text: $newProjectName)
                        .onSubmit(commitNewProject)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.inset)
            .overlay {
                if projects.isEmpty && !isAddingProject {
                    ContentUnavailableView("No Projects", systemImage: "folder")
                }
            }

            // Bottom-left "+" (no header row above the list anymore) —
            // matches OmniFocus's own placement for adding a new project.
            HStack {
                Button {
                    isAddingProject = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New Project")
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        // Deliberately no .navigationTitle — this view is embedded inline
        // inside the content column now, not a standalone NavigationSplitView
        // column; see TaskListView's comment for why that matters on macOS.
        .onChange(of: selection) { _, newValue in
            onSelectionChange(newValue)
        }
    }

    private func nameBinding(for project: Project) -> Binding<String> {
        Binding(
            get: { project.name },
            set: { project.name = $0; project.updatedAt = Date() }
        )
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
