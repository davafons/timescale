import Foundation
import TimescaleCore

@MainActor
final class SharedSettingsCoordinator {
  private let defaults: UserDefaults
  private let fileManager: FileManager
  private(set) var configurationURL: URL
  private var defaultsObserver: NSObjectProtocol?
  private var pollingTimer: Timer?
  private var exportWorkItem: DispatchWorkItem?
  private var lastFileData: Data?
  private var suppressDefaultsUntil = Date.distantPast

  init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
    self.defaults = defaults
    self.fileManager = fileManager
    configurationURL = Self.resolveConfigurationURL(fileManager: fileManager)
  }

  func start() {
    if fileManager.fileExists(atPath: configurationURL.path) {
      if sharedFileContainsUntouchedDefaults(), hasPersistedNativeSettings() {
        exportNow()
      } else {
        importFile()
      }
    } else {
      exportNow()
    }

    defaultsObserver = NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification,
      object: defaults,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.defaultsDidChange()
      }
    }
    pollingTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.importFileIfChanged()
      }
    }
  }

  func stop() {
    pollingTimer?.invalidate()
    exportWorkItem?.cancel()
    if let defaultsObserver {
      NotificationCenter.default.removeObserver(defaultsObserver)
    }
  }

  private func defaultsDidChange() {
    guard Date() >= suppressDefaultsUntil else { return }
    exportWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated {
        self?.exportNow()
      }
    }
    exportWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
  }

  private func importFileIfChanged() {
    guard let data = try? Data(contentsOf: configurationURL), data != lastFileData else { return }
    importData(data)
  }

  private func importFile() {
    guard let data = try? Data(contentsOf: configurationURL) else { return }
    importData(data)
  }

  private func sharedFileContainsUntouchedDefaults() -> Bool {
    guard let data = try? Data(contentsOf: configurationURL),
      let configuration = try? JSONDecoder().decode(SharedConfiguration.self, from: data)
    else { return false }
    return configuration == SharedConfiguration()
  }

  private func hasPersistedNativeSettings() -> Bool {
    guard
      let domain = defaults.persistentDomain(forName: "com.davafons.timescale")
    else { return false }
    return [
      SettingsKey.birthDateConfigured,
      SettingsKey.country,
      SettingsKey.dayStartMinutes,
      SettingsKey.dayEndMinutes,
      SettingsKey.lifeExpectancy,
      SettingsKey.locationConfigured,
    ].contains { domain[$0] != nil }
  }

  private func importData(_ data: Data) {
    do {
      let configuration = try JSONDecoder().decode(SharedConfiguration.self, from: data)
      try configuration.validate()
      let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
      let hasCountersField = object?["counters"] != nil
      suppressDefaultsUntil = Date().addingTimeInterval(0.75)
      apply(configuration, preserveMigratedCounters: !hasCountersField)
      lastFileData = data
    } catch {
      NSLog("Timescale ignored invalid shared settings: %@", error.localizedDescription)
    }
  }

  private func exportNow() {
    do {
      if let currentData = try? Data(contentsOf: configurationURL),
        let lastFileData,
        currentData != lastFileData
      {
        importData(currentData)
        return
      }
      var configuration = existingConfiguration() ?? SharedConfiguration()
      update(&configuration)
      try configuration.validate()
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      var data = try encoder.encode(configuration)
      data.append(0x0A)
      let directory = configurationURL.deletingLastPathComponent()
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
      try data.write(to: configurationURL, options: .atomic)
      try fileManager.setAttributes(
        [.posixPermissions: 0o600], ofItemAtPath: configurationURL.path)
      lastFileData = data
    } catch {
      NSLog("Timescale could not write shared settings: %@", error.localizedDescription)
    }
  }

  private func existingConfiguration() -> SharedConfiguration? {
    guard let data = try? Data(contentsOf: configurationURL),
      let configuration = try? JSONDecoder().decode(SharedConfiguration.self, from: data),
      (try? configuration.validate()) != nil
    else { return nil }
    return configuration
  }

  private func update(_ configuration: inout SharedConfiguration) {
    configuration.version = SharedConfiguration.currentVersion
    configuration.day.start = Self.timeString(defaults.integer(forKey: SettingsKey.dayStartMinutes))
    configuration.day.end = Self.timeString(defaults.integer(forKey: SettingsKey.dayEndMinutes))
    configuration.routine.name =
      defaults.string(forKey: SettingsKey.routineName) ?? "Work"
    configuration.routine.durationMinutes =
      defaults.integer(forKey: SettingsKey.routineDurationMinutes)
    let routineStartedTimestamp = defaults.double(forKey: SettingsKey.routineStartedTimestamp)
    configuration.routine.startedAt =
      routineStartedTimestamp > 0
      ? ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: routineStartedTimestamp))
      : nil
    if let data = defaults.string(forKey: SettingsKey.countersJSON)?.data(using: .utf8),
      let counters = try? JSONDecoder().decode([SharedCounter].self, from: data)
    {
      configuration.counters = counters
    }
    configuration.week.startsOn =
      defaults.string(forKey: SettingsKey.weekStartsOn) == WeekStartChoice.sunday.rawValue
      ? .sunday : .monday
    configuration.quarter.cycle =
      defaults.string(forKey: SettingsKey.quarterCycle) == QuarterCycle.japanFiscal.rawValue
      ? .japanFiscal : .calendar
    configuration.solar.enabled = defaults.bool(forKey: SettingsKey.showSolarEvents)
    if defaults.bool(forKey: SettingsKey.locationConfigured) {
      configuration.solar.latitude = defaults.double(forKey: SettingsKey.latitude)
      configuration.solar.longitude = defaults.double(forKey: SettingsKey.longitude)
    } else {
      configuration.solar.latitude = nil
      configuration.solar.longitude = nil
    }
    configuration.life.birthDate = configuredBirthDateString()
    configuration.life.country =
      defaults.string(forKey: SettingsKey.country) ?? Country.japan.rawValue
    configuration.life.expectancyYears = defaults.double(forKey: SettingsKey.lifeExpectancy)
    configuration.visible = visiblePeriods()
    configuration.macOS.accent =
      defaults.string(forKey: SettingsKey.accent) ?? AccentChoice.system.rawValue
    configuration.macOS.precision = defaults.integer(forKey: SettingsKey.precision)
    configuration.macOS.showRemaining = defaults.bool(forKey: SettingsKey.showRemaining)
    configuration.macOS.statusItemSource =
      defaults.string(forKey: SettingsKey.statusItemSource) ?? "day"
  }

  private func apply(_ configuration: SharedConfiguration, preserveMigratedCounters: Bool = false) {
    if let start = try? SharedConfiguration.minutes(configuration.day.start) {
      defaults.set(start, forKey: SettingsKey.dayStartMinutes)
    }
    if let end = try? SharedConfiguration.minutes(configuration.day.end) {
      defaults.set(end, forKey: SettingsKey.dayEndMinutes)
    }
    defaults.set(configuration.routine.name, forKey: SettingsKey.routineName)
    defaults.set(configuration.routine.durationMinutes, forKey: SettingsKey.routineDurationMinutes)
    if let startedAt = configuration.routine.startedAt,
      let date = ISO8601DateFormatter().date(from: startedAt)
    {
      defaults.set(date.timeIntervalSince1970, forKey: SettingsKey.routineStartedTimestamp)
    } else {
      defaults.set(0.0, forKey: SettingsKey.routineStartedTimestamp)
    }
    if !preserveMigratedCounters {
      if let data = try? JSONEncoder().encode(configuration.counters),
        let value = String(data: data, encoding: .utf8)
      {
        defaults.set(value, forKey: SettingsKey.countersJSON)
      }
    }
    defaults.set(configuration.week.startsOn.rawValue, forKey: SettingsKey.weekStartsOn)
    defaults.set(configuration.quarter.cycle.rawValue, forKey: SettingsKey.quarterCycle)
    defaults.set(configuration.solar.enabled, forKey: SettingsKey.showSolarEvents)
    if let latitude = configuration.solar.latitude,
      let longitude = configuration.solar.longitude
    {
      defaults.set(true, forKey: SettingsKey.locationConfigured)
      defaults.set(latitude, forKey: SettingsKey.latitude)
      defaults.set(longitude, forKey: SettingsKey.longitude)
    } else {
      defaults.set(false, forKey: SettingsKey.locationConfigured)
    }
    applyBirthDate(configuration.life.birthDate)
    defaults.set(configuration.life.country, forKey: SettingsKey.country)
    defaults.set(configuration.life.expectancyYears, forKey: SettingsKey.lifeExpectancy)
    let visible = Set(configuration.visible)
    defaults.set(visible.contains(.day), forKey: SettingsKey.showDay)
    defaults.set(visible.contains(.week), forKey: SettingsKey.showWeek)
    defaults.set(visible.contains(.month), forKey: SettingsKey.showMonth)
    defaults.set(visible.contains(.quarter), forKey: SettingsKey.showQuarter)
    defaults.set(visible.contains(.year), forKey: SettingsKey.showYear)
    defaults.set(visible.contains(.life), forKey: SettingsKey.showLife)
    defaults.set(configuration.macOS.accent, forKey: SettingsKey.accent)
    defaults.set(configuration.macOS.precision, forKey: SettingsKey.precision)
    defaults.set(configuration.macOS.showRemaining, forKey: SettingsKey.showRemaining)
    defaults.set(configuration.macOS.statusItemSource, forKey: SettingsKey.statusItemSource)
  }

  private func visiblePeriods() -> [SharedPeriod] {
    [
      (SettingsKey.showDay, SharedPeriod.day),
      (SettingsKey.showWeek, .week),
      (SettingsKey.showMonth, .month),
      (SettingsKey.showQuarter, .quarter),
      (SettingsKey.showYear, .year),
      (SettingsKey.showLife, .life),
    ].compactMap { defaults.bool(forKey: $0.0) ? $0.1 : nil }
  }

  private func configuredBirthDateString() -> String? {
    guard defaults.bool(forKey: SettingsKey.birthDateConfigured) else { return nil }
    let year = defaults.integer(forKey: SettingsKey.birthYear)
    let month = defaults.integer(forKey: SettingsKey.birthMonth)
    let day = defaults.integer(forKey: SettingsKey.birthDay)
    guard year > 0, month > 0, day > 0 else { return nil }
    return String(format: "%04d-%02d-%02d", year, month, day)
  }

  private func applyBirthDate(_ value: String?) {
    guard let value else {
      defaults.set(false, forKey: SettingsKey.birthDateConfigured)
      return
    }
    let parts = value.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .autoupdatingCurrent
    guard
      let date = calendar.date(
        from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    else { return }
    defaults.set(true, forKey: SettingsKey.birthDateConfigured)
    defaults.set(parts[0], forKey: SettingsKey.birthYear)
    defaults.set(parts[1], forKey: SettingsKey.birthMonth)
    defaults.set(parts[2], forKey: SettingsKey.birthDay)
    defaults.set(date.timeIntervalSince1970, forKey: SettingsKey.birthTimestamp)
  }

  private static func timeString(_ minutes: Int) -> String {
    String(format: "%02d:%02d", minutes / 60, minutes % 60)
  }

  private static func resolveConfigurationURL(fileManager: FileManager) -> URL {
    if let override = ProcessInfo.processInfo.environment["TIMESCALE_CONFIG"], !override.isEmpty {
      return URL(fileURLWithPath: override).standardizedFileURL
    }
    let base =
      fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support")
    return base.appendingPathComponent("Timescale/config.json")
  }
}
