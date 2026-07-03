import Foundation

struct OTTaskJSON: Codable, Hashable {
    let name: String
    let status: String
    let role: String
    let due: String?
    let nonNegotiable: Bool
    let body: String
    let source: String?
    let filepath: String?
}

struct OTTasksPayload: Codable, Hashable {
    let updated: String
    let tasks: [OTTaskJSON]
}
