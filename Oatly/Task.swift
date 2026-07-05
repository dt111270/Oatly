import Foundation

struct OTTask: Identifiable, Equatable, Hashable {
    let id: URL
    let fileURL: URL

    var name: String
    var status: String
    var role: String
    var due: String?
    var source: String?
    var parent: String?
    var nonNnegotiable: Bool
    var optional: Bool
    var created: String?
    var url: String?
    /// `HH:MM`, Europe/London. Presence is the "nagging reminder" flag —
    /// if set, this task gets a repeating every-5-minutes phone reminder
    /// from `due`+`nagTime` onward instead of (not in addition to) the
    /// once-daily 07:00 reminder. See `NaggingNotificationScheduler`.
    var nagTime: String?

    var body: String
    var rawFrontmatter: [(key: String, value: String)]

    static func == (lhs: OTTask, rhs: OTTask) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
