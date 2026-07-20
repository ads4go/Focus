import SwiftUI
import SwiftData

/// The task-list portion of the Forecast perspective: date-grouped tasks with
/// project breadcrumbs. The calendar header lives in ForecastCalendarView.
struct ForecastView: View {
    @Binding var selectedTaskID: UUID?

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil && !$0.completed })
    private var incompleteTasks: [TaskItem]
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.name)
    private var allProjects: [Project]

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: Date()) }

    private struct DayGroup: Identifiable {
        let date: Date
        let tasks: [TaskItem]
        var id: TimeInterval { date.timeIntervalSince1970 }
    }

    private var overdueTasks: [TaskItem] {
        incompleteTasks
            .filter { ($0.dueDate ?? .distantFuture) < today }
            .sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
    }

    private var upcomingGroups: [DayGroup] {
        let dueTasks = incompleteTasks.filter { ($0.dueDate ?? .distantPast) >= today }
        let grouped = Dictionary(grouping: dueTasks) { calendar.startOfDay(for: $0.dueDate!) }
        return grouped.keys.sorted().map { day in
            DayGroup(date: day, tasks: grouped[day]!.sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) })
        }
    }

    var body: some View {
        groupedList
    }

    // MARK: - Grouped task list

    private var groupedList: some View {
        List(selection: $selectedTaskID) {
            if !overdueTasks.isEmpty {
                Section("Past") {
                    ForEach(overdueTasks) { task in row(for: task) }
                }
            }
            ForEach(upcomingGroups) { group in
                Section(sectionTitle(for: group.date)) {
                    ForEach(group.tasks) { task in row(for: task) }
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if overdueTasks.isEmpty && upcomingGroups.isEmpty {
                ContentUnavailableView("Nothing Due", systemImage: "calendar")
            }
        }
    }

    private func row(for task: TaskItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                Mutations.toggleCompleted(task, in: modelContext)
            } label: {
                Image(systemName: "circle")
                    .foregroundStyle((task.dueDate ?? .distantFuture) < Date() ? .red : .primary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                if let projectID = task.projectID, let project = allProjects.first(where: { $0.id == projectID }) {
                    Label(project.name, systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let due = task.dueDate {
                Text(due.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if task.flagged {
                Image(systemName: "flag.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
        .tag(task.id)
        .padding(.vertical, 2)
    }

    private func sectionTitle(for day: Date) -> String {
        if calendar.isDateInToday(day) {
            return "Today — \(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))"
        }
        if calendar.isDateInTomorrow(day) {
            return "Tomorrow — \(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))"
        }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

}
