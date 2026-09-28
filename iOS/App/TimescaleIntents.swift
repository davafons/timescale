import AppIntents
import Foundation
import TimescaleCore
import WidgetKit

struct ProgressEntity: AppEntity {
  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Progress"
  static let defaultQuery = ProgressEntityQuery()

  var id: String
  @Property(title: "Period") var label: String
  @Property(title: "Start") var start: Date
  @Property(title: "End") var end: Date
  @Property(title: "Elapsed fraction") var elapsedFraction: Double
  @Property(title: "Displayed fraction") var displayedFraction: Double
  @Property(title: "Remaining seconds") var remainingSeconds: Double
  @Property(title: "Seconds per one percent") var onePercentSeconds: Double
  @Property(title: "Calculated at") var calculatedAt: Date

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(label)")
  }

  init(_ snapshot: PeriodSnapshot) {
    id = snapshot.period.rawValue
    label = snapshot.period.rawValue.capitalized
    start = snapshot.start
    end = snapshot.end
    elapsedFraction = snapshot.elapsedFraction
    displayedFraction = snapshot.displayedFraction
    remainingSeconds = snapshot.remainingDuration
    onePercentSeconds = snapshot.onePercentDuration
    calculatedAt = snapshot.calculatedAt
  }
}

struct ProgressEntityQuery: EntityQuery {
  func entities(for identifiers: [String]) async throws -> [ProgressEntity] {
    let settings = IOSStore.loadSettings()
    let now = Date.now
    return identifiers.compactMap(SharedPeriod.init(rawValue:))
      .compactMap { settings.snapshot(for: $0, at: now) }
      .map(ProgressEntity.init)
  }
}

private enum ProgressIntentError: LocalizedError {
  case unavailable

  var errorDescription: String? {
    "Set your birth date in Timescale to calculate Life progress."
  }
}

struct GetProgressIntent: AppIntent {
  static var title: LocalizedStringResource = "Get Progress"
  static var description = IntentDescription("Get exact progress for one Timescale period.")

  @Parameter(title: "Period")
  var period: IntentPeriod

  func perform() async throws -> some IntentResult & ReturnsValue<ProgressEntity> {
    let settings = IOSStore.loadSettings()
    guard let snapshot = settings.snapshot(for: period.shared, at: .now) else {
      throw ProgressIntentError.unavailable
    }
    return .result(value: ProgressEntity(snapshot))
  }
}

struct GetVisibleProgressIntent: AppIntent {
  static var title: LocalizedStringResource = "Get Visible Progress"
  static var description = IntentDescription("Get progress for dashboard periods in order.")

  func perform() async throws -> some IntentResult & ReturnsValue<[ProgressEntity]> {
    let settings = IOSStore.loadSettings()
    let now = Date.now
    let values = SharedPeriod.allCases
      .filter { settings.visible.contains($0) }
      .compactMap { settings.snapshot(for: $0, at: now) }
      .map(ProgressEntity.init)
    return .result(value: values)
  }
}

struct CheckInIntent: AppIntent {
  static var title: LocalizedStringResource = "Check In"
  static var description = IntentDescription("Record a deliberate Timescale check-in.")

  func perform() async throws -> some IntentResult & ReturnsValue<Date> {
    let now = Date.now
    IOSStore.checkIn(source: "shortcut", at: now)
    WidgetCenter.shared.reloadAllTimelines()
    await ReminderManager.reschedule(
      settings: IOSStore.loadSettings(), checks: IOSStore.loadChecks())
    return .result(value: now)
  }
}

struct TimescaleShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: GetProgressIntent(),
      phrases: ["Get progress in \(.applicationName)"],
      shortTitle: "Get Progress",
      systemImageName: "chart.bar.fill")
    AppShortcut(
      intent: GetVisibleProgressIntent(),
      phrases: ["Get visible progress in \(.applicationName)"],
      shortTitle: "Visible Progress",
      systemImageName: "chart.bar.xaxis")
    AppShortcut(
      intent: CheckInIntent(),
      phrases: ["Check in with \(.applicationName)"],
      shortTitle: "Check In",
      systemImageName: "clock.badge.checkmark")
  }
}
