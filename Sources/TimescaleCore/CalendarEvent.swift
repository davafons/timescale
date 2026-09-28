import Foundation

public struct CalendarEvent: Identifiable, Equatable, Sendable {
  public let id: Int
  public let title: String
  public let description: String?
  public let editURL: URL?
  public let start: Date
  public let end: Date
  public let allDay: Bool
  public let source: String
  public let sourceIdentifier: String?
  public let externalUID: String?
  public let stableID: String

  public init(
    id: Int,
    title: String,
    description: String? = nil,
    editURL: URL? = nil,
    start: Date,
    end: Date,
    allDay: Bool = false,
    source: String = "HEY",
    sourceIdentifier: String? = nil,
    externalUID: String? = nil,
    stableID: String? = nil
  ) {
    self.id = id
    self.title = title
    self.description = description
    self.editURL = editURL
    self.start = start
    self.end = end
    self.allDay = allDay
    self.source = source
    self.sourceIdentifier = sourceIdentifier
    self.externalUID = externalUID
    self.stableID = stableID ?? "hey:\(id)"
  }

  public func progress(at date: Date) -> Double {
    guard end > start else { return date >= end ? 1 : 0 }
    return min(max(date.timeIntervalSince(start) / end.timeIntervalSince(start), 0), 1)
  }

  public func isOngoing(at date: Date) -> Bool {
    !allDay && date >= start && date < end
  }
}
