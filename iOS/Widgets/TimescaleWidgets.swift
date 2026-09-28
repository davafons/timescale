import AppIntents
import SwiftUI
import TimescaleCore
import WidgetKit

typealias WidgetPeriod = IntentPeriod

struct PeriodWidgetIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "Progress period"
  static var description = IntentDescription("Choose the period for this widget.")

  @Parameter(title: "Period")
  var period: WidgetPeriod?

  init() { period = .day }
  init(period: WidgetPeriod) { self.period = period }
}

struct NumberWidgetIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "Number period"
  static var description = IntentDescription("Choose the period for this number widget.")

  @Parameter(title: "Period")
  var period: IntentPeriod?

  init() { period = .year }
}

struct WidgetEntry: TimelineEntry {
  let date: Date
  let settings: IOSSettings
  let period: SharedPeriod?
  var events: [TimedEvent] = IOSStore.loadEvents().events
  var eventsUpdated: Date? = IOSStore.loadEvents().updated
  var checks: [InteractionHistory.Check] = IOSStore.loadChecks()

  var snapshot: PeriodSnapshot? {
    period.flatMap { settings.snapshot(for: $0, at: date) }
  }
}

struct PeriodProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> WidgetEntry {
    WidgetEntry(date: .now, settings: IOSSettings(), period: .day)
  }

  func snapshot(for configuration: PeriodWidgetIntent, in context: Context) async -> WidgetEntry {
    WidgetEntry(date: .now, settings: IOSStore.loadSettings(), period: (configuration.period ?? .day).shared)
  }

  func timeline(for configuration: PeriodWidgetIntent, in context: Context) async -> Timeline<WidgetEntry> {
    let now = Date.now
    let settings = IOSStore.loadSettings()
    let entries = (0..<9).map { step in
      WidgetEntry(
        date: now.addingTimeInterval(Double(step * 15 * 60)),
        settings: settings, period: (configuration.period ?? .day).shared)
    }
    return Timeline(entries: entries, policy: .after(now.addingTimeInterval(2 * 60 * 60)))
  }
}

struct NumberProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> WidgetEntry {
    WidgetEntry(date: .now, settings: IOSSettings(), period: .year)
  }

  func snapshot(for configuration: NumberWidgetIntent, in context: Context) async -> WidgetEntry {
    WidgetEntry(date: .now, settings: IOSStore.loadSettings(),
      period: (configuration.period ?? .year).shared)
  }

  func timeline(for configuration: NumberWidgetIntent, in context: Context) async -> Timeline<WidgetEntry> {
    let now = Date.now
    let settings = IOSStore.loadSettings()
    let entries = (0..<9).map { step in
      WidgetEntry(date: now.addingTimeInterval(Double(step * 15 * 60)),
        settings: settings, period: (configuration.period ?? .year).shared)
    }
    return Timeline(entries: entries, policy: .after(now.addingTimeInterval(2 * 60 * 60)))
  }
}

private struct OverviewProvider: TimelineProvider {
  func placeholder(in context: Context) -> WidgetEntry {
    WidgetEntry(date: .now, settings: IOSSettings(), period: nil)
  }

  func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
    completion(WidgetEntry(date: .now, settings: IOSStore.loadSettings(), period: nil))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
    let now = Date.now
    let settings = IOSStore.loadSettings()
    let entries = (0..<9).map { step in
      WidgetEntry(date: now.addingTimeInterval(Double(step * 15 * 60)),
        settings: settings, period: nil)
    }
    completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(2 * 60 * 60))))
  }
}

private enum VisualStyle { case bar, ring, number, overview }

private enum SpecialStyle { case daySun, yearBirthday, life, calendar, awareness }

private struct PeriodWidgetView: View {
  let entry: WidgetEntry
  let style: VisualStyle
  @Environment(\.widgetFamily) private var family

  private var tint: Color {
    switch entry.settings.accent {
    case "blue": .blue
    case "green": .green
    case "purple": .purple
    case "monochrome": .primary
    default: .orange
    }
  }

