import SwiftUI
import TimescaleCore

struct HistoryScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Bindable var model: AppModel
  @State private var confirmingClear = false

  var body: some View {
    NavigationStack {
      List {
        Section("Summary") {
          LabeledContent("Today", value: "\(todayCount)")
          if let last = model.checks.last {
            LabeledContent("Last check-in") {
              Text(Date(timeIntervalSince1970: last.timestamp), style: .relative)
            }
          }
          if let averageGap {
            LabeledContent("Average gap") {
              Text(Duration.seconds(averageGap).formatted(
                .units(allowed: [.hours, .minutes], width: .abbreviated)))
            }
          }
        }
        Section("Check-ins by hour") {
          HourlyHistoryChart(checks: model.checks)
            .frame(height: 112)
            .accessibilityLabel("Hourly distribution of check-ins")
        }
        Section("Recent check-ins") {
          ForEach(model.checks.indices.reversed(), id: \.self) { index in
            let check = model.checks[index]
            VStack(alignment: .leading) {
              let date = Date(timeIntervalSince1970: check.timestamp)
              Text(date.formatted(date: .abbreviated, time: .shortened))
              Text(sourceLabel(check.source))
                .font(.caption).foregroundStyle(.secondary)
              if index > 0 {
                let prior = model.checks[index - 1]
                Text(gapDescription(from: prior, to: check))
                  .font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        }
        if !model.checks.isEmpty {
          Button("Clear history", role: .destructive) { confirmingClear = true }
        }
      }
      .navigationTitle("History")
      .toolbar { ToolbarItem(placement: .confirmationAction) {
        Button("Done") { dismiss() }
      }}
      .confirmationDialog("Clear all check-in history?", isPresented: $confirmingClear) {
        Button("Clear history", role: .destructive) { model.clearHistory() }
      }
    }
  }

  private var todayCount: Int {
    model.checks.filter {
      Calendar.current.isDateInToday(Date(timeIntervalSince1970: $0.timestamp))
    }.count
  }

  private var averageGap: TimeInterval? {
    guard model.checks.count > 1 else { return nil }
    let gaps = zip(model.checks, model.checks.dropFirst()).map {
      $1.timestamp - $0.timestamp
    }
    return gaps.reduce(0, +) / Double(gaps.count)
  }

  private func sourceLabel(_ source: String) -> String {
    switch source {
    case "app": "App open"
    case "widget": "Widget open"
    case "shortcut": "Shortcut"
    default: "Unavailable source (\(source))"
    }
  }

  private func gapDescription(
    from prior: InteractionHistory.Check, to check: InteractionHistory.Check
  ) -> String {
    let gap = max(0, check.timestamp - prior.timestamp)
    let date = Date(timeIntervalSince1970: check.timestamp)
    let day = ProgressCalculator.activeDay(
      at: date, startMinutes: model.settings.dayStartMinutes,
      endMinutes: model.settings.dayEndMinutes)
    let fraction = day.end.timeIntervalSince(day.start) > 0
      ? min(gap / day.end.timeIntervalSince(day.start), 1) : 0
    let duration = Duration.seconds(gap).formatted(
      .units(allowed: [.days, .hours, .minutes], width: .abbreviated))
    let longGap = gap >= Double(model.settings.longGapMinutes * 60)
      ? " · Long gap" : ""
    return "After \(duration) · \(fraction.formatted(.percent.precision(.fractionLength(1)))) of a waking day\(longGap)"
  }
}

private struct HourlyHistoryChart: View {
  let checks: [InteractionHistory.Check]

  var body: some View {
    GeometryReader { geometry in
      let counts = (0..<24).map { hour in
        checks.filter {
          Calendar.current.component(.hour, from: Date(timeIntervalSince1970: $0.timestamp))
            == hour
        }.count
      }
      let maximum = max(counts.max() ?? 0, 1)
      VStack {
        HStack(alignment: .bottom, spacing: 2) {
          ForEach(0..<24, id: \.self) { hour in
            Capsule()
              .fill(counts[hour] == 0 ? Color.secondary.opacity(0.2) : Color.accentColor)
              .frame(height: max(2, geometry.size.height * 0.75
                * CGFloat(counts[hour]) / CGFloat(maximum)))
              .accessibilityLabel("\(hour):00, \(counts[hour]) check-ins")
          }
        }
        HStack {
          Text("12 AM")
          Spacer()
          Text("6 AM")
          Spacer()
          Text("Noon")
          Spacer()
          Text("6 PM")
        }
        .font(.caption2).foregroundStyle(.secondary)
      }
    }
  }
}
