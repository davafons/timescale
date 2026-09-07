import Foundation
import TimescaleCore

@MainActor
final class HEYCalendarProvider: ObservableObject {
  @Published private(set) var currentEvent: CalendarEvent?
  @Published private(set) var isAvailable = true

  private static let refreshInterval: TimeInterval = 5 * 60
  private var timer: Timer?
  private var cachedEvents: [CalendarEvent] = []
  private var lastRefreshAttempt: Date?
  private var isRefreshing = false

  func start() {
    refresh()
    timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) {
      [weak self] _ in
      MainActor.assumeIsolated {
        self?.refreshIfStale()
      }
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  func refreshIfStale(at date: Date = Date()) {
    if let lastRefreshAttempt,
      date.timeIntervalSince(lastRefreshAttempt) < Self.refreshInterval
    {
      return
    }
    refresh(at: date)
  }

  func refresh(at date: Date = Date()) {
    guard !isRefreshing else { return }
    isRefreshing = true
    lastRefreshAttempt = date

    Task { [weak self] in
      let outcome = await Task.detached(priority: .utility) {
        Self.fetchEvents(at: date)
      }.value
      guard let self else { return }
      isRefreshing = false
      isAvailable = outcome.isAvailable
      if outcome.isAvailable {
        cachedEvents = outcome.events
        updateCurrentEvent(at: Date())
      }
    }
  }

  func updateCurrentEvent(at date: Date = Date()) {
    currentEvent = cachedEvents
      .filter { $0.isOngoing(at: date) }
      .sorted { $0.end < $1.end }
      .first
  }

  nonisolated private static func fetchEvents(at date: Date) -> HEYCalendarFetchOutcome {
    let process = Process()
    let output = Pipe()
    guard let heyPath = heyExecutablePath() else {
      return HEYCalendarFetchOutcome(events: [], isAvailable: false)
    }
    process.executableURL = URL(fileURLWithPath: heyPath)
    process.arguments = ["event", "list", "--starts-on", dayString(offset: -1, from: date),
      "--ends-on", dayString(offset: 1, from: date), "--all", "--json"]
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
      let data = output.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else {
        return HEYCalendarFetchOutcome(events: [], isAvailable: false)
      }
      let envelope = try JSONDecoder().decode(HEYEventEnvelope.self, from: data)
      let events = envelope.data
        .compactMap { $0.toCalendarEvent() }
        .filter { !$0.allDay }
      return HEYCalendarFetchOutcome(events: events, isAvailable: true)
    } catch {
      return HEYCalendarFetchOutcome(events: [], isAvailable: false)
    }
  }

  nonisolated private static func dayString(offset: Int, from date: Date) -> String {
    let calendar = Calendar.autoupdatingCurrent
    let day = calendar.date(byAdding: .day, value: offset, to: date) ?? date
    return day.formatted(.iso8601.year().month().day())
  }

  nonisolated private static func heyExecutablePath() -> String? {
    let fileManager = FileManager.default
    var paths = [
      fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/hey").path,
      "/opt/homebrew/bin/hey",
      "/usr/local/bin/hey",
    ]
    if let path = ProcessInfo.processInfo.environment["PATH"] {
      paths.append(contentsOf: path.split(separator: ":").map {
        String($0) + "/hey"
      })
    }
    return paths.first { fileManager.isExecutableFile(atPath: $0) }
  }
}

private struct HEYCalendarFetchOutcome: Sendable {
  let events: [CalendarEvent]
  let isAvailable: Bool
}

private struct HEYEventEnvelope: Decodable {
  let data: [HEYEvent]
}

private struct HEYEvent: Decodable {
  let id: Int
  let title: String?
  let summary: String?
  let description: String?
  let editURL: URL?
  let startsAt: Date
  let endsAt: Date
  let allDay: Bool?

  enum CodingKeys: String, CodingKey {
    case id, title, summary, description
    case editURL = "edit_url"
    case startsAt = "starts_at"
    case endsAt = "ends_at"
    case allDay = "all_day"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(Int.self, forKey: .id)
    title = try container.decodeIfPresent(String.self, forKey: .title)
    summary = try container.decodeIfPresent(String.self, forKey: .summary)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    editURL = try container.decodeIfPresent(URL.self, forKey: .editURL)
    startsAt = try container.decode(HEYISO8601Date.self, forKey: .startsAt).value
    endsAt = try container.decode(HEYISO8601Date.self, forKey: .endsAt).value
    allDay = try container.decodeIfPresent(Bool.self, forKey: .allDay)
  }

  func toCalendarEvent() -> CalendarEvent? {
    guard endsAt > startsAt else { return nil }
    return CalendarEvent(
      id: id,
      title: title ?? summary ?? "Untitled event",
      description: description,
      editURL: editURL,
      start: startsAt,
      end: endsAt,
      allDay: allDay ?? false)
  }
}

private struct HEYISO8601Date: Decodable {
  let value: Date

  init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: raw) {
      value = date
      return
    }
    formatter.formatOptions = [.withInternetDateTime]
    guard let date = formatter.date(from: raw) else {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
        debugDescription: "Invalid HEY timestamp: \(raw)"))
    }
    value = date
  }
}
