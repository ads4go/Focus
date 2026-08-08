import SwiftUI
import SwiftData

/// The iPhone Forecast tab — horizontal day-strip (tap to filter) plus a
/// date-grouped task list below. The date-grouping algorithm (DayGroup,
/// DateSection, dayID, overdueTasks/upcomingGroups/filteredDateSections,
/// sectionTitle) is ported verbatim from ForecastView.swift's logic; only
/// the presentation is rewritten (native List/Section instead of
/// TaskRowView/SectionHeaderRow, no NSColor).
struct ForecastScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil && !$0.completed })
    private var incompleteTasks: [TaskItem]
    @Query(filter: #Predicate<Tag> { $0.deletedAt == nil }, sort: \Tag.name)
    private var allTags: [Tag]
    @Query(filter: #Predicate<TaskTag> { $0.deletedAt == nil })
    private var allTaskTags: [TaskTag]

    @State private var selectedCalendarDate: Date?
    /// Drives a sheet-presented TaskEditSheet — matches Inbox/
    /// ProjectTaskListScreen's identical choice so tapping an action item
    /// looks and behaves the same everywhere in the app.
    @State private var selectedTaskForDetail: TaskItem?

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: Date()) }
    private let stripDayCount = 3

    private struct DayGroup: Identifiable {
        let date: Date
        let tasks: [TaskItem]
        var id: TimeInterval { date.timeIntervalSince1970 }
    }

    private struct DateSection: Identifiable {
        let id: String
        let title: String
        let date: Date?
        let tasks: [TaskItem]
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

    private func dayID(for date: Date) -> String {
        String(calendar.startOfDay(for: date).timeIntervalSince1970)
    }

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
        if sel < today {
            return dateSections.filter { $0.id == "past" }
        }
        if let lastStripDay = stripDays.last, sel > lastStripDay {
            return dateSections.filter { section in
                guard let date = section.date else { return false }
                return date > lastStripDay
            }
        }
        return dateSections.filter { section in
            guard let sectionDate = section.date else { return false }
            return calendar.isDate(sectionDate, inSameDayAs: sel)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            strip
            Divider()
            groupedList
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Real nav bar toolbar item, matching Inbox/Projects' identical
            // conversion, instead of the custom big-title header row this
            // used to be.
            ToolbarItem(placement: .principal) {
                Text("Forecast")
                    .font(.headline)
                    .foregroundStyle(PerspectiveTint.forecast)
            }
        }
        .sheet(item: $selectedTaskForDetail) { task in
            NavigationStack {
                TaskEditSheet(task: task, tint: PerspectiveTint.forecast)
                    .navigationTitle("Action")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { selectedTaskForDetail = nil }
                        }
                    }
            }
        }
    }

    // MARK: - Summary strip

    private var strip: some View {
        HStack(spacing: 4) {
            let pastSelected = selectedCalendarDate.map { $0 < today } ?? false
            stripTile(label: "Past", count: overdueTasks.count, isSelected: pastSelected) {
                selectedCalendarDate = pastSelected ? nil : .distantPast
            }
            ForEach(stripDays, id: \.self) { day in
                let daySelected = selectedCalendarDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false
                stripTile(label: stripLabel(for: day), count: count(dueOn: day), isSelected: daySelected) {
                    selectedCalendarDate = daySelected ? nil : calendar.startOfDay(for: day)
                }
            }
            let futureSelected = selectedCalendarDate.map { sel -> Bool in
                guard let last = stripDays.last else { return false }
                return sel > last
            } ?? false
            stripTile(label: "Future", count: futureCount, isSelected: futureSelected) {
                selectedCalendarDate = futureSelected ? nil : .distantFuture
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    private func stripTile(label: String, count: Int, isSelected: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .lineLimit(1)
                Text("\(count)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : (count > 0 ? .primary : .secondary))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                isSelected ? PerspectiveTint.forecast : Color.secondary.opacity(0.15),
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

    private var groupedList: some View {
        List {
            ForEach(filteredDateSections) { section in
                Section(section.title) {
                    ForEach(section.tasks) { task in
                        Button {
                            selectedTaskForDetail = task
                        } label: {
                            MobileTaskRow(
                                task: task,
                                tagNames: Perspectives.tags(for: task, allTags: allTags, allTaskTags: allTaskTags).map(\.name),
                                onToggleComplete: { Mutations.toggleCompleted(task, in: modelContext) }
                            )
                        }
                        .buttonStyle(RowPressHighlightStyle(tint: PerspectiveTint.forecast))
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 16))
                    }
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 16)
        .overlay {
            if filteredDateSections.isEmpty {
                ContentUnavailableView("Nothing Due", systemImage: "calendar")
            }
        }
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
