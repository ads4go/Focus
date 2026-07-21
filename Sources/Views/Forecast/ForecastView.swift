import SwiftUI
import SwiftData

/// The task-list portion of the Forecast perspective: header, day strip, and
/// date-grouped tasks with project breadcrumbs. The mini month calendar
/// lives in ForecastCalendarView (the left pane).
struct ForecastView: View {
    @Binding var selectedTaskID: UUID?

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil && !$0.completed })
    private var incompleteTasks: [TaskItem]
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.name)
    private var allProjects: [Project]

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: Date()) }
    private let stripDayCount = 4

    private struct DayGroup: Identifiable {
        let date: Date
        let tasks: [TaskItem]
        var id: TimeInterval { date.timeIntervalSince1970 }
    }

    /// A collapsible section in the grouped list ("Past", "Today — …", …) —
    /// Past and each day group are unified into this one shape so the list
    /// can render them as a single run of DisclosureGroups with dividers
    /// only *between* sections, not between rows within one. Carries `date`
    /// (nil for Past) so filteredDateSections can match it against the
    /// strip's selected day/Future filters.
    private struct DateSection: Identifiable {
        let id: String
        let title: String
        let date: Date?
        let tasks: [TaskItem]
    }

    /// Collapsed-state per section, keyed by DateSection.id — absent means
    /// expanded, so newly-appearing sections (e.g. a task becomes due
    /// tomorrow) default to open rather than needing to be seen once first.
    @State private var collapsedSectionIDs: Set<String> = []

    /// Which strip tiles ("past", a day's dayID, "future") are selected —
    /// a multi-select filter over the grouped list below, mirroring the
    /// Projects/Tags left-pane filter pattern elsewhere in the app: empty
    /// means no filter (show everything).
    @State private var selectedStripIDs: Set<String> = []

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
        incompleteTasks.filter { $0.dueDate != nil }.count
    }

    /// A stable id for a calendar day, shared between a strip tile and the
    /// date-grouped section it should filter — both are computed from the
    /// same start-of-day date, so they always agree.
    private func dayID(for date: Date) -> String {
        String(calendar.startOfDay(for: date).timeIntervalSince1970)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            strip
            groupedList
        }
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
                stripTile(id: "past", label: "Past", count: overdueTasks.count)
                ForEach(stripDays, id: \.self) { day in
                    stripTile(id: dayID(for: day), label: stripLabel(for: day), count: count(dueOn: day))
                }
                stripTile(id: "future", label: "Future", count: futureCount)
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
    }

    /// A Set binding (matching Projects/Tags) rather than a single selected
    /// id — Cmd-clicking several tiles filters the list to their union.
    private func stripTile(id: String, label: String, count: Int) -> some View {
        let isSelected = selectedStripIDs.contains(id)
        return Button {
            if isSelected {
                selectedStripIDs.remove(id)
            } else {
                selectedStripIDs.insert(id)
            }
        } label: {
            VStack(spacing: 4) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isSelected ? .white : .secondary)
                Text("\(count)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : (count > 0 ? .primary : .secondary))
            }
            .frame(width: 48)
            .padding(.vertical, 8)
            .background(
                isSelected ? Color.accentColor : Color.secondary.opacity(0.1),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private func stripLabel(for day: Date) -> String {
        calendar.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.abbreviated).day())
    }

    private func count(dueOn day: Date) -> Int {
        incompleteTasks.filter { task in
            guard let due = task.dueDate else { return false }
            return calendar.isDate(due, inSameDayAs: day)
        }.count
    }

    // MARK: - Grouped task list

    private var dateSections: [DateSection] {
        var sections: [DateSection] = []
        if !overdueTasks.isEmpty {
            sections.append(DateSection(id: "past", title: "Past", date: nil, tasks: overdueTasks))
        }
        sections += upcomingGroups.map { group in
            DateSection(id: dayID(for: group.date), title: sectionTitle(for: group.date), date: group.date, tasks: group.tasks)
        }
        return sections
    }

    /// dateSections narrowed by the strip's selection — empty selection
    /// means no filter (every section), matching Projects/Tags. A "Future"
    /// tile has no single matching section id (unlike Past or a specific
    /// day), so it's matched by date instead: any day beyond the strip's
    /// last day.
    private var filteredDateSections: [DateSection] {
        guard !selectedStripIDs.isEmpty else { return dateSections }
        let lastStripDay = stripDays.last
        return dateSections.filter { section in
            if selectedStripIDs.contains(section.id) { return true }
            if selectedStripIDs.contains("future"), let date = section.date, let lastStripDay, date > lastStripDay {
                return true
            }
            return false
        }
    }

    private func isExpandedBinding(for sectionID: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedSectionIDs.contains(sectionID) },
            set: { isExpanded in
                if isExpanded {
                    collapsedSectionIDs.remove(sectionID)
                } else {
                    collapsedSectionIDs.insert(sectionID)
                }
            }
        )
    }

    private var groupedList: some View {
        List(selection: $selectedTaskID) {
            ForEach(Array(filteredDateSections.enumerated()), id: \.element.id) { index, section in
                // SectionHeaderRow (not a real DisclosureGroup) so each
                // date group gets its own collapse arrow to the left of
                // its title, matching OmniFocus, without macOS collapsing
                // the whole section into one selectable row the way an
                // actual DisclosureGroup with a custom style does inside a
                // List — see SectionHeaderRow's doc comment.
                let expanded = isExpandedBinding(for: section.id)
                SectionHeaderRow(isExpanded: expanded) {
                    Text(section.title)
                        .font(.headline)
                }
                .listRowSeparator(.hidden)
                if expanded.wrappedValue {
                    ForEach(Array(section.tasks.enumerated()), id: \.element.id) { rowIndex, task in
                        row(for: task)
                            .listRowSeparator(.hidden)
                            .padding(.top, rowIndex == 0 ? 6 : 0)
                    }
                    .padding(.leading, sectionHeaderLabelIndent)
                }
                if index < filteredDateSections.count - 1 {
                    Divider()
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if filteredDateSections.isEmpty {
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
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle((task.dueDate ?? .distantFuture) < Date() ? .red : .primary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                EditableNameText(name: titleBinding(for: task))
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

    private func titleBinding(for task: TaskItem) -> Binding<String> {
        Binding(
            get: { task.title },
            set: { task.title = $0; task.updatedAt = Date() }
        )
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
