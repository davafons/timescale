import SwiftUI
import TimescaleCore
import WidgetKit

@MainActor
@Observable final class AppModel {
  var calendar = CalendarSource()
  var location = IOSLocationSource()
  var locationMessage: String?
  var settings = IOSStore.loadSettings() {
    didSet {
      IOSStore.saveSettings(settings)
      WidgetCenter.shared.reloadAllTimelines()
      Task { await ReminderManager.reschedule(settings: settings, checks: checks) }
      Task {
        await ProgressActivityManager.reconcile(settings: settings)
        trackingPeriod = ProgressActivityManager.activePeriod
      }
    }
  }
  var checks = IOSStore.loadChecks()
  var now = Date.now
  var trackingPeriod: SharedPeriod? = ProgressActivityManager.activePeriod
  var trackingError: String?
  private var lastActivation: Date?

  init() {
    location.onCoordinate = { [weak self] coordinate in
      self?.settings.latitude = coordinate.latitude
      self?.settings.longitude = coordinate.longitude
    }
    location.onMessage = { [weak self] message in self?.locationMessage = message }
  }

  func activate(source: String = "app") {
    now = .now
    calendar.refresh(selectedIDs: settings.selectedCalendarIDs)
    if settings.locationMode == "automatic" { location.refresh() }
    Task {
      await ProgressActivityManager.reconcile(settings: settings, now: now)
      trackingPeriod = ProgressActivityManager.activePeriod
    }
    if let lastActivation, now.timeIntervalSince(lastActivation) < 3 { return }
    lastActivation = now
    checks.append(IOSStore.checkIn(source: source, at: now))
    WidgetCenter.shared.reloadAllTimelines()
    Task { await ReminderManager.reschedule(settings: settings, checks: checks) }
  }

  func clearHistory() {
    IOSStore.clearChecks()
    checks = []
    WidgetCenter.shared.reloadAllTimelines()
    Task { await ReminderManager.reschedule(settings: settings, checks: checks) }
  }

  func startTracking(_ period: SharedPeriod) {
    Task {
      do {
        try await ProgressActivityManager.start(period, settings: settings)
        trackingPeriod = ProgressActivityManager.activePeriod
        trackingError = nil
      } catch {
        trackingError = error.localizedDescription
      }
    }
  }

  func stopTracking() {
    Task {
      await ProgressActivityManager.stop()
      trackingPeriod = nil
    }
  }

  func useAutomaticLocation() {
    settings.locationMode = "automatic"
    location.refresh()
  }
}

@main struct TimescaleIOSApp: App {
  @Environment(\.scenePhase) private var scenePhase
  @State private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      DashboardView(model: model)
        .onChange(of: scenePhase) { _, phase in
          if phase == .active { model.activate() }
        }
        .onOpenURL { url in
          guard url.scheme == "timescale" else { return }
          model.now = .now
        }
    }
  }
}
