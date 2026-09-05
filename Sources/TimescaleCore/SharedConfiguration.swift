import Foundation

public struct SharedConfiguration: Codable, Equatable, Sendable {
  public static let currentVersion = 1

  public var version: Int
  public var timeZone: String
  public var day: SharedDaySettings
  public var routine: SharedRoutineSettings
  public var week: SharedWeekSettings
  public var quarter: SharedQuarterSettings
  public var solar: SharedSolarSettings
  public var life: SharedLifeSettings
  public var visible: [SharedPeriod]
  public var macOS: SharedMacOSSettings
  public var tui: SharedTUISettings

  public init(
    version: Int = currentVersion,
    timeZone: String = "local",
    day: SharedDaySettings = .init(),
    routine: SharedRoutineSettings = .init(),
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
    self.week = week
    self.quarter = quarter
    self.solar = solar
    self.life = life
    self.visible = visible
    self.macOS = macOS
    self.tui = tui
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

  public init(accent: String = "system", precision: Int = 1, showRemaining: Bool = false) {
    self.accent = accent
    self.precision = precision
    self.showRemaining = showRemaining
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
