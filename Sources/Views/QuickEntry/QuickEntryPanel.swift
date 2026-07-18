import SwiftUI
import SwiftData

struct QuickEntryPanel: View {
    let defaultProjectID: UUID?
    var onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var title: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Task")
                .font(.headline)
            TextField("Task title", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(commit)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 360)
        .onAppear { isFocused = true }
    }

    private func commit() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        modelContext.insert(TaskItem(title: trimmed, projectID: defaultProjectID))
        onDismiss()
    }
}
