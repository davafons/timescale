import Foundation

public struct SharedConfiguration: Codable, Equatable, Sendable {
  public static let currentVersion = 1

  public var version: Int
  public var timeZone: String
  public var day: SharedDaySettings
  public var routine: SharedRoutineSettings
  public var counters: [SharedCounter]
  public var week: SharedWeekSettings
  public var quarter: SharedQuarterSettings
  public var solar: SharedSolarSettings
  public var life: SharedLifeSettings
  public var visible: [SharedPeriod]
  public var macOS: SharedMacOSSettings
  public var tui: SharedTUISettings

  private enum CodingKeys: String, CodingKey {
    case version, timeZone, day, routine, counters, week, quarter, solar, life, visible, macOS, tui
  }

  public init(
    version: Int = currentVersion,
    timeZone: String = "local",
    day: SharedDaySettings = .init(),
    routine: SharedRoutineSettings = .init(),
    counters: [SharedCounter] = [],
    week: SharedWeekSettings = .init(),
    quarter: SharedQuarterSettings = .init(),
    solar: SharedSolarSettings = .init(),
    life: SharedLifeSettings = .init(),
    visible: [SharedPeriod] = SharedPeriod.allCases,
    macOS: SharedMacOSSettings = .init(),
    tui: SharedTUISettings = .init()
  ) {
    self.version = version
    self.timeZone = timeZone
    self.day = day
    self.routine = routine
    self.counters = counters
    self.week = week
    self.quarter = quarter
    self.solar = solar
    self.life = life
    self.visible = visible
    self.macOS = macOS
    self.tui = tui
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
    timeZone = try container.decodeIfPresent(String.self, forKey: .timeZone) ?? "local"
    day = try container.decodeIfPresent(SharedDaySettings.self, forKey: .day) ?? .init()
    routine = try container.decodeIfPresent(SharedRoutineSettings.self, forKey: .routine) ?? .init()
    counters = try container.decodeIfPresent([SharedCounter].self, forKey: .counters) ?? []
    week = try container.decodeIfPresent(SharedWeekSettings.self, forKey: .week) ?? .init()
    quarter = try container.decodeIfPresent(SharedQuarterSettings.self, forKey: .quarter) ?? .init()
    solar = try container.decodeIfPresent(SharedSolarSettings.self, forKey: .solar) ?? .init()
    life = try container.decodeIfPresent(SharedLifeSettings.self, forKey: .life) ?? .init()
    visible = try container.decodeIfPresent([SharedPeriod].self, forKey: .visible) ?? SharedPeriod.allCases
    macOS = try container.decodeIfPresent(SharedMacOSSettings.self, forKey: .macOS) ?? .init()
    tui = try container.decodeIfPresent(SharedTUISettings.self, forKey: .tui) ?? .init()
  }

