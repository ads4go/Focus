import SwiftUI
import SwiftData

/// Left pane for the Done tab: completed projects, multi-selectable to filter
/// the middle pane's completed-task list. Empty selection = all completed tasks.
struct DoneListView: View {
    let onSelectionChange: (Set<UUID>) -> Void

    @Query(
        filter: #Predicate<Project> { $0.deletedAt == nil && $0.isCompleted },
        sort: \Project.name
    )
    private var completedProjects: [Project]

    @State private var selection: Set<UUID> = []

    private static let tint = Color(white: 0.52)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selection) {
                ForEach(completedProjects) { project in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Self.tint)
                        Text(project.name)
                        Spacer()
                    }
                    .tag(project.id)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.inset)
            .padding(.top, 12)
            .padding(.leading, -6)
            .padding(.trailing, -10)
            .overlay {
                if completedProjects.isEmpty {
                    ContentUnavailableView("No Completed Projects", systemImage: "checkmark.circle")
                }
            }
        }
        .onChange(of: selection) { _, newValue in
            onSelectionChange(newValue)
        }
    }
}
