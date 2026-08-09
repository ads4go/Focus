import SwiftUI
import SwiftData

struct ProjectDetailView: View {
    @Bindable var project: Project

    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSessionStore.self) private var authStore
    @Query(filter: #Predicate<Tag> { $0.deletedAt == nil }, sort: \Tag.name)
    private var allTags: [Tag]
    @Query(filter: #Predicate<ProjectTag> { $0.deletedAt == nil })
    private var allProjectTags: [ProjectTag]
    @Query(filter: #Predicate<ProjectShare> { $0.deletedAt == nil })
    private var allProjectShares: [ProjectShare]

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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TextField("Title", text: $project.name)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                    .onChange(of: project.name) { touch() }

                statusSection
                // tagsSection hidden — uncomment to restore
                // Defer date hidden — uncomment to restore
                // OptionalDateField(label: "Defer", date: deferBinding, touch: touch)
                OptionalDateField(label: "Due", date: dueBinding, touch: touch)
                notesSection
                if isOwner {
                    sharedWithSection
                }

                HStack {
                    Spacer()
                    Menu {
                        if isOwner {
                            Button("Share Project…") {
                                shareErrorMessage = nil
                                isSharingProject = true
                            }
                            Divider()
                        }
                        Button("Delete Project", role: .destructive) {
                            Mutations.deleteProject(project, in: modelContext)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
        .alert("Share Project", isPresented: $isSharingProject) {
            TextField("Username", text: $shareUsername)
            Button("Cancel", role: .cancel) { shareUsername = "" }
            Button("Share") { Task { await commitShare() } }
        }
    }

    // MARK: - Sharing

    private var sharedWithSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shared With").font(.headline)
            if activeShares.isEmpty {
                Text("Not shared with anyone.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(activeShares) { share in
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
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

    // MARK: - Sections

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Status").font(.headline)
                Spacer()
                Text(project.isCompleted ? "Completed" : "Active")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Picker("", selection: completedBinding) {
                    Image(systemName: "play.fill").tag(false)
                    Image(systemName: "checkmark").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 160)

                // Flag button hidden — uncomment to restore
                // Button {
                //     project.flagged.toggle()
                //     touch()
                // } label: {
                //     Image(systemName: project.flagged ? "flag.fill" : "flag")
                // }
                // .buttonStyle(.bordered)
                // .tint(project.flagged ? .orange : .secondary)
            }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tags").font(.headline)
            ProjectTagPickerView(project: project, allTags: allTags, allProjectTags: allProjectTags)
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes").font(.headline)
            TextField("Add notes…", text: $project.notes, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...8)
                .onChange(of: project.notes) { touch() }
        }
    }

    // MARK: - Bindings

    private func touch() { project.updatedAt = Date() }

    private var completedBinding: Binding<Bool> {
        Binding(
            get: { project.isCompleted },
            set: { project.isCompleted = $0; touch() }
        )
    }

    private var dueBinding: Binding<Date?> {
        Binding(get: { project.dueDate }, set: { project.dueDate = $0; touch() })
    }

    private var deferBinding: Binding<Date?> {
        Binding(get: { project.deferDate }, set: { project.deferDate = $0; touch() })
    }
}

// MARK: - Tag picker for projects

private struct ProjectTagPickerView: View {
    let project: Project
    let allTags: [Tag]
    let allProjectTags: [ProjectTag]

    @Environment(\.modelContext) private var modelContext

    private var assignedTagIDs: Set<UUID> {
        Set(allProjectTags.filter { $0.projectID == project.id }.map(\.tagID))
    }
    private var assignedTags: [Tag] { allTags.filter { assignedTagIDs.contains($0.id) } }
    private var unassignedTags: [Tag] { allTags.filter { !assignedTagIDs.contains($0.id) } }

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(assignedTags) { tag in
                ProjectTagChip(name: tag.name) {
                    Mutations.removeTag(tag, fromProject: project, in: modelContext)
                }
            }
            if !unassignedTags.isEmpty {
                Menu {
                    ForEach(unassignedTags) { tag in
                        Button(tag.name) {
                            Mutations.addTag(tag, toProject: project, in: modelContext)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Color.secondary.opacity(0.15), in: .circle)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        if allTags.isEmpty {
            Text("No tags yet — add one from the sidebar.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ProjectTagChip: View {
    let name: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(name).font(.caption.weight(.medium))
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.pink)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.pink.opacity(0.15), in: .capsule)
    }
}
