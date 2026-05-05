import SwiftUI

struct NameEditSheetView: View {
    let title: String
    let placeholder: String
    let initialValue: String
    let commitTitle: String
    let allowsEmptyValue: Bool
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var value: String

    init(
        title: String,
        placeholder: String,
        initialValue: String,
        commitTitle: String,
        allowsEmptyValue: Bool = false,
        onSave: @escaping (String) -> Void
    ) {
        self.title = title
        self.placeholder = placeholder
        self.initialValue = initialValue
        self.commitTitle = commitTitle
        self.allowsEmptyValue = allowsEmptyValue
        self.onSave = onSave
        _value = State(initialValue: initialValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.headline)

            TextField(placeholder, text: $value)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(save)

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(commitTitle, action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!allowsEmptyValue && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 380)
        .onAppear {
            isFocused = true
        }
    }

    private func save() {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard allowsEmptyValue || !trimmedValue.isEmpty else {
            return
        }

        onSave(trimmedValue)
        dismiss()
    }
}
