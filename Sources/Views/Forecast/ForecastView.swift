import SwiftUI
import SwiftData

/// A calendar-based dashboard for due dates, matching OmniFocus's Forecast
/// perspective: a Past/Today/+days/Future summary strip, a mini month
/// calendar with per-day task-count dots, and a date-grouped task list with
/// project breadcrumbs — replacing a flat "Today" list.
struct ForecastView: View {
    @Binding var selectedTaskID: UUID?

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil && !$0.completed })
    private var incompleteTasks: [TaskItem]
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.name)
    private var allProjects: [Project]

    @State private var visibleMonth: Date = Date()

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: Date()) }
    private let stripDayCount = 4

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

    private var stripDays: [Date] {
        (0..<stripDayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    private var futureCount: Int {
        guard let lastStripDay = stripDays.last,
              let futureStart = calendar.date(byAdding: .day, value: 1, to: lastStripDay)
        else { return 0 }
        return incompleteTasks.filter { ($0.dueDate ?? .distantPast) >= futureStart }.count
    }

    private var totalDueCount: Int {
        overdueTasks.count + upcomingGroups.reduce(0) { $0 + $1.tasks.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            strip
            monthCalendar
            Divider()
            groupedList
        }
        // Deliberately no .navigationTitle — see TaskListView's comment.
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Forecast")
                .font(.largeTitle.bold())
                .foregroundStyle(.red)
            Text("\(totalDueCount) item\(totalDueCount == 1 ? "" : "s") due")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    // MARK: - Summary strip

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                stripTile(label: "Past", count: overdueTasks.count)
                ForEach(stripDays, id: \.self) { day in
                    stripTile(label: stripLabel(for: day), count: count(dueOn: day))
                }
                stripTile(label: "Future", count: futureCount)
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
    }

    private func stripTile(label: String, count: Int) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(count > 0 ? .primary : .secondary)
        }
        .frame(width: 64)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func stripLabel(for day: Date) -> String {
        calendar.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.abbreviated).day())
    }

    // MARK: - Month calendar

    private var monthCalendar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(visibleMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                Spacer()
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                ForEach(calendar.shortWeekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(Array(monthGridDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 28)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func dayCell(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        let dueCount = count(dueOn: day)
        return VStack(spacing: 2) {
            Text("\(calendar.component(.day, from: day))")
                .font(.caption)
                .foregroundStyle(isToday ? .white : .primary)
                .frame(width: 20, height: 20)
                .background(isToday ? Color.red : Color.clear, in: Circle())
            Circle()
                .fill(dueCount > 0 ? Color.red.opacity(0.7) : Color.clear)
                .frame(width: 4, height: 4)
        }
        .frame(height: 28)
    }

    private var monthGridDays: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: visibleMonth) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let daysInMonth = calendar.range(of: .day, in: .month, for: visibleMonth)?.count ?? 30
        var days: [Date?] = Array(repeating: nil, count: firstWeekday - 1)
        for offset in 0..<daysInMonth {
            days.append(calendar.date(byAdding: .day, value: offset, to: monthInterval.start))
        }
        return days
    }

    private func shiftMonth(_ delta: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: delta, to: visibleMonth) {
            visibleMonth = newMonth
        }
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

    private func count(dueOn day: Date) -> Int {
        incompleteTasks.filter { task in
            guard let due = task.dueDate else { return false }
            return calendar.isDate(due, inSameDayAs: day)
        }.count
    }
}
