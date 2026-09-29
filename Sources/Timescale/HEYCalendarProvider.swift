import EventKit
import Foundation
import TimescaleCore

@MainActor
final class HEYCalendarProvider: ObservableObject {
  @Published private(set) var currentEvent: CalendarEvent?
  @Published private(set) var nextEvent: CalendarEvent?
  @Published private(set) var isAvailable = true
  @Published private(set) var cliUnavailable = false
  @Published private(set) var calendarAccessDenied = false

  private static let refreshInterval: TimeInterval = 5 * 60
  private var timer: Timer?
  private var cachedEvents: [CalendarEvent] = []
  private var lastRefreshAttempt: Date?
  private var isRefreshing = false
  private let eventStore = EKEventStore()
  private var selectionObserver: NSObjectProtocol?

  func start() {
    refresh()
    selectionObserver = NotificationCenter.default.addObserver(
      forName: .timescaleCalendarSelectionChanged, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.refresh() }
    }
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
    if let selectionObserver { NotificationCenter.default.removeObserver(selectionObserver) }
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
      let cliEnabled =
        UserDefaults.standard.object(forKey: SettingsKey.enableHEYCLI)
        as? Bool ?? true
      let outcome =
        cliEnabled
        ? await Task.detached(priority: .utility) { Self.fetchEvents(at: date) }.value
        : HEYCalendarFetchOutcome(events: [], isAvailable: true)
      guard let self else { return }
      isRefreshing = false
      let appleEvents = fetchAppleEvents(at: date)
      cliUnavailable = cliEnabled && !outcome.isAvailable
      calendarAccessDenied = EKEventStore.authorizationStatus(for: .event) == .denied
      isAvailable =
        outcome.isAvailable
        || EKEventStore.authorizationStatus(for: .event) == .fullAccess
      cachedEvents = Self.deduplicate(outcome.events + appleEvents)
      updateCurrentEvent(at: Date())
    }
  }

  func updateCurrentEvent(at date: Date = Date()) {
    currentEvent =
      cachedEvents
      .filter { $0.isOngoing(at: date) }
      .sorted { $0.end < $1.end }
      .first
    nextEvent =
      cachedEvents
      .filter { !$0.allDay && $0.start > date }
      .min { $0.start < $1.start }
  }

  private func fetchAppleEvents(at date: Date) -> [CalendarEvent] {
    guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
    let selectedIDs = UserDefaults.standard.string(forKey: SettingsKey.appleCalendarIDsJSON)
      .flatMap { $0.data(using: .utf8) }
      .flatMap { try? JSONDecoder().decode([String].self, from: $0) }
    let calendars = eventStore.calendars(for: .event).filter {
      selectedIDs == nil || selectedIDs!.contains($0.calendarIdentifier)
    }
    guard !calendars.isEmpty else { return [] }
    let start = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
    let end = Calendar.current.date(byAdding: .day, value: 8, to: date) ?? date
    let predicate = eventStore.predicateForEvents(
      withStart: start, end: end, calendars: calendars)
    return eventStore.events(matching: predicate)
      .filter { !$0.isAllDay }
      .compactMap { event in
        guard let identifier = event.eventIdentifier else { return nil }
        return CalendarEvent(
          id: identifier.hashValue,
          title: event.title ?? "Untitled event",
          description: event.notes,
          start: event.startDate, end: event.endDate,
          source: event.calendar.title,
          sourceIdentifier: "eventkit:\(event.calendar.calendarIdentifier)",
          externalUID: event.calendarItemExternalIdentifier,
          stableID: "apple:\(identifier)")
      }
  }

  private static func deduplicate(_ events: [CalendarEvent]) -> [CalendarEvent] {
    let normalized = events.map {
      TimedEvent(
        id: $0.stableID, source: $0.source,
        sourceIdentifier: $0.sourceIdentifier, externalUID: $0.externalUID,
        title: $0.title, detail: $0.description,
        start: $0.start, end: $0.end, openURL: $0.editURL)
    }
    let kept = Set(TimedEvents.deduplicated(normalized).map(\.id))
    return events.filter { kept.contains($0.stableID) }
  }

  nonisolated private static func fetchEvents(at date: Date) -> HEYCalendarFetchOutcome {
    let process = Process()
    let output = Pipe()
    guard let heyPath = heyExecutablePath() else {
      return HEYCalendarFetchOutcome(events: [], isAvailable: false)
    }
    process.executableURL = URL(fileURLWithPath: heyPath)
    process.arguments = [
      "event", "list", "--starts-on", dayString(offset: -1, from: date),
      "--ends-on", dayString(offset: 1, from: date), "--all", "--json",
    ]
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
      paths.append(
        contentsOf: path.split(separator: ":").map {
          String($0) + "/hey"
        })
    }
    return paths.first { fileManager.isExecutableFile(atPath: $0) }
  }
}

extension Notification.Name {
  static let timescaleCalendarSelectionChanged =
    Notification.Name("timescaleCalendarSelectionChanged")
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
      allDay: allDay ?? false,
      sourceIdentifier: "hey-cli")
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
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath,
          debugDescription: "Invalid HEY timestamp: \(raw)"))
    }
    value = date
  }
}
