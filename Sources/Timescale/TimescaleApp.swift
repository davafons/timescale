import AppKit
import SwiftUI
import TimescaleCore

@main
@MainActor
final class TimescaleApp: NSObject, NSApplicationDelegate {
  private static let retainedDelegate = TimescaleApp()
  private var statusItem: NSStatusItem!
  private let popover = NSPopover()
  private let checkSession = CheckSession()
  private let calendarProvider = HEYCalendarProvider()
  private var updateTimer: Timer?
  private var defaultsObserver: NSObjectProtocol?
  private let sharedSettings = SharedSettingsCoordinator()
  private let locationProvider = LocationProvider()

  static func main() {
    let application = NSApplication.shared
    application.delegate = retainedDelegate
    application.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApplication.shared.setActivationPolicy(.accessory)
    registerDefaults()
    migrateLegacySettings()
    sharedSettings.start()
    calendarProvider.start()
    configurePopover()
    configureStatusItem()
    updatePercentage()

    updateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.calendarProvider.updateCurrentEvent()
        self?.updatePercentage()
      }
    }
    defaultsObserver = NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification,
      object: UserDefaults.standard,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.updatePercentage()
      }
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
      self?.recordCheckAndShowPopover()
    }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    recordCheckAndShowPopover()
    return true
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    guard urls.contains(where: { $0.scheme == "timescale" && $0.host == "locate" }) else {
      return
    }
    requestCurrentLocation()
  }

  func applicationWillTerminate(_ notification: Notification) {
    updateTimer?.invalidate()
    sharedSettings.stop()
    calendarProvider.stop()
    if let defaultsObserver {
      NotificationCenter.default.removeObserver(defaultsObserver)
    }
  }

  private func configurePopover() {
    popover.behavior = .transient
    popover.animates = true
    popover.contentViewController = NSHostingController(
      rootView: ProgressPopover(checkSession: checkSession, calendarProvider: calendarProvider))
  }

  private func configureStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.autosaveName = "TimescaleStatusItem"

    guard let button = statusItem.button else { return }
    button.image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: "Timescale")
    button.imagePosition = .imageLeading
    button.target = self
    button.action = #selector(statusItemClicked)
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
  }

  @objc private func statusItemClicked() {
    if NSApplication.shared.currentEvent?.type == .rightMouseUp {
      showContextMenu()
      return
    }

    if popover.isShown {
      popover.performClose(nil)
      return
    }

    recordCheckAndShowPopover()
  }

  private func showContextMenu() {
    guard let event = NSApplication.shared.currentEvent, let button = statusItem.button else {
      return
    }

    let menu = NSMenu()
    let settingsItem = menu.addItem(
      withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "")
    settingsItem.image = NSImage(
      systemSymbolName: "gearshape", accessibilityDescription: "Settings")

    menu.addItem(.separator())
    menu.addItem(withTitle: "Quit Timescale", action: #selector(quit), keyEquivalent: "")
    for item in menu.items {
      item.target = self
    }

    NSMenu.popUpContextMenu(menu, with: event, for: button)
  }

  @objc private func openSettings() {
    SettingsWindowController.shared.show()
  }

  @objc private func quit() {
    NSApplication.shared.terminate(nil)
  }

  private func recordCheckAndShowPopover() {
    let defaults = UserDefaults.standard
    let now = Date().timeIntervalSince1970
    let activeApplication = NSWorkspace.shared.frontmostApplication
    sharedSettings.recordCheck(
      at: now,
      source: defaults.string(forKey: SettingsKey.statusItemSource) ?? "day",
      appName: activeApplication?.localizedName,
      bundleIdentifier: activeApplication?.bundleIdentifier)
    showPopover(checkTimestamp: now)
  }

  private func showPopover(checkTimestamp: TimeInterval? = nil) {
    checkSession.currentTimestamp = checkTimestamp
    calendarProvider.refreshIfStale()
    guard statusItem.isVisible, let button = statusItem.button, button.window != nil else {
      SettingsWindowController.shared.show()
      return
    }
    updatePercentage()
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    popover.contentViewController?.view.window?.makeKey()

    DispatchQueue.main.async { [weak self, weak button] in
      guard let self, let button else { return }
      self.clampPopoverToVisibleScreen(relativeTo: button)
    }
  }

  private func clampPopoverToVisibleScreen(relativeTo button: NSStatusBarButton) {
    guard let window = popover.contentViewController?.view.window,
      let screen = button.window?.screen ?? NSScreen.main
    else { return }

    let safeFrame = screen.visibleFrame.insetBy(dx: 10, dy: 0)
    var frame = window.frame
    frame.origin.x = min(max(frame.origin.x, safeFrame.minX), safeFrame.maxX - frame.width)
    frame.origin.y = min(max(frame.origin.y, safeFrame.minY), safeFrame.maxY - frame.height)
    window.setFrameOrigin(frame.origin)
  }

  private func updatePercentage() {
    let defaults = UserDefaults.standard
    let requestedSource = defaults.string(forKey: SettingsKey.statusItemSource) ?? "day"
    let now = Date()
    let result: (progress: Double, label: String, resolvedSource: String)
    if requestedSource.hasPrefix("counter:"),
      let data = defaults.string(forKey: SettingsKey.countersJSON)?.data(using: .utf8),
      let counters = try? JSONDecoder().decode([SharedCounter].self, from: data),
      let counter = counters.first(where: { "counter:\($0.id)" == requestedSource })
    {
      result = (
        counter.elapsed(at: now) / Double(counter.targetMinutes * 60),
        counter.name,
        requestedSource
      )
    } else {
      switch requestedSource {
      case "day":
        result = (dayProgress(at: now, defaults: defaults), "waking day", "day")
      case "week":
        var calendar = Calendar.autoupdatingCurrent
        let weekStart = defaults.string(forKey: SettingsKey.weekStartsOn)
        calendar.firstWeekday = weekStart == WeekStartChoice.sunday.rawValue ? 1 : 2
        calendar.minimumDaysInFirstWeek = weekStart == WeekStartChoice.sunday.rawValue ? 1 : 4
        result = (ProgressCalculator.week(at: now, calendar: calendar).elapsed, "week", "week")
      case "month":
        result = (ProgressCalculator.month(at: now).elapsed, "month", "month")
      case "quarter":
        let quarterCycle = defaults.string(forKey: SettingsKey.quarterCycle) ?? ""
        let cycle = QuarterCycle(rawValue: quarterCycle) ?? .calendar
        result = (
          ProgressCalculator.quarter(at: now, startMonth: cycle.startMonth).elapsed,
          cycle == .calendar ? "quarter" : "fiscal quarter",
          "quarter"
        )
      case "year":
        result = (ProgressCalculator.year(at: now).elapsed, "year", "year")
      case "life":
        if let birthDate = configuredBirthDate(from: defaults),
          let progress = ProgressCalculator.life(
            at: now,
            birthDate: birthDate,
            expectedYears: defaults.double(forKey: SettingsKey.lifeExpectancy))
        {
          result = (progress.elapsed, "life estimate", "life")
        } else {
          result = (dayProgress(at: now, defaults: defaults), "waking day", "day")
        }
      default:
        result = (dayProgress(at: now, defaults: defaults), "waking day", "day")
      }
    }
    if result.resolvedSource != requestedSource {
      defaults.set(result.resolvedSource, forKey: SettingsKey.statusItemSource)
    }
    let percentage = min(max(result.progress, 0), 1).formatted(
      .percent.precision(.fractionLength(0)))
    if let event = calendarProvider.currentEvent {
      let eventPercentage = event.progress(at: now).formatted(
        .percent.precision(.fractionLength(0)))
      statusItem.button?.image = nil
      statusItem.button?.attributedTitle = statusTitle(
        selectedPercentage: percentage, eventPercentage: eventPercentage)
      statusItem.button?.setAccessibilityValue(
        "\(percentage) of \(result.label) elapsed; \(eventPercentage) of \(event.title) elapsed")
    } else {
      statusItem.button?.image = nil
      statusItem.button?.attributedTitle = statusTitle(selectedPercentage: percentage)
      statusItem.button?.setAccessibilityValue("\(percentage) of \(result.label) elapsed")
    }
  }

  private func statusTitle(
    selectedPercentage: String,
    eventPercentage: String? = nil
  ) -> NSAttributedString {
    let title = NSMutableAttributedString()
    appendStatusSymbol("hourglass", accessibilityDescription: "Selected progress", to: title)
    title.append(NSAttributedString(string: " \(selectedPercentage)"))
    if let eventPercentage {
      title.append(NSAttributedString(string: "  "))
      appendStatusSymbol(
        "calendar.badge.clock", accessibilityDescription: "Current event", to: title)
      title.append(NSAttributedString(string: " \(eventPercentage)"))
    }
    return title
  }

  private func appendStatusSymbol(
    _ name: String,
    accessibilityDescription: String,
    to title: NSMutableAttributedString
  ) {
    let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
    guard
      let image = NSImage(
        systemSymbolName: name,
        accessibilityDescription: accessibilityDescription
      )?.withSymbolConfiguration(configuration)
    else { return }
    image.isTemplate = true
    let attachment = NSTextAttachment()
    attachment.image = image
    attachment.bounds = NSRect(x: 0, y: -2, width: 13, height: 13)
    title.append(NSAttributedString(attachment: attachment))
  }

  private func dayProgress(at date: Date, defaults: UserDefaults) -> Double {
    ProgressCalculator.activeDay(
      at: date,
      startMinutes: defaults.integer(forKey: SettingsKey.dayStartMinutes),
      endMinutes: defaults.integer(forKey: SettingsKey.dayEndMinutes)
    ).elapsed
  }

  private func configuredBirthDate(from defaults: UserDefaults) -> Date? {
    guard defaults.bool(forKey: SettingsKey.birthDateConfigured) else { return nil }
    let year = defaults.integer(forKey: SettingsKey.birthYear)
    let month = defaults.integer(forKey: SettingsKey.birthMonth)
    let day = defaults.integer(forKey: SettingsKey.birthDay)
    if year > 0, month > 0, day > 0 {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = .autoupdatingCurrent
      return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }
    return Date(timeIntervalSince1970: defaults.double(forKey: SettingsKey.birthTimestamp))
  }

  private func requestCurrentLocation() {
    locationProvider.requestLocation { coordinate in
      let defaults = UserDefaults.standard
      defaults.set(coordinate.latitude, forKey: SettingsKey.latitude)
      defaults.set(coordinate.longitude, forKey: SettingsKey.longitude)
      defaults.set(true, forKey: SettingsKey.locationConfigured)
    }
  }

  private func registerDefaults() {
    UserDefaults.standard.register(defaults: [
      SettingsKey.birthTimestamp: DateComponents(calendar: .current, year: 1990, month: 1, day: 1)
        .date?.timeIntervalSince1970 ?? 0,
      SettingsKey.birthDateConfigured: false,
      SettingsKey.birthYear: 0,
      SettingsKey.birthMonth: 0,
      SettingsKey.birthDay: 0,
      SettingsKey.country: Country.japan.rawValue,
      SettingsKey.lifeExpectancy: Country.japan.lifeExpectancy,
      SettingsKey.showDay: true,
      SettingsKey.showWeek: true,
      SettingsKey.weekStartsOn: WeekStartChoice.monday.rawValue,
      SettingsKey.showMonth: true,
      SettingsKey.showQuarter: true,
      SettingsKey.quarterCycle: QuarterCycle.calendar.rawValue,
      SettingsKey.showYear: true,
      SettingsKey.showLife: true,
      SettingsKey.showRemaining: false,
      SettingsKey.precision: 1,
      SettingsKey.accent: AccentChoice.system.rawValue,
      SettingsKey.dayStartMinutes: 8 * 60,
      SettingsKey.dayEndMinutes: 23 * 60,
      SettingsKey.routineName: "Work",
      SettingsKey.routineDurationMinutes: 8 * 60,
      SettingsKey.routineStartedTimestamp: 0.0,
      SettingsKey.countersJSON: "[]",
      SettingsKey.statusItemSource: "day",
      SettingsKey.lastInteractionTimestamp: 0.0,
      SettingsKey.interactionHistoryJSON: "[]",
      SettingsKey.awarenessThresholdMinutes: 90,
      SettingsKey.showSolarEvents: true,
      SettingsKey.locationConfigured: false,
      SettingsKey.latitude: 0.0,
      SettingsKey.longitude: 0.0,
    ])
  }

  private func migrateLegacySettings() {
    let defaults = UserDefaults.standard
    let history = InteractionHistory.timestamps(
      from: defaults.string(forKey: SettingsKey.interactionHistoryJSON) ?? "[]")
    if history.isEmpty {
      let legacyTimestamp = defaults.double(forKey: SettingsKey.lastInteractionTimestamp)
      if legacyTimestamp > 0 {
        InteractionHistory.record(legacyTimestamp, source: "day", in: defaults)
      }
    }
    let hasPersistedCounters =
      defaults.persistentDomain(forName: "com.davafons.timescale")?[SettingsKey.countersJSON] != nil
    if !hasPersistedCounters {
      let started = defaults.double(forKey: SettingsKey.routineStartedTimestamp)
      let counter = SharedCounter(
        name: defaults.string(forKey: SettingsKey.routineName) ?? "Work",
        targetMinutes: min(
          max(defaults.integer(forKey: SettingsKey.routineDurationMinutes), 1), 10_080),
        startedAt: started > 0
          ? ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: started)) : nil
      )
      if let data = try? JSONEncoder().encode([counter]),
        let value = String(data: data, encoding: .utf8)
      {
        defaults.set(value, forKey: SettingsKey.countersJSON)
      }
    }
    if defaults.bool(forKey: SettingsKey.birthDateConfigured),
      defaults.integer(forKey: SettingsKey.birthYear) == 0
    {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = .autoupdatingCurrent
      let legacyDate = Date(
        timeIntervalSince1970: defaults.double(forKey: SettingsKey.birthTimestamp))
      let components = calendar.dateComponents([.year, .month, .day], from: legacyDate)
      defaults.set(components.year, forKey: SettingsKey.birthYear)
      defaults.set(components.month, forKey: SettingsKey.birthMonth)
      defaults.set(components.day, forKey: SettingsKey.birthDay)
    }

    if defaults.double(forKey: SettingsKey.lifeExpectancy) <= 0 {
      defaults.set(Country.japan.lifeExpectancy, forKey: SettingsKey.lifeExpectancy)
    }
  }

}

@MainActor
final class CheckSession: ObservableObject {
  @Published var currentTimestamp: TimeInterval?
}
