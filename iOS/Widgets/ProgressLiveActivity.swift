import ActivityKit
import SwiftUI
import WidgetKit

struct ProgressLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: ProgressActivityAttributes.self) { context in
      VStack(alignment: .leading, spacing: 8) {
        Text(context.attributes.period.capitalized)
          .font(.headline)
        ProgressView(
          timerInterval: context.state.start...context.state.end,
          countsDown: context.state.remaining)
        Text(context.state.remaining ? "remaining" : "elapsed")
          .font(.caption).foregroundStyle(.secondary)
        Text("Tracking ends \(context.state.sessionEnd, style: .time)")
          .font(.caption2).foregroundStyle(.secondary)
      }
      .padding()
      .activityBackgroundTint(.black.opacity(0.85))
      .activitySystemActionForegroundColor(.orange)
      .widgetURL(URL(string: "timescale://dashboard"))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text(context.attributes.period.capitalized)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(context.state.remaining ? "left" : "elapsed")
        }
        DynamicIslandExpandedRegion(.bottom) {
          ProgressView(
            timerInterval: context.state.start...context.state.end,
            countsDown: context.state.remaining)
        }
      } compactLeading: {
        Image(systemName: "hourglass")
      } compactTrailing: {
        Text(context.attributes.period.prefix(1).uppercased())
      } minimal: {
        Image(systemName: "hourglass")
      }
      .widgetURL(URL(string: "timescale://dashboard"))
    }
  }
}
