import SwiftUI
import SwiftData
import UIKit

/// The iPhone's project-detail sheet, styled identically to TaskEditSheet
/// (and QuickEntrySheet before it) — same single-container Form, same
/// tap-to-open-calendar due date row. Sources/Views/Detail/ProjectDetailView.swift
/// is left untouched — it's shared with the Mac app.
struct ProjectEditSheet: View {
    @Bindable var project: Project
    var tint: Color = PerspectiveTint.projects

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Folder> { $0.deletedAt == nil }, sort: \Folder.name)
    private var allFolders: [Folder]
    @State private var isShowingDueDateCalendar = false
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Project title", text: $project.name)
                    .focused($isTitleFocused)
                    .onChange(of: project.name) { touch() }
                dueDateRow
                TextField("Add note", text: $project.notes, axis: .vertical)
                    .lineLimit(1...4)
                    .onChange(of: project.notes) { touch() }
                folderPicker
                statusRow
            }
        }
        .contentMargins(.top, 0, for: .scrollContent)
    }

    // Identical pattern to TaskEditSheet's projectPicker.
    private var folderPicker: some View {
        Menu {
            Picker("", selection: Binding(get: { project.folderID }, set: { project.folderID = $0; touch() })) {
                Text("No Folder").tag(UUID?.none)
                ForEach(allFolders) { folder in
                    Text(folder.name).tag(UUID?.some(folder.id))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.body)
                    .foregroundStyle(tint)
                Text(allFolders.first { $0.id == project.folderID }?.name ?? "No Folder")
                    .foregroundStyle(.white)
                Spacer()
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 4) {
            Image(systemName: project.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.body)
                .foregroundStyle(tint)
            Button(project.isCompleted ? "Complete" : "Active") {
                project.isCompleted.toggle()
                touch()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            Spacer()
        }
    }

    // Identical pattern to QuickEntrySheet/TaskEditSheet's dueDateRow.
    private var dueDateRow: some View {
        HStack {
            Button {
                isTitleFocused = false
                if project.dueDate == nil {
                    project.dueDate = Date()
                    touch()
                }
                isShowingDueDateCalendar = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.body)
                        .foregroundStyle(tint)
                    Text(project.dueDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Due Date")
                        .foregroundStyle(project.dueDate == nil ? Color(uiColor: .placeholderText) : Color.primary)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            Spacer()
            if project.dueDate != nil {
                Button {
                    project.dueDate = nil
                    touch()
                    isShowingDueDateCalendar = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .popover(isPresented: $isShowingDueDateCalendar, arrowEdge: .top) {
            DatePicker(
                "",
                selection: Binding(get: { project.dueDate ?? Date() }, set: { project.dueDate = $0; touch() }),
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding()
            .frame(width: 320, height: 360)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func touch() { project.updatedAt = Date() }
}
