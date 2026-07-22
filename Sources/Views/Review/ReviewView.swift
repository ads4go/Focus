import SwiftUI
import SwiftData

/// The browse column for the Review perspective: projects due for a periodic
/// check-in, paged one at a time with a "Mark Reviewed" action that advances
/// to the next due project — matching OmniFocus's Review workflow.
struct ReviewView: View {
    let onSelectProject: (UUID) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.sortOrder)
    private var allProjects: [Project]

    @State private var selection: UUID?

    private var dueProjects: [Project] {
        allProjects
            .filter(\.isDueForReview)
            .sorted { ($0.nextReviewDate ?? .distantPast) < ($1.nextReviewDate ?? .distantPast) }
    }

    private var selectedIndex: Int? {
        guard let selection else { return nil }
        return dueProjects.firstIndex { $0.id == selection }
    }

    var body: some View {
        // Deliberately no header (matching ProjectListView/TagListView) —
        // the paging chevrons and due-count that used to live in one move
        // to the toolbar below, alongside "Mark Reviewed".
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selection) {
                ForEach(dueProjects) { project in
                    row(for: project)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.inset)
            .padding(.leading, -6)
            .padding(.trailing, -10)
            .overlay {
                if dueProjects.isEmpty {
                    ContentUnavailableView("Nothing Due for Review", systemImage: "checkmark.seal")
                }
            }
        }
        .onChange(of: selection) { _, newValue in
            if let newValue {
                onSelectProject(newValue)
            }
        }
        .onAppear {
            if selection == nil {
                selection = dueProjects.first?.id
            }
        }
        .toolbar {
            ToolbarItem {
                Button { selectAdjacent(-1) } label: { Image(systemName: "chevron.up") }
                    .disabled((selectedIndex ?? 0) <= 0)
            }
            ToolbarItem {
                Button { selectAdjacent(1) } label: { Image(systemName: "chevron.down") }
                    .disabled(selectedIndex.map { $0 >= dueProjects.count - 1 } ?? true)
            }
            ToolbarItem {
                Button("Mark Reviewed", action: markSelectedReviewed)
                    .disabled(selection == nil)
            }
        }
    }

    private func row(for project: Project) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                EditableNameText(name: nameBinding(for: project))
            }
            Text("\(intervalLabel(project)) · \(lastReviewedLabel(project))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Menu(intervalLabel(project)) {
                Button("Daily") { setInterval(project, 1) }
                Button("Weekly") { setInterval(project, 7) }
                Button("Monthly") { setInterval(project, 30) }
                Button("Never") { setInterval(project, nil) }
            }
            .menuStyle(.borderlessButton)
            .font(.caption2)
            .fixedSize()
        }
        .tag(project.id)
    }

    private func nameBinding(for project: Project) -> Binding<String> {
        Binding(
            get: { project.name },
            set: { project.name = $0; project.updatedAt = Date() }
        )
    }

    private func intervalLabel(_ project: Project) -> String {
        switch project.reviewIntervalDays {
        case nil: return "No review"
        case 1: return "Review daily"
        case 7: return "Review weekly"
        case 30: return "Review monthly"
        case let days?: return "Review every \(days) days"
        }
    }

    private func lastReviewedLabel(_ project: Project) -> String {
        guard let date = project.lastReviewedAt else { return "never reviewed" }
        return "last reviewed \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    private func setInterval(_ project: Project, _ days: Int?) {
        project.reviewIntervalDays = days
        project.updatedAt = Date()
    }

    private func selectAdjacent(_ delta: Int) {
        guard let selectedIndex else { return }
        let newIndex = selectedIndex + delta
        guard dueProjects.indices.contains(newIndex) else { return }
        selection = dueProjects[newIndex].id
    }

    /// Advances to whichever project is next in the (pre-mutation) queue —
    /// computed before marking reviewed, since marking it changes
    /// `dueProjects` (the just-reviewed project drops out immediately).
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