  var body: some View {
    Group {
      if style == .overview {
        overview
      } else if let snapshot = entry.snapshot {
        periodContent(snapshot)
      } else {
        Label("Set up Life in Timescale", systemImage: "heart")
          .font(.caption)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .containerBackground(for: .widget) { Color(uiColor: .secondarySystemGroupedBackground) }
    .widgetURL(URL(string: "timescale://dashboard"))
  }

  @ViewBuilder
  private func periodContent(_ snapshot: PeriodSnapshot) -> some View {
    let value = snapshot.displayedFraction.formatted(
      .percent.precision(.fractionLength(entry.settings.precision)))
    if family == .accessoryInline {
      Text("\(snapshot.period.title) \(value) · \(entry.date, style: .relative)")
        .font(.caption)
    } else if family == .accessoryCircular {
      if style == .number {
        VStack(spacing: 0) {
          Text(snapshot.period.title).font(.caption2)
          Text(value).font(.caption.bold()).minimumScaleFactor(0.6)
          Text(entry.date, style: .relative).font(.system(size: 7))
        }
      } else {
        Gauge(value: snapshot.elapsedFraction) {
          Text(snapshot.period.title)
        } currentValueLabel: {
          Text(value).font(.caption2).minimumScaleFactor(0.6)
        }
        .gaugeStyle(.accessoryCircular)
      }
    } else {
      VStack(alignment: .leading, spacing: 8) {
        Text(snapshot.period.title)
          .font(family == .systemMedium ? .headline : .subheadline.bold())
        if style == .ring {
          Gauge(value: snapshot.elapsedFraction) {
            Text(snapshot.period.title)
          } currentValueLabel: {
            Text(value).font(.caption.bold()).minimumScaleFactor(0.6)
          }
          .gaugeStyle(.accessoryCircular)
          .tint(tint)
        } else {
          Text(value)
            .font(style == .number ? .system(size: 36, weight: .light, design: .rounded) : .title2)
            .minimumScaleFactor(0.6)
            .monospacedDigit()
          if style == .bar {
            ProgressView(value: snapshot.elapsedFraction).tint(tint)
          }
        }
        if family != .accessoryRectangular {
          Text("As of \(entry.date.formatted(date: .omitted, time: .shortened))")
            .font(.caption2).foregroundStyle(.secondary)
        } else {
          Text(entry.date, style: .relative)
            .font(.caption2).foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var overview: some View {
    let periods = SharedPeriod.allCases.filter { entry.settings.visible.contains($0) }
    let limit = family == .systemLarge ? 6 : family == .systemMedium ? 4 : 2
    return VStack(alignment: .leading, spacing: 5) {
      Text("Timescale").font(.headline)
      ForEach(Array(periods.prefix(limit)), id: \.self) { period in
        if let snapshot = entry.settings.snapshot(for: period, at: entry.date) {
          HStack {
            Text(period.title)
            Spacer()
            Text(snapshot.displayedFraction, format: .percent.precision(
              .fractionLength(entry.settings.precision)))
              .monospacedDigit()
          }
          .font(.caption)
        }
      }
      if periods.count > limit {
        Text("+\(periods.count - limit) more in app")
          .font(.caption2).foregroundStyle(.secondary)
      }
      if family != .accessoryRectangular {
        Text("As of \(entry.date.formatted(date: .omitted, time: .shortened))")
          .font(.caption2).foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct BarWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: "timescale.bar", intent: PeriodWidgetIntent.self, provider: PeriodProvider()
    ) {
      PeriodWidgetView(entry: $0, style: .bar)
    }
    .configurationDisplayName("Period Bar")
    .description("See one chosen period at a glance.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
  }
}

private struct RingWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: "timescale.ring", intent: PeriodWidgetIntent.self, provider: PeriodProvider()
    ) {
      PeriodWidgetView(entry: $0, style: .ring)
    }
    .configurationDisplayName("Period Ring")
    .description("See one chosen period as a ring.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
  }
}

private struct NumberWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: "timescale.number", intent: NumberWidgetIntent.self, provider: NumberProvider()
    ) {
      PeriodWidgetView(entry: $0, style: .number)
    }
    .configurationDisplayName("Period Number")
    .description("See one chosen period as a large number.")
    .supportedFamilies([
      .systemSmall, .systemMedium, .accessoryInline, .accessoryCircular,
      .accessoryRectangular,
    ])
  }
}

private struct OverviewWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "timescale.overview", provider: OverviewProvider()) {
      PeriodWidgetView(entry: $0, style: .overview)
    }
    .configurationDisplayName("Overview")
    .description("Your visible periods in dashboard order.")
    .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular])
  }
}

