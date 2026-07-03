import SwiftUI

struct TaskRowView: View {
    let task: OTTaskJSON
    let isChecked: Bool
    let onCheck: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onCheck) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(isChecked ? Color.blue : Color.gray.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.blue)
                    }
                }
                .animation(.spring(duration: 0.2), value: isChecked)
            }
            .buttonStyle(.plain)

            Text(task.name)
                .font(.system(size: 13))
                .foregroundColor(isChecked ? .secondary : .primary)

            Spacer()

            if let due = task.due {
                Text(due)
                    .font(.caption)
                    .foregroundColor(dueColour(due))
            }
        }
        .padding(.vertical, 8)
    }

    private func dueColour(_ due: String) -> Color {
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        if due < today { return .red }
        if due == today { return .orange }
        return .secondary
    }
}
