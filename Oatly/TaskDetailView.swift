import SwiftUI

struct TaskDetailView: View {
    let task: OTTask?
    let onStatusChange: () -> Void
    @EnvironmentObject var store: TaskStore
    @State private var bodyText = ""
    @State private var pressedStatus: String?

    private let buttonEmojis: [String: String] = [
        "hot": "🔥", "warm": "⛅", "cool": "❄️", "done": "✅", "dropped": "💧"
    ]
    private let allStatuses = ["hot", "warm", "cool", "done", "dropped"]
    
    private func statusColour(_ s: String) -> Color {
        switch s {
        case "hot":     return .red
        case "warm":    return .orange
        case "cool":    return .blue
        case "done":    return .green
        case "dropped": return .gray
        default:        return .secondary
        }
    }

    private func cleanBody(_ raw: String) -> String {
        raw.components(separatedBy: "\n")
            .filter { !$0.contains("BUTTON[") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Group {
            if let task = task {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        HStack(alignment: .firstTextBaseline) {
                            Text(task.name)
                                .font(.title2)
                                .fontWeight(.semibold)
                            Spacer()
                            Button("🔗 Obsidian") {
                                let stem = task.fileURL.deletingPathExtension().lastPathComponent
                                let encoded = stem.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? stem
                                if let url = URL(string: "obsidian://open?vault=DTObs&file=\(encoded)") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.purple.opacity(0.12))
                            .foregroundColor(.purple)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.purple.opacity(0.4), lineWidth: 1))
                        }

                        HStack(spacing: 6) {
                            ForEach(allStatuses, id: \.self) { s in
                                let emoji = buttonEmojis[s] ?? ""
                                Button("\(emoji) \(s.capitalized)") {
                                    pressedStatus = s
                                    TaskParser.updateStatus(fileURL: task.fileURL, newStatus: s)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        pressedStatus = nil
                                    }
                                    onStatusChange()
                                }
                                .buttonStyle(.borderless)
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(s == task.status ? statusColour(s).opacity(0.2) : Color.clear)
                                .foregroundColor(statusColour(s))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(statusColour(s).opacity(0.4), lineWidth: 1))
                                .scaleEffect(pressedStatus == s ? 0.88 : 1.0)
                                .animation(.spring(duration: 0.2), value: pressedStatus)
                            }
                        }

                        Divider()

                        
                        TextEditor(text: $bodyText)
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(minHeight: 200)
                            .scrollContentBackground(.hidden)
                            .background(Color(NSColor.controlBackgroundColor))
                            .onChange(of: bodyText) { _, newValue in
                                TaskParser.updateBody(fileURL: task.fileURL, newBody: newValue)
                            }

                        
                        .buttonStyle(.borderless)
                        .foregroundColor(Color(red: 48/255, green: 95/255, blue: 188/255))

                        Spacer()
                    }
                    .padding(20)
                }
                .onAppear { bodyText = cleanBody(task.body) }
                .onChange(of: task.id) { _, _ in bodyText = cleanBody(task.body) }

            } else {
                VStack {
                    Text("Select a task")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}
