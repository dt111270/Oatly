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

    var body: String
    var rawFrontmatter: [(key: String, value: String)]

    static func == (lhs: OTTask, rhs: OTTask) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
