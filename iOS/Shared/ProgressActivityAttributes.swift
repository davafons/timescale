import ActivityKit
import Foundation

struct ProgressActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var start: Date
    var end: Date
    var sessionEnd: Date
    var remaining: Bool
  }

  var period: String
}