  public func validate() throws {
    guard version == Self.currentVersion else {
      throw SharedConfigurationError.invalid("Unsupported settings version \(version).")
    }
    guard timeZone == "local" else {
      throw SharedConfigurationError.invalid("timeZone currently must be \"local\".")
    }
    _ = try Self.minutes(day.start)
    _ = try Self.minutes(day.end)
    guard !routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw SharedConfigurationError.invalid("routine.name must not be empty.")
    }
    guard (1...10_080).contains(routine.durationMinutes) else {
      throw SharedConfigurationError.invalid("routine.durationMinutes must be between 1 and 10080.")
    }
    guard counters.count <= 100 else {
      throw SharedConfigurationError.invalid("counters must contain at most 100 items.")
    }
    var counterIDs = Set<String>()
    for counter in counters {
      guard counterIDs.insert(counter.id).inserted else {
        throw SharedConfigurationError.invalid("counters must not contain duplicate IDs.")
      }
      try counter.validate()
    }
    if let startedAt = routine.startedAt,
      ISO8601DateFormatter().date(from: startedAt) == nil
    {
      throw SharedConfigurationError.invalid("routine.startedAt must be an RFC 3339 timestamp.")
    }
    guard (0...3).contains(macOS.precision) else {
      throw SharedConfigurationError.invalid("macOS.precision must be between 0 and 3.")
    }
    guard life.expectancyYears > 0, life.expectancyYears <= 150 else {
      throw SharedConfigurationError.invalid("life.expectancyYears must be between 0 and 150.")
    }
    if let birthDate = life.birthDate {
      guard Self.isDate(birthDate) else {
        throw SharedConfigurationError.invalid("life.birthDate must be a valid YYYY-MM-DD date.")
      }
    }
    guard Set(visible).count == visible.count else {
      throw SharedConfigurationError.invalid("visible must not contain duplicate periods.")
    }
    guard ["system", "orange", "blue", "green", "purple", "monochrome"].contains(macOS.accent)
    else {
      throw SharedConfigurationError.invalid("macOS.accent is not supported.")
    }
    let source = macOS.statusItemSource
    let validSource = ["day", "week", "month", "quarter", "year", "life"].contains(source)
      || source.split(separator: ":", maxSplits: 1).count == 2
        && source.hasPrefix("counter:")
        && counters.contains { $0.id == String(source.dropFirst("counter:".count)) }
    guard validSource else {
      throw SharedConfigurationError.invalid("macOS.statusItemSource is not a known progress source.")
    }
    guard solar.latitude.map({ (-90...90).contains($0) }) ?? true,
      solar.longitude.map({ (-180...180).contains($0) }) ?? true,
      (solar.latitude != nil) == (solar.longitude != nil)
    else {
      throw SharedConfigurationError.invalid("Solar coordinates are incomplete or out of range.")
    }
  }

  public static func minutes(_ value: String) throws -> Int {
    let parts = value.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
      let hour = Int(parts[0]), let minute = Int(parts[1]),
      (0...23).contains(hour), (0...59).contains(minute)
    else {
      throw SharedConfigurationError.invalid("Invalid time \(value); expected HH:MM.")
    }
    return hour * 60 + minute
  }

  private static func isDate(_ value: String) -> Bool {
    let parts = value.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
      let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
    else { return false }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
    else { return false }
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return components.year == year && components.month == month && components.day == day
  }
}

public enum SharedConfigurationError: LocalizedError {
  case invalid(String)

  public var errorDescription: String? {
    switch self {
    case .invalid(let message): message
    }
  }
}

public struct SharedDaySettings: Codable, Equatable, Sendable {
  public var start: String
  public var end: String

  public init(start: String = "08:00", end: String = "23:00") {
    self.start = start
    self.end = end
  }
}

public struct SharedRoutineSettings: Codable, Equatable, Sendable {
  public var name: String
  public var durationMinutes: Int
  public var startedAt: String?

  public init(name: String = "Work", durationMinutes: Int = 8 * 60, startedAt: String? = nil) {
    self.name = name
    self.durationMinutes = durationMinutes
    self.startedAt = startedAt
  }
}

public struct SharedCounter: Codable, Equatable, Sendable, Identifiable {
  public var id: String
  public var name: String
  public var targetMinutes: Int
  public var elapsedSeconds: Double
  public var startedAt: String?

  public init(
    id: String = UUID().uuidString,
    name: String = "Work",
    targetMinutes: Int = 8 * 60,
    elapsedSeconds: Double = 0,
    startedAt: String? = nil
  ) {
    self.id = id
    self.name = name
    self.targetMinutes = targetMinutes
    self.elapsedSeconds = elapsedSeconds
    self.startedAt = startedAt
  }

