import SwiftUI
import SwiftData

/// The task-list portion of the Forecast perspective: header, day strip, and
/// date-grouped tasks with project breadcrumbs. The mini month calendar
/// lives in ForecastCalendarView (the left pane).
struct ForecastView: View {
    @Binding var selectedTaskID: UUID?
    @Binding var selectedCalendarDate: Date?

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil && !$0.completed })
    private var incompleteTasks: [TaskItem]
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.name)
    private var allProjects: [Project]
    @Query(filter: #Predicate<Tag> { $0.deletedAt == nil }, sort: \Tag.name)
    private var allTags: [Tag]
    @Query(filter: #Predicate<TaskTag> { $0.deletedAt == nil })
    private var allTaskTags: [TaskTag]

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
            strip
            Divider()
            groupedList
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Forecast")
                .font(.largeTitle.bold())
                .foregroundStyle(.red)
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    // MARK: - Summary strip

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                let pastSelected = selectedCalendarDate.map { $0 < today } ?? false
                stripTile(
                    label: "Past", count: overdueTasks.count, isSelected: pastSelected,
                    onTap: { selectedCalendarDate = pastSelected ? nil : .distantPast }
                )
                ForEach(stripDays, id: \.self) { day in
                    let daySelected = selectedCalendarDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false
                    stripTile(
                        label: stripLabel(for: day), count: count(dueOn: day), isSelected: daySelected,
                        onTap: { selectedCalendarDate = daySelected ? nil : calendar.startOfDay(for: day) }
                    )
                }
                let futureSelected = selectedCalendarDate.map { sel -> Bool in
                    guard let last = stripDays.last else { return false }
                    return sel > last
                } ?? false
                stripTile(
                    label: "Future", count: futureCount, isSelected: futureSelected,
                    onTap: { selectedCalendarDate = futureSelected ? nil : .distantFuture }
                )
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
    }

    private func stripTile(label: String, count: Int, isSelected: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
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

    private var filteredDateSections: [DateSection] {
        guard let sel = selectedCalendarDate else { return dateSections }
        // Any date before today (including distantPast sentinel) → Past section.
        if sel < today {
            return dateSections.filter { $0.id == "past" }
        }
        // Any date beyond the strip (including distantFuture sentinel) → future sections.
        if let lastStripDay = stripDays.last, sel > lastStripDay {
            return dateSections.filter { section in
                guard let date = section.date else { return false }
                return date > lastStripDay
            }
        }
        // Specific day within the strip range.
        return dateSections.filter { section in
            guard let sectionDate = section.date else { return false }
            return calendar.isDate(sectionDate, inSameDayAs: sel)
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
        let projectName = allProjects.first { $0.id == task.projectID }?.name
        let tagNames = Perspectives.tags(for: task, allTags: allTags, allTaskTags: allTaskTags).map(\.name)
        return TaskRowView(
            task: task,
            isSelected: task.id == selectedTaskID,
            projectName: projectName,
            tagNames: tagNames,
            allProjects: allProjects,
            allTags: allTags,
            allTaskTags: allTaskTags
        ) {
            Mutations.toggleCompleted(task, in: modelContext)
        }
        .tag(task.id)
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