private struct SpecialWidgetView: View {
  let entry: WidgetEntry
  let style: SpecialStyle
  @Environment(\.widgetFamily) private var family

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      switch style {
      case .daySun: daySun
      case .yearBirthday: yearBirthday
      case .life: life
      case .calendar: calendar
      case .awareness: awareness
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .containerBackground(for: .widget) { Color(uiColor: .secondarySystemGroupedBackground) }
    .widgetURL(URL(string: "timescale://dashboard"))
  }

  @ViewBuilder private var daySun: some View {
    if let snapshot = entry.settings.snapshot(for: .day, at: entry.date) {
      let solar = solarToday
      if family == .accessoryRectangular {
        Text("Day \(percent(snapshot))")
        Text(nextSolarText(solar))
          .font(.caption2)
      } else {
        Text("Day and sun").font(.headline)
        Text(percent(snapshot)).font(.title2.monospacedDigit())
        ProgressView(value: snapshot.elapsedFraction)
        Text(nextSolarText(solar))
          .font(.caption2).foregroundStyle(.secondary)
      }
    }
  }

  private var solarToday: SolarEvents? {
    guard let latitude = entry.settings.latitude,
      let longitude = entry.settings.longitude else { return nil }
    return SolarCalculator.events(
      on: entry.date, latitude: latitude, longitude: longitude)
  }

  private func nextSolarText(_ solar: SolarEvents?) -> String {
    guard let solar else { return "Add coordinates in Settings" }
    if solar.sunrise > entry.date {
      return "Sunrise \(solar.sunrise.formatted(date: .omitted, time: .shortened))"
    }
    if solar.sunset > entry.date {
      return "Sunset \(solar.sunset.formatted(date: .omitted, time: .shortened))"
    }
    return "Sunset \(solar.sunset.formatted(date: .omitted, time: .shortened))"
  }