  public func validate() throws {
    guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw SharedConfigurationError.invalid("counter.id must not be empty.")
    }
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw SharedConfigurationError.invalid("counter.name must not be empty.")
    }
    guard (1...10_080).contains(targetMinutes) else {
      throw SharedConfigurationError.invalid("counter.targetMinutes must be between 1 and 10080.")
    }
    guard elapsedSeconds.isFinite, elapsedSeconds >= 0 else {
      throw SharedConfigurationError.invalid("counter.elapsedSeconds must be non-negative.")
    }
    if let startedAt, ISO8601DateFormatter().date(from: startedAt) == nil {
      throw SharedConfigurationError.invalid("counter.startedAt must be an RFC 3339 timestamp.")
    }
  }

  public func elapsed(at date: Date) -> Double {
    guard let startedAt, let start = ISO8601DateFormatter().date(from: startedAt) else {
      return min(elapsedSeconds, Double(targetMinutes * 60))
    }
    return min(
      max(elapsedSeconds + max(date.timeIntervalSince(start), 0), 0),
      Double(targetMinutes * 60)
    )
  }
}

public enum SharedWeekStart: String, Codable, CaseIterable, Sendable {
  case monday, sunday
}

public struct SharedWeekSettings: Codable, Equatable, Sendable {
  public var startsOn: SharedWeekStart

  public init(startsOn: SharedWeekStart = .monday) {
    self.startsOn = startsOn
  }
}

public enum SharedQuarterCycle: String, Codable, CaseIterable, Sendable {
  case calendar, japanFiscal
}

public struct SharedQuarterSettings: Codable, Equatable, Sendable {
  public var cycle: SharedQuarterCycle

  public init(cycle: SharedQuarterCycle = .calendar) {
    self.cycle = cycle
  }
}

public struct SharedSolarSettings: Codable, Equatable, Sendable {
  public var enabled: Bool
  public var latitude: Double?
  public var longitude: Double?

  public init(enabled: Bool = true, latitude: Double? = nil, longitude: Double? = nil) {
    self.enabled = enabled
    self.latitude = latitude
    self.longitude = longitude
  }
}

public struct SharedLifeSettings: Codable, Equatable, Sendable {
  public var birthDate: String?
  public var country: String
  public var expectancyYears: Double

  public init(birthDate: String? = nil, country: String = "Japan", expectancyYears: Double = 84) {
    self.birthDate = birthDate
    self.country = country
    self.expectancyYears = expectancyYears
  }
}

public enum SharedPeriod: String, Codable, CaseIterable, Sendable, Hashable {
  case day, week, month, quarter, year, life
}

public struct SharedMacOSSettings: Codable, Equatable, Sendable {
  public var accent: String
  public var precision: Int
  public var showRemaining: Bool
  public var statusItemSource: String

  private enum CodingKeys: String, CodingKey { case accent, precision, showRemaining, statusItemSource }

  public init(
    accent: String = "system", precision: Int = 1, showRemaining: Bool = false,
    statusItemSource: String = "day"
  ) {
    self.accent = accent
    self.precision = precision
    self.showRemaining = showRemaining
    self.statusItemSource = statusItemSource
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    accent = try container.decodeIfPresent(String.self, forKey: .accent) ?? "system"
    precision = try container.decodeIfPresent(Int.self, forKey: .precision) ?? 1
    showRemaining = try container.decodeIfPresent(Bool.self, forKey: .showRemaining) ?? false
    statusItemSource = try container.decodeIfPresent(String.self, forKey: .statusItemSource) ?? "day"
  }
}

public enum SharedTUITheme: String, Codable, CaseIterable, Sendable {
  case auto, color, catppuccin, tokyoNight, gruvbox, monochrome
}

public enum SharedTUIMotion: String, Codable, CaseIterable, Sendable {
  case full, reduced, off
}

public struct SharedTUISettings: Codable, Equatable, Sendable {
  public var theme: SharedTUITheme
  public var motion: SharedTUIMotion

  public init(
    theme: SharedTUITheme = .auto,
    motion: SharedTUIMotion = .full
  ) {
    self.theme = theme
    self.motion = motion
  }
}
