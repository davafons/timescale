import Foundation

public struct TimedEvent: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let source: String
  public let sourceIdentifier: String?
  public let externalUID: String?
  public let title: String
  public let detail: String?
  public let start: Date
  public let end: Date
  public let openURL: URL?

  public init(
    id: String, source: String, sourceIdentifier: String? = nil,
    externalUID: String? = nil, title: String,
    detail: String? = nil, start: Date, end: Date, openURL: URL? = nil
  ) {
    self.id = id
    self.source = source
    self.sourceIdentifier = sourceIdentifier
    self.externalUID = externalUID
    self.title = title
    self.detail = detail
    self.start = start
    self.end = end
    self.openURL = openURL
  }

  public func progress(at date: Date) -> Double {
    guard end > start else { return 0 }
    return min(max(date.timeIntervalSince(start) / end.timeIntervalSince(start), 0), 1)
  }
}

public struct TimedEventSelection: Equatable, Sendable {
  public let current: TimedEvent?
  public let next: TimedEvent?
}

public enum TimedEvents {
  public static func leadIn(
    to eventStart: Date, at date: Date, wakingDay: TimeProgress,
    lookAhead: TimeInterval = 8 * 60 * 60
  ) -> TimeProgress? {
    guard date >= wakingDay.start, date < wakingDay.end,
      eventStart > date, eventStart <= wakingDay.end,
      eventStart.timeIntervalSince(date) <= lookAhead
    else { return nil }
    let start = max(wakingDay.start, eventStart.addingTimeInterval(-lookAhead))
    return TimeProgress(
      elapsed: date.timeIntervalSince(start) / eventStart.timeIntervalSince(start),
      start: start, end: eventStart)
  }

  public static func deduplicated(_ events: [TimedEvent]) -> [TimedEvent] {
    var kept: [TimedEvent] = []
    let sorted = events
      .filter { $0.end > $0.start }
      .sorted {
        if $0.start != $1.start { return $0.start < $1.start }
        return $0.source < $1.source
      }
    for event in sorted {
      let duplicate = kept.contains { existing in
        guard existing.title.trimmingCharacters(in: .whitespacesAndNewlines)
          .localizedCaseInsensitiveCompare(
            event.title.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame,
          abs(existing.start.timeIntervalSince(event.start)) < 1,
          abs(existing.end.timeIntervalSince(event.end)) < 1
        else { return false }
        if let firstUID = existing.externalUID, let secondUID = event.externalUID {
          return firstUID == secondUID
        }
        if existing.sourceIdentifier == event.sourceIdentifier,
          existing.id == event.id
        { return true }
        let firstIsCLI = existing.sourceIdentifier == "hey-cli"
        let secondIsCLI = event.sourceIdentifier == "hey-cli"
        let firstIsEventKit = existing.sourceIdentifier?.hasPrefix("eventkit:") == true
        let secondIsEventKit = event.sourceIdentifier?.hasPrefix("eventkit:") == true
        return (firstIsCLI && secondIsEventKit)
          || (secondIsCLI && firstIsEventKit)
      }
      if !duplicate { kept.append(event) }
    }
    return kept
  }

  public static func select(_ events: [TimedEvent], at date: Date) -> TimedEventSelection {
    let unique = deduplicated(events)
    return TimedEventSelection(
      current: unique.filter { $0.start <= date && date < $0.end }
        .min { $0.end < $1.end },
      next: unique.filter { $0.start > date }
        .min { $0.start < $1.start })
  }
}
