import SwiftUI

struct TaskRowView: View {
    let task: OTTaskJSON
    let isChecked: Bool
    let onCheck: () -> Void
    /// Hairline divider under the row — pass `false` for the last row in a
    /// card (iPhone) or when the host already draws its own separator
    /// (iPad's `List`, which shows a native separator per row already).
    var showDivider: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Redesign spec: a plain ring, no fill/checkmark glyph even
                // once done — just the border colour muting from accent to
                // a neutral grey. Matches the reference mockup exactly;
                // done tasks only ever appear here transiently anyway
                // (right after tapping, before the next refresh drops them
                // out of the filtered list), so the tick itself doesn't
                // need to read at a glance.
                Button(action: onCheck) {
                    Circle()
                        .strokeBorder(
                            isChecked ? OTPalette.textPrimary.opacity(0.2) : OTPalette.accent,
                            lineWidth: 2
                        )
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)

                titleText
                    .font(.system(size: 14))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                if let due = task.due {
                    Text(OTPalette.formattedDue(due))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(OTPalette.dueColor(due, isDone: isChecked))
                        .fixedSize()
                }
            }
            .padding(.vertical, 6.5)

            if showDivider {
                Rectangle()
                    .fill(OTPalette.divider)
                    .frame(height: 0.5)
            }
        }
    }

    /// Task name, prefixed with "⏰ HH:MM" when `nag_time` is set — a visual
    /// cue that this one's covered by an alarm and doesn't need worrying
    /// about right now. Built as one concatenated `Text` (rather than a
    /// separate view before the title) so the whole thing truncates and
    /// dims together as a single line, same as a plain title would.
    private var titleText: Text {
        let color = isChecked ? OTPalette.textPrimary.opacity(0.5) : OTPalette.textPrimary
        var text = Text("")
        if let nagTime = task.nagTime, !nagTime.isEmpty {
            text = text + Text("⏰ \(nagTime) ").foregroundColor(color)
        }
        return text + Text(task.name).foregroundColor(color)
    }
}
