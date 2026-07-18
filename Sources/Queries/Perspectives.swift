import Foundation

enum Perspective: Hashable {
    case inbox
    case today
    case flagged
    case projects
    case project(UUID)
    case tag(UUID)
}

enum Perspectives {
    static func tasks(for perspective: Perspective, allTasks: [TaskItem], allTaskTags: [TaskTag]) -> [TaskItem] {
        let filtered: [TaskItem]
        switch perspective {
        case .inbox:
            filtered = allTasks.filter { $0.projectID == nil && !$0.completed }
        case .today:
            let startOfToday = Calendar.current.startOfDay(for: Date())
            guard let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday) else {
                filtered = []
                break
            }
            filtered = allTasks.filter { task in
                guard !task.completed else { return false }
                if let due = task.dueDate, due < endOfToday { return true }
                if let defer_ = task.deferDate, defer_ < endOfToday { return true }
                return false
            }
        case .flagged:
            filtered = allTasks.filter { $0.flagged && !$0.completed }
        case .projects:
            filtered = []
        case .project(let projectID):
            filtered = allTasks.filter { $0.projectID == projectID }
        case .tag(let tagID):
            let taskIDs = Set(allTaskTags.filter { $0.tagID == tagID }.map(\.taskID))
            filtered = allTasks.filter { taskIDs.contains($0.id) }
        }
        return filtered.sorted(by: taskSortOrder)
    }

    static func tags(for task: TaskItem, allTags: [Tag], allTaskTags: [TaskTag]) -> [Tag] {
        let tagIDs = Set(allTaskTags.filter { $0.taskID == task.id }.map(\.tagID))
        return allTags.filter { tagIDs.contains($0.id) }
    }

    private static func taskSortOrder(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        if lhs.completed != rhs.completed {
            return !lhs.completed && rhs.completed
        }
        let lhsDue = lhs.dueDate ?? .distantFuture
        let rhsDue = rhs.dueDate ?? .distantFuture
        if lhsDue != rhsDue {
            return lhsDue < rhsDue
        }
        return lhs.createdAt < rhs.createdAt
    }
}
