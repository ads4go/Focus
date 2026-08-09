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
    /// True only for the brand-new-project creation flow (ProjectsScreen's
    /// "+" menu) — auto-focuses the title field, matching QuickEntrySheet's
    /// identical onAppear for new actions. Left false when opening an
    /// existing project to edit, where stealing focus on every open would
    /// be unwelcome.
    var isNewProject: Bool = false

    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSessionStore.self) private var authStore
    @Query(filter: #Predicate<Folder> { $0.deletedAt == nil }, sort: \Folder.name)
    private var allFolders: [Folder]
    @Query(filter: #Predicate<ProjectShare> { $0.deletedAt == nil })
    private var allProjectShares: [ProjectShare]
    @State private var isShowingDueDateCalendar = false
    @FocusState private var isTitleFocused: Bool

    @State private var isSharingProject = false
    @State private var shareUsername = ""
    @State private var shareErrorMessage: String?
    @State private var isSubmittingShare = false

    // No local ownerID field exists on Project — see Perspectives.isProjectShared's
    // doc comment for why this is the only way to tell "mine" from "shared with me".
    private var isOwner: Bool {
        !Perspectives.isProjectShared(project, allShares: allProjectShares, currentUserID: authStore.currentUserID)
    }
    private var activeShares: [ProjectShare] {
        Perspectives.activeShares(for: project, allShares: allProjectShares)
    }

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
            if isOwner {
                sharedWithSection
            }
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .onAppear {
            if isNewProject { isTitleFocused = true }
        }
        .alert("Share Project", isPresented: $isSharingProject) {
            TextField("Username", text: $shareUsername)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { shareUsername = "" }
            Button("Share") { Task { await commitShare() } }
        }
    }

    // MARK: - Sharing

    private var sharedWithSection: some View {
        Section("Shared With") {
            ForEach(activeShares) { share in
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundStyle(tint)
                    Text(share.sharedWithUsername)
                    Spacer()
                    Button {
                        Mutations.unshareProject(share, in: modelContext)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                shareErrorMessage = nil
                isSharingProject = true
            } label: {
                Label(isSubmittingShare ? "Sharing…" : "Share Project…", systemImage: "person.badge.plus")
            }
            .disabled(isSubmittingShare)
            if let shareErrorMessage {
                Text(shareErrorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }

    private func commitShare() async {
        let trimmed = shareUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        shareUsername = ""
        guard !trimmed.isEmpty else { return }
        isSubmittingShare = true
        shareErrorMessage = nil
        defer { isSubmittingShare = false }
        do {
            guard let userID = try await UserLookup.userID(forUsername: trimmed) else {
                shareErrorMessage = "No user found with username \"\(trimmed)\"."
                return
            }
            guard userID != authStore.currentUserID else {
                shareErrorMessage = "You can't share a project with yourself."
                return
            }
            Mutations.shareProject(project, withUserID: userID, username: trimmed, in: modelContext)
        } catch {
            shareErrorMessage = error.localizedDescription
        }
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