  @ViewBuilder private var yearBirthday: some View {
    if let snapshot = entry.settings.snapshot(for: .year, at: entry.date) {
      Text("Year and birthday").font(.headline)
      Text(percent(snapshot)).font(.title2.monospacedDigit())
      if family != .accessoryRectangular {
        ProgressView(value: snapshot.elapsedFraction)
      }
      if let birthDate = entry.settings.birthDate {
        let parts = Calendar.current.dateComponents([.month, .day], from: birthDate)
        Text("Birthday: \(Calendar.current.monthSymbols[(parts.month ?? 1) - 1]) \(parts.day ?? 1)")
          .font(.caption2).foregroundStyle(.secondary)
      } else {
        Text("Add birthday in Settings")
          .font(.caption2).foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder private var life: some View {
    if let snapshot = entry.settings.snapshot(for: .life, at: entry.date),
      let birthDate = entry.settings.birthDate
    {
      Text("Life estimate").font(.headline)
      Text(percent(snapshot)).font(.title2.monospacedDigit())
      if family != .accessoryRectangular {
        ProgressView(value: snapshot.elapsedFraction)
      }
      Text("Age \(Calendar.current.dateComponents([.year], from: birthDate, to: entry.date).year ?? 0) · \(entry.settings.country) average \(entry.settings.expectedYears.formatted()) years")
        .font(.caption2).foregroundStyle(.secondary)
    } else {
      Text("Life estimate").font(.headline)
      Text("Set your birth date in Timescale")
        .font(.caption)
    }
  }

  @ViewBuilder private var calendar: some View {
    let selected = TimedEvents.select(entry.events, at: entry.date)
    if let updated = entry.eventsUpdated,
      entry.date.timeIntervalSince(updated) > 60 * 60
    {
      Text("Calendar").font(.headline)
      Text("Calendar data may be stale").font(.caption)
    } else if let event = selected.current ?? selected.next {
      if family == .accessoryInline {
        Text(event.title)
      } else if family == .accessoryCircular {
        VStack(spacing: 0) {
          Image(systemName: "calendar")
          Text(event.start, format: .dateTime.hour().minute())
            .font(.caption2)
        }
      } else {
        Text(selected.current != nil ? "Now" : "Next")
          .font(.headline)
        Text(event.title).lineLimit(family == .systemLarge ? 3 : 2)
        Text(event.start.formatted(date: .omitted, time: .shortened))
          .font(.caption2).foregroundStyle(.secondary)
        if selected.current != nil {
          ProgressView(value: event.progress(at: entry.date))
        }
      }
    } else {
      Text("Calendar").font(.headline)
      Text(calendarUnavailableText).font(.caption)
    }
  }

  private var calendarUnavailableText: String {
    guard let updated = entry.eventsUpdated else { return "Connect Calendar in Timescale" }
    if entry.date.timeIntervalSince(updated) > 60 * 60 {
      return "Calendar data may be stale"
    }
    return "No timed events coming up"
  }

  @ViewBuilder private var awareness: some View {
    if let last = entry.checks.last {
      if family == .accessoryInline {
        Text("Checked \(Date(timeIntervalSince1970: last.timestamp), style: .relative)")
      } else if family == .accessoryCircular {
        VStack {
          Image(systemName: "clock")
          Text("\(todayCount) today").font(.caption2)
        }
      } else {
        Text("Time awareness").font(.headline)
        Text("Last check-in").font(.caption2).foregroundStyle(.secondary)
        Text(Date(timeIntervalSince1970: last.timestamp), style: .relative)
          .font(.title3)
        if family != .accessoryRectangular {
          Text("\(todayCount) today").font(.caption2)
        }
      }
    } else {
      Text("Time awareness").font(.headline)
      Text("Open Timescale to start check-ins")
        .font(.caption)
    }
  }

  private var todayCount: Int {
    entry.checks.filter {
      Calendar.current.isDate($0.timestampDate, inSameDayAs: entry.date)
    }.count
  }

  private func percent(_ snapshot: PeriodSnapshot) -> String {
    snapshot.displayedFraction.formatted(
      .percent.precision(.fractionLength(entry.settings.precision)))
  }
}

private extension InteractionHistory.Check {
  var timestampDate: Date { Date(timeIntervalSince1970: timestamp) }
}

private struct DaySunWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "timescale.day-sun", provider: OverviewProvider()) {
      SpecialWidgetView(entry: $0, style: .daySun)
    }
    .configurationDisplayName("Day and Sun")
    .description("Waking day and the next solar boundary.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
  }
}

private struct YearBirthdayWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "timescale.year-birthday", provider: OverviewProvider()) {
      SpecialWidgetView(entry: $0, style: .yearBirthday)
    }
    .configurationDisplayName("Year and Birthday")
    .description("Year progress with birthday context.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
  }
}

private struct LifeWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "timescale.life", provider: OverviewProvider()) {
      SpecialWidgetView(entry: $0, style: .life)
    }
    .configurationDisplayName("Life Estimate")
    .description("Population-average life visualization.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
  }
}

private struct CalendarWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "timescale.calendar", provider: OverviewProvider()) {
      SpecialWidgetView(entry: $0, style: .calendar)
    }
    .configurationDisplayName("Calendar")
    .description("Current or next timed event.")
    .supportedFamilies([
      .systemSmall, .systemMedium, .systemLarge, .accessoryInline,
      .accessoryCircular, .accessoryRectangular,
    ])
  }
}

private struct AwarenessWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "timescale.awareness", provider: OverviewProvider()) {
      SpecialWidgetView(entry: $0, style: .awareness)
    }
    .configurationDisplayName("Time Awareness")
    .description("Last check-in and today's count.")
    .supportedFamilies([
      .systemSmall, .systemMedium, .accessoryInline, .accessoryCircular,
      .accessoryRectangular,
    ])
  }
}

@main struct TimescaleWidgetBundle: WidgetBundle {
  var body: some Widget {
    BarWidget()
    RingWidget()
    NumberWidget()
    OverviewWidget()
    DaySunWidget()
    YearBirthdayWidget()
    LifeWidget()
    CalendarWidget()
    AwarenessWidget()
    ProgressLiveActivity()
  }
}
