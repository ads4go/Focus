import SwiftUI
import SwiftData

/// The calendar portion of the Forecast perspective: the mini month
/// calendar. The header, day strip, and task list all live in the adjacent
/// detail pane (ForecastView).
struct ForecastCalendarView: View {
    @Binding var selectedDate: Date?

    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil && !$0.completed })
    private var incompleteTasks: [TaskItem]

    @State private var visibleMonth: Date = Date()

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            monthCalendar
            Spacer()
        }
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
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func dayCell(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let dueCount = count(dueOn: day)
        return Button {
            if isSelected {
                selectedDate = nil
            } else {
                selectedDate = day
            }
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.caption)
                    .foregroundStyle(isToday || isSelected ? .white : .primary)
                    .frame(width: 20, height: 20)
                    .background(
                        isSelected ? Color.accentColor : (isToday ? Color.red : Color.clear),
                        in: Circle()
                    )
                Circle()
                    .fill(dueCount > 0 ? Color.red.opacity(0.7) : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(height: 28)
        }
        .buttonStyle(.plain)
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

    private func count(dueOn day: Date) -> Int {
        incompleteTasks.filter { task in
            guard let due = task.dueDate else { return false }
            return calendar.isDate(due, inSameDayAs: day)
        }.count
    }
}
