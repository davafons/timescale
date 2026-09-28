import ActivityKit
import Foundation
import TimescaleCore

private enum ProgressActivityError: LocalizedError {
  case unavailable
  case ended

  var errorDescription: String? {
    switch self {
    case .unavailable: "Live Activities are unavailable for this period."
    case .ended: "This period has ended. Choose an active period."
    }
  }
}

@MainActor
enum ProgressActivityManager {
  static var isSupported: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

  static var activePeriod: SharedPeriod? {
    Activity<ProgressActivityAttributes>.activities
      .first(where: { $0.activityState == .active })
      .flatMap { SharedPeriod(rawValue: $0.attributes.period) }
  }

  static func start(_ period: SharedPeriod, settings: IOSSettings) async throws {
    let now = Date.now
    guard isSupported, settings.visible.contains(period),
      let snapshot = settings.snapshot(for: period, at: now)
    else { throw ProgressActivityError.unavailable }
    guard snapshot.end > now else { throw ProgressActivityError.ended }
    await stop()
    let sessionEnd = min(snapshot.end, now.addingTimeInterval(8 * 60 * 60))
    let state = ProgressActivityAttributes.ContentState(
      start: snapshot.start, end: snapshot.end,
      sessionEnd: sessionEnd, remaining: settings.showRemaining)
    let content = ActivityContent(state: state, staleDate: sessionEnd)
    _ = try Activity<ProgressActivityAttributes>.request(
      attributes: ProgressActivityAttributes(period: period.rawValue),
      content: content, pushType: nil)
  }

  static func stop() async {
    for activity in Activity<ProgressActivityAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }

  static func reconcile(settings: IOSSettings, now: Date = .now) async {
    for activity in Activity<ProgressActivityAttributes>.activities {
      guard let period = SharedPeriod(rawValue: activity.attributes.period),
        settings.visible.contains(period),
        let snapshot = settings.snapshot(for: period, at: now),
        snapshot.start == activity.content.state.start,
        snapshot.end == activity.content.state.end,
        now < activity.content.state.sessionEnd
      else {
        await activity.end(nil, dismissalPolicy: .immediate)
        continue
      }
      if activity.content.state.remaining != settings.showRemaining {
        var state = activity.content.state
        state.remaining = settings.showRemaining
        await activity.update(ActivityContent(state: state, staleDate: state.sessionEnd))
      }
    }
  }
}
