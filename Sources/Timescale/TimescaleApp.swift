import AppKit
import SwiftUI
import TimescaleCore

@main
@MainActor
final class TimescaleApp: NSObject, NSApplicationDelegate {
  private static let retainedDelegate = TimescaleApp()
  private var statusItem: NSStatusItem!
  private let popover = NSPopover()
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
    configurePopover()
    configureStatusItem()
    updatePercentage()

    updateTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
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
      self?.showPopover()
    }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    showPopover()
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
    if let defaultsObserver {
      NotificationCenter.default.removeObserver(defaultsObserver)
    }
  }

  private func configurePopover() {
    popover.behavior = .transient
    popover.animates = true
    popover.contentViewController = NSHostingController(rootView: ProgressPopover())
  }

  private func configureStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.autosaveName = "TimescaleStatusItem"

    guard let button = statusItem.button else { return }
    button.image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: "Timescale")
    button.imagePosition = .imageLeading
    button.target = self
    button.action = #selector(togglePopover)
    button.sendAction(on: [.leftMouseUp])
  }

  @objc private func togglePopover() {
    if popover.isShown {
      popover.performClose(nil)
    } else {
      showPopover()
    }
  }

  private func showPopover() {
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
    let start = defaults.integer(forKey: SettingsKey.dayStartMinutes)
    let end = defaults.integer(forKey: SettingsKey.dayEndMinutes)
    let progress = ProgressCalculator.activeDay(at: Date(), startMinutes: start, endMinutes: end)
    let percentage = progress.elapsed.formatted(.percent.precision(.fractionLength(0)))
    statusItem.button?.title = " " + percentage
    statusItem.button?.setAccessibilityValue("\(percentage) of waking day elapsed")
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
      SettingsKey.showSolarEvents: true,
      SettingsKey.locationConfigured: false,
      SettingsKey.latitude: 0.0,
      SettingsKey.longitude: 0.0,
    ])
  }

  private func migrateLegacySettings() {
    let defaults = UserDefaults.standard
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
