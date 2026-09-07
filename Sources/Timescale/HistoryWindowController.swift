import AppKit
import SwiftUI
import TimescaleCore

@MainActor
final class HistoryWindowController: NSWindowController, NSWindowDelegate {
  static let shared = HistoryWindowController()

  private init() {
    let hostingController = NSHostingController(
      rootView: HistoryView().frame(width: 620, height: 680))
    let window = NSWindow(contentViewController: hostingController)
    window.title = "Timescale History"
    window.styleMask = [.titled, .closable, .resizable]
    window.minSize = NSSize(width: 520, height: 480)
    window.isReleasedWhenClosed = false
    window.center()
    super.init(window: window)
    window.delegate = self
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func show() {
    guard let window else { return }
    window.center()
    showWindow(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }
}

private struct HistoryView: View {
  @AppStorage(SettingsKey.interactionHistoryJSON) private var interactionHistoryJSON = "[]"

  private var checks: [InteractionHistory.Check] {
    InteractionHistory.checks(from: interactionHistoryJSON)
      .sorted { $0.timestamp < $1.timestamp }
  }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 30)) { context in
      let dayChecks = checksOnDay(containing: context.date)
      ScrollView {
        VStack(alignment: .leading, spacing: LayoutScale.xLarge) {
          header(dayChecks: dayChecks, at: context.date)
          hourlyActivity(dayChecks: dayChecks)
          appSummary(dayChecks: dayChecks)
          checkList(dayChecks: dayChecks, at: context.date)
        }
        .padding(LayoutScale.xLarge)
      }
    }
  }

  private func header(dayChecks: [InteractionHistory.Check], at date: Date) -> some View {
    VStack(alignment: .leading, spacing: LayoutScale.small) {
      Text("Today’s checks")
        .font(TypographyScale.heading)
      HStack(alignment: .firstTextBaseline) {
        Text("\(dayChecks.count)")
          .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
        Text(dayChecks.count == 1 ? "time opened" : "times opened")
          .foregroundStyle(.secondary)
        Spacer()
        Text("Average gap \(averageGap(in: dayChecks))")
          .font(TypographyScale.detail)
          .foregroundStyle(.secondary)
      }
      Text(
        "Each check records the progress source and the frontmost app at the moment you open Timescale."
      )
      .font(TypographyScale.detail)
      .foregroundStyle(.secondary)
    }
  }

  private func hourlyActivity(dayChecks: [InteractionHistory.Check]) -> some View {
    let calendar = Calendar.autoupdatingCurrent
    let counts = (0..<24).map { hour in
      dayChecks.filter {
        calendar.component(.hour, from: Date(timeIntervalSince1970: $0.timestamp)) == hour
      }.count
    }
    let maximum = max(counts.max() ?? 0, 1)

    return VStack(alignment: .leading, spacing: LayoutScale.small) {
      Text("Check-ins by hour")
        .font(TypographyScale.rowTitle)
      GeometryReader { geometry in
        HStack(alignment: .bottom, spacing: 2) {
          ForEach(Array(counts.enumerated()), id: \.offset) { _, count in
            Capsule()
              .fill(count == 0 ? Color.secondary.opacity(0.16) : Color.accentColor)
              .frame(
                height: max(
                  count == 0 ? 2 : 4,
                  geometry.size.height * CGFloat(count) / CGFloat(maximum)
                )
              )
              .accessibilityLabel("\(count) check-ins")
          }
        }
      }
      .frame(height: 92)
      HStack {
        Text("12 AM")
        Spacer()
        Text("6 AM")
        Spacer()
        Text("Noon")
        Spacer()
        Text("6 PM")
        Spacer()
        Text("Now")
      }
      .font(TypographyScale.detail)
      .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
  }

  private func appSummary(dayChecks: [InteractionHistory.Check]) -> some View {
    let applications = applications(in: dayChecks)
    return Group {
      if !applications.isEmpty {
        VStack(alignment: .leading, spacing: LayoutScale.small) {
          Text("Frontmost apps at check-in")
            .font(TypographyScale.rowTitle)
          HStack(spacing: LayoutScale.medium) {
            ForEach(applications.prefix(4), id: \.name) { application in
              Text("\(application.name) \(application.count)")
                .font(TypographyScale.detail)
                .padding(.horizontal, LayoutScale.small)
                .padding(.vertical, LayoutScale.xSmall)
                .background(.secondary.opacity(0.12), in: Capsule())
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private func checkList(dayChecks: [InteractionHistory.Check], at date: Date) -> some View {
    VStack(alignment: .leading, spacing: LayoutScale.small) {
      Text("Check history")
        .font(TypographyScale.rowTitle)
      if dayChecks.isEmpty {
        Text("Open Timescale from the menu bar to start today’s history.")
          .font(TypographyScale.detail)
          .foregroundStyle(.secondary)
      } else {
        ForEach(dayChecks.indices.reversed(), id: \.self) { index in
          let check = dayChecks[index]
          HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: LayoutScale.xSmall) {
              Text(
                Date(timeIntervalSince1970: check.timestamp)
                  .formatted(date: .omitted, time: .shortened))
              Text(detail(for: check))
                .font(TypographyScale.detail)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(intervalLabel(for: index, in: dayChecks))
              .font(TypographyScale.detail)
              .foregroundStyle(.secondary)
          }
          if index > 0 { Divider() }
        }
      }
    }
  }

  private func checksOnDay(containing date: Date) -> [InteractionHistory.Check] {
    let calendar = Calendar.autoupdatingCurrent
    return checks.filter {
      calendar.isDate(Date(timeIntervalSince1970: $0.timestamp), inSameDayAs: date)
    }
  }

  private func applications(in checks: [InteractionHistory.Check]) -> [(name: String, count: Int)] {
    var counts: [String: Int] = [:]
    for check in checks {
      guard let appName = check.appName else { continue }
      counts[appName, default: 0] += 1
    }
    return counts.map { (name: $0.key, count: $0.value) }
      .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
  }

  private func averageGap(in checks: [InteractionHistory.Check]) -> String {
    guard checks.count > 1 else { return "—" }
    let gaps = zip(checks.dropFirst(), checks).map { $0.timestamp - $1.timestamp }
    return duration(gaps.reduce(0, +) / Double(gaps.count))
  }

  private func intervalLabel(
    for index: Int,
    in checks: [InteractionHistory.Check]
  ) -> String {
    guard index > 0 else { return "First today" }
    let seconds = checks[index].timestamp - checks[index - 1].timestamp
    return "After \(duration(seconds))"
  }

  private func detail(for check: InteractionHistory.Check) -> String {
    let source = check.source.hasPrefix("counter:") ? "Custom counter" : check.source.capitalized
    if let appName = check.appName { return "\(source) · \(appName)" }
    return source
  }

  private func duration(_ seconds: TimeInterval) -> String {
    let minutes = max(Int(seconds / 60), 0)
    if minutes < 1 { return "under 1 min" }
    let hours = minutes / 60
    let remainingMinutes = minutes % 60
    if hours == 0 { return "\(minutes) min" }
    return remainingMinutes == 0 ? "\(hours) hr" : "\(hours) hr \(remainingMinutes) min"
  }
}
