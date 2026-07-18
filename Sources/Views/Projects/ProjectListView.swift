import SwiftUI
import SwiftData

struct ProjectListView: View {
    let onSelectProject: (UUID) -> Void

    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.name)
    private var projects: [Project]
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil })
    private var allTasks: [TaskItem]

    var body: some View {
        List {
            ForEach(projects) { project in
                Button {
                    onSelectProject(project.id)
                } label: {
                    HStack {
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
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Projects")
        .overlay {
            if projects.isEmpty {
                ContentUnavailableView("No Projects", systemImage: "folder")
            }
        }
    }

    private func remainingCount(_ project: Project) -> Int {
        allTasks.filter { $0.projectID == project.id && !$0.completed }.count
    }
}
