import AppKit
import SwiftUI
import TimescaleCore

struct ProgressPopover: View {
  @ObservedObject var checkSession: CheckSession
  @ObservedObject var calendarProvider: HEYCalendarProvider
  @AppStorage(SettingsKey.birthTimestamp) private var birthTimestamp = 0.0
  @AppStorage(SettingsKey.birthDateConfigured) private var birthDateConfigured = false
  @AppStorage(SettingsKey.birthYear) private var birthYear = 0
  @AppStorage(SettingsKey.birthMonth) private var birthMonth = 0
  @AppStorage(SettingsKey.birthDay) private var birthDay = 0
  @AppStorage(SettingsKey.lifeExpectancy) private var lifeExpectancy = 84.0
  @AppStorage(SettingsKey.showDay) private var showDay = true
  @AppStorage(SettingsKey.showWeek) private var showWeek = true
  @AppStorage(SettingsKey.weekStartsOn) private var weekStartsOn = WeekStartChoice.monday.rawValue
  @AppStorage(SettingsKey.showMonth) private var showMonth = true
  @AppStorage(SettingsKey.showQuarter) private var showQuarter = true
  @AppStorage(SettingsKey.quarterCycle) private var quarterCycleRawValue =
    QuarterCycle.calendar.rawValue
  @AppStorage(SettingsKey.showYear) private var showYear = true
  @AppStorage(SettingsKey.showLife) private var showLife = true
  @AppStorage(SettingsKey.showRemaining) private var showRemaining = false
  @AppStorage(SettingsKey.precision) private var precision = 1
  @AppStorage(SettingsKey.accent) private var accentRawValue = AccentChoice.system.rawValue
  @AppStorage(SettingsKey.dayStartMinutes) private var dayStartMinutes = 8 * 60
  @AppStorage(SettingsKey.dayEndMinutes) private var dayEndMinutes = 23 * 60
  @AppStorage(SettingsKey.countersJSON) private var countersJSON = "[]"
  @AppStorage(SettingsKey.statusItemSource) private var statusItemSource = "day"
  @AppStorage(SettingsKey.collapsedProgressSourcesJSON)
  private var collapsedProgressSourcesJSON = "[]"
  @AppStorage(SettingsKey.interactionHistoryJSON) private var interactionHistoryJSON = "[]"
  @AppStorage(SettingsKey.awarenessThresholdMinutes) private var awarenessThresholdMinutes = 90
  @AppStorage(SettingsKey.showSolarEvents) private var showSolarEvents = true
  @AppStorage(SettingsKey.locationConfigured) private var locationConfigured = false
  @AppStorage(SettingsKey.latitude) private var latitude = 0.0
  @AppStorage(SettingsKey.longitude) private var longitude = 0.0
  @State private var editingCounter: SharedCounter?
  @State private var isAddingCounter = false

  private var counters: [SharedCounter] {
    guard let data = countersJSON.data(using: .utf8),
      let value = try? JSONDecoder().decode([SharedCounter].self, from: data)
    else { return [] }
    return value
  }

  private var collapsedProgressSources: Set<String> {
    guard let data = collapsedProgressSourcesJSON.data(using: .utf8),
      let sources = try? JSONDecoder().decode([String].self, from: data)
    else { return [] }
    return Set(sources)
  }

  private var accent: Color {
    AccentChoice(rawValue: accentRawValue)?.color ?? .accentColor
  }

  private var weekCalendar: Calendar {
    var calendar = Calendar.autoupdatingCurrent
    let choice = WeekStartChoice(rawValue: weekStartsOn) ?? .monday
    calendar.firstWeekday = choice.firstWeekday
    calendar.minimumDaysInFirstWeek = choice == .monday ? 4 : 1
    return calendar
  }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      VStack(alignment: .leading, spacing: LayoutScale.xLarge) {
        header(date: context.date)

        VStack(spacing: LayoutScale.xLarge) {
          if showDay {
            dayRow(at: context.date)
          }
          if showWeek {
            let calendar = weekCalendar
            ProgressRow(
              title:
                "Week \(calendar.component(.weekOfYear, from: context.date))",
              progress: ProgressCalculator.week(at: context.date, calendar: calendar),
              period: .week,
              showRemaining: showRemaining,
              precision: precision,
              accent: accent,
              isCollapsed: isProgressCollapsed("week"),
              isStatusSource: statusItemSource == "week",
              onToggleCollapsed: { toggleProgress("week") },
              onSelect: { selectSource("week") }
            )
          }
          if showMonth {
            ProgressRow(
              title: context.date.formatted(.dateTime.month(.wide)),
              progress: ProgressCalculator.month(at: context.date),
              period: .month,
              showRemaining: showRemaining, precision: precision, accent: accent,
              isCollapsed: isProgressCollapsed("month"),
              isStatusSource: statusItemSource == "month",
              onToggleCollapsed: { toggleProgress("month") },
              onSelect: { selectSource("month") })
          }
          if showQuarter {
            let cycle = QuarterCycle(rawValue: quarterCycleRawValue) ?? .calendar
            let quarter = ProgressCalculator.quarterNumber(
              at: context.date, startMonth: cycle.startMonth)
            let progress = ProgressCalculator.quarter(
              at: context.date, startMonth: cycle.startMonth)
            ProgressRow(
              title: cycle == .calendar ? "Quarter Q\(quarter)" : "Fiscal Q\(quarter)",
              progress: progress,
              period: .quarter,
              showRemaining: showRemaining,
              precision: precision,
              accent: accent,
              rangeStart: progress.start,
              rangeEnd: progress.end,
              rangeDisplay: .inclusiveDates,
              isCollapsed: isProgressCollapsed("quarter"),
              isStatusSource: statusItemSource == "quarter",
              onToggleCollapsed: { toggleProgress("quarter") },
              onSelect: { selectSource("quarter") }
            )
          }
          if showYear {
            ProgressRow(
              title: "Year \(context.date.formatted(.dateTime.year()))",
              progress: ProgressCalculator.year(at: context.date),
              period: .year,
              showRemaining: showRemaining,
              precision: precision,
              accent: accent,
              markerDate: birthday(inYearOf: context.date),
              markerDescription: birthday(inYearOf: context.date).map {
                "Birthday, \($0.formatted(.dateTime.month(.wide).day()))"
              },
              isCollapsed: isProgressCollapsed("year"),
              isStatusSource: statusItemSource == "year",
              onToggleCollapsed: { toggleProgress("year") },
              onSelect: { selectSource("year") }
            )
          }
          if showLife {
            lifeRow(at: context.date)
          }

          Divider()

          VStack(alignment: .leading, spacing: LayoutScale.medium) {
            HStack {
              Text("Counters")
                .font(TypographyScale.rowTitle)
              Spacer()
              Button {
                isAddingCounter = true
              } label: {
                Label("Add counter", systemImage: "plus.circle")
              }
              .buttonStyle(.plain)
              .foregroundStyle(.secondary)
            }

            ForEach(counters) { counter in
              counterRow(counter, at: context.date)
            }
          }

          if let event = calendarProvider.currentEvent {
            Divider()
            calendarEventRow(event, at: context.date)
          }
        }

        let todayChecks = checksToday(at: context.date)
        if !todayChecks.isEmpty {
          Divider()

          if let currentCheck = currentSessionCheck {
            if todayChecks.count > 1 {
              checkHistoryRow(
                displayedCheck: todayChecks[todayChecks.count - 2],
                currentCheck: currentCheck,
                count: todayChecks.count,
                at: context.date)
            } else {
              firstCheckRow
            }
          } else if let lastCheck = todayChecks.last {
            checkHistoryRow(
              displayedCheck: lastCheck,
              currentCheck: nil,
              count: todayChecks.count,
              at: context.date)
          }
        }

        HStack {
          Button {
            SettingsWindowController.shared.show()
          } label: {
            Label("Settings", systemImage: "gearshape")
          }
          .buttonStyle(.plain)

          Button {
            HistoryWindowController.shared.show()
          } label: {
            Label("View history", systemImage: "clock.arrow.circlepath")
          }
          .buttonStyle(.plain)

          Spacer()

          Button("Quit") { NSApplication.shared.terminate(nil) }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.secondary)
        .font(TypographyScale.action)
      }
      .padding(LayoutScale.xLarge)
      .frame(width: LayoutScale.popoverWidth)
      .sheet(item: $editingCounter) { counter in
        CounterEditor(
          counter: counter, isNew: false,
          onDelete: {
            saveCounters(counters.filter { $0.id != counter.id })
          }
        ) { updated in
          replaceCounter(updated)
        }
      }
      .sheet(isPresented: $isAddingCounter) {
        CounterEditor(counter: SharedCounter(), isNew: true) { counter in
          var updated = counters
          updated.append(counter)
          saveCounters(updated)
        }
      }
    }
  }

  @ViewBuilder
  private func counterRow(_ counter: SharedCounter, at date: Date) -> some View {
    let source = "counter:\(counter.id)"
    let elapsedSeconds = counter.elapsed(at: date)
    let duration = TimeInterval(counter.targetMinutes * 60)
    let start = counter.startedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
    let rangeStart = start ?? date.addingTimeInterval(-elapsedSeconds)
    let progress = TimeProgress(
      elapsed: duration > 0 ? elapsedSeconds / duration : 0,
      start: rangeStart,
      end: rangeStart.addingTimeInterval(duration)
    )
    VStack(alignment: .leading, spacing: LayoutScale.small) {
      ProgressRow(
        title: counter.name,
        progress: progress,
        period: .counter,
        showRemaining: false,
        precision: precision,
        accent: accent,
        isCollapsed: isProgressCollapsed(source),
        isStatusSource: statusItemSource == source,
        onToggleCollapsed: { toggleProgress(source) },
        onSelect: { selectSource(source) }
      )
      if !isProgressCollapsed(source) {
        HStack {
          Button(
            counter.startedAt == nil ? (elapsedSeconds >= duration ? "Restart" : "Start") : "Pause"
          ) {
            toggleCounter(counter)
          }
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
          Button("Edit") { editingCounter = counter }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
          if elapsedSeconds > 0 {
            Button("Reset") { resetCounter(counter) }
              .buttonStyle(.plain)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Text(formatCounterDuration(elapsedSeconds) + " / " + formatCounterDuration(duration))
            .foregroundStyle(.secondary)
            .font(TypographyScale.action)
        }
      }
    }
  }

  private func formatCounterDuration(_ seconds: TimeInterval) -> String {
    let minutes = max(Int(seconds / 60), 0)
    let hours = minutes / 60
    let remainder = minutes % 60
    if hours == 0 { return "\(remainder) min" }
    if remainder == 0 { return "\(hours) hr" }
    return "\(hours) hr \(remainder) min"
  }

  private func toggleCounter(_ counter: SharedCounter) {
    var updated = counter
    let currentElapsed = counter.elapsed(at: Date())
    if currentElapsed >= Double(counter.targetMinutes * 60) {
      updated.elapsedSeconds = 0
      updated.startedAt = ISO8601DateFormatter().string(from: Date())
    } else if counter.startedAt != nil {
      updated.elapsedSeconds = currentElapsed
      updated.startedAt = nil
    } else {
      updated.startedAt = ISO8601DateFormatter().string(from: Date())
    }
    replaceCounter(updated)
  }

  private func replaceCounter(_ counter: SharedCounter) {
    saveCounters(counters.map { $0.id == counter.id ? counter : $0 })
  }

  private func resetCounter(_ counter: SharedCounter) {
    var updated = counter
    updated.elapsedSeconds = 0
    updated.startedAt = nil
    replaceCounter(updated)
  }

  private func saveCounters(_ value: [SharedCounter]) {
    if statusItemSource.hasPrefix("counter:"),
      !value.contains(where: { "counter:\($0.id)" == statusItemSource })
    {
      statusItemSource = "day"
    }
    let activeSources = Set(value.map { "counter:\($0.id)" })
    let retainedCollapsedSources = collapsedProgressSources.filter {
      !$0.hasPrefix("counter:") || activeSources.contains($0)
    }
    if retainedCollapsedSources != collapsedProgressSources {
      saveCollapsedProgressSources(retainedCollapsedSources)
    }
    guard let data = try? JSONEncoder().encode(value),
      let string = String(data: data, encoding: .utf8)
    else { return }
    countersJSON = string
  }

  @ViewBuilder
  private func dayRow(at date: Date) -> some View {
    let progress = ProgressCalculator.activeDay(
      at: date,
      startMinutes: dayStartMinutes,
      endMinutes: dayEndMinutes
    )
    let solar =
      showSolarEvents && locationConfigured
      ? SolarCalculator.events(on: date, latitude: latitude, longitude: longitude)
      : nil
    VStack(alignment: .leading, spacing: LayoutScale.medium) {
      ProgressRow(
        title: "Day",
        progress: progress,
        period: .day,
        showRemaining: showRemaining,
        precision: precision,
        accent: accent,
        rangeStart: progress.start,
        rangeEnd: progress.end,
        isCollapsed: isProgressCollapsed("day"),
        isStatusSource: statusItemSource == "day",
        onToggleCollapsed: { toggleProgress("day") },
        onSelect: { selectSource("day") }
      )
      if !isProgressCollapsed("day"), let solar {
        SolarStrip(interval: progress, events: solar)
      }
    }
  }

  private func calendarEventRow(_ event: CalendarEvent, at date: Date) -> some View {
    let source = "hey-event:\(event.id)"
    let progress = TimeProgress(
      elapsed: event.progress(at: date), start: event.start, end: event.end)
    return VStack(alignment: .leading, spacing: LayoutScale.medium) {
      ProgressRow(
        title: event.title,
        detail: "HEY event",
        progress: progress,
        period: .event,
        showRemaining: false,
        precision: precision,
        accent: accent,
        rangeStart: event.start,
        rangeEnd: event.end,
        isCollapsed: isProgressCollapsed(source),
        isStatusSource: false,
        onToggleCollapsed: { toggleProgress(source) },
        onSelect: nil)

      if !isProgressCollapsed(source) {
        if let description = event.description?.trimmingCharacters(in: .whitespacesAndNewlines),
          !description.isEmpty
        {
          Text(description)
            .font(TypographyScale.detail)
            .foregroundStyle(.secondary)
            .lineLimit(3)
        }

        if let editURL = event.editURL {
          Button {
            NSWorkspace.shared.open(editURL)
          } label: {
            Label("Open in HEY", systemImage: "arrow.up.right.square")
          }
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
          .font(TypographyScale.action)
          .help("Open this event in HEY to view or edit it")
        }
      }
    }
  }

  private func header(date: Date) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
      Spacer()
      Text(date.formatted(date: .omitted, time: .shortened))
        .font(TypographyScale.headerTime)
        .foregroundStyle(.secondary)
    }
    .font(TypographyScale.heading)
  }

  private func birthday(inYearOf date: Date) -> Date? {
    guard let birthDate = configuredBirthDate() else { return nil }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .autoupdatingCurrent
    let birthday = calendar.dateComponents([.month, .day], from: birthDate)
    guard let month = birthday.month, let requestedDay = birthday.day,
      let monthStart = calendar.date(
        from: DateComponents(
          calendar: calendar,
          timeZone: calendar.timeZone,
          year: calendar.component(.year, from: date),
          month: month,
          day: 1,
          hour: 12
        )),
      let days = calendar.range(of: .day, in: .month, for: monthStart)
    else { return nil }

    return calendar.date(byAdding: .day, value: min(requestedDay, days.count) - 1, to: monthStart)
  }

  private func configuredBirthDate() -> Date? {
    guard birthDateConfigured else { return nil }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .autoupdatingCurrent
    if birthYear > 0, birthMonth > 0, birthDay > 0 {
      return calendar.date(
        from: DateComponents(year: birthYear, month: birthMonth, day: birthDay, hour: 12))
    }
    return Date(timeIntervalSince1970: birthTimestamp)
  }

  private func decimalAge(at date: Date, birthDate: Date) -> Double {
    guard date >= birthDate else { return 0 }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .autoupdatingCurrent
    let wholeYears = max(calendar.dateComponents([.year], from: birthDate, to: date).year ?? 0, 0)
    guard let previousBirthday = calendar.date(byAdding: .year, value: wholeYears, to: birthDate),
      let nextBirthday = calendar.date(byAdding: .year, value: wholeYears + 1, to: birthDate)
    else { return Double(wholeYears) }
    let yearDuration = nextBirthday.timeIntervalSince(previousBirthday)
    guard yearDuration > 0 else { return Double(wholeYears) }
    return Double(wholeYears) + date.timeIntervalSince(previousBirthday) / yearDuration
  }

  @ViewBuilder
  private func lifeRow(at date: Date) -> some View {
    if let birthDate = configuredBirthDate(),
      let progress = ProgressCalculator.life(
        at: date,
        birthDate: birthDate,
        expectedYears: lifeExpectancy
      )
    {
      let age = decimalAge(at: date, birthDate: birthDate)
      ProgressRow(
        title: "Life",
        detail:
          "Age \(age.formatted(.number.precision(.fractionLength(1)))) / \(lifeExpectancy.formatted(.number.precision(.fractionLength(0...1))))",
        progress: progress,
        period: .life,
        showRemaining: showRemaining,
        precision: precision,
        accent: accent,
        isCollapsed: isProgressCollapsed("life"),
        isStatusSource: statusItemSource == "life",
        onToggleCollapsed: { toggleProgress("life") },
        onSelect: { selectSource("life") }
      )
    } else {
      VStack(alignment: .leading, spacing: LayoutScale.small) {
        HStack {
          Text("Life").font(TypographyScale.rowTitle)
          Spacer()
          Text("Not configured").foregroundStyle(.secondary)
        }
        Text("Add your birth date in Settings")
          .font(TypographyScale.detail)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func selectSource(_ source: String) {
    statusItemSource = source
  }

  private func isProgressCollapsed(_ source: String) -> Bool {
    collapsedProgressSources.contains(source)
  }

  private func toggleProgress(_ source: String) {
    var sources = collapsedProgressSources
    if !sources.insert(source).inserted {
      sources.remove(source)
    }
    saveCollapsedProgressSources(sources)
  }

  private func saveCollapsedProgressSources(_ sources: Set<String>) {
    guard let data = try? JSONEncoder().encode(sources.sorted()),
      let value = String(data: data, encoding: .utf8)
    else { return }
    collapsedProgressSourcesJSON = value
  }

  private var checkHistory: [InteractionHistory.Check] {
    InteractionHistory.checks(from: interactionHistoryJSON)
  }

  private var currentSessionCheck: InteractionHistory.Check? {
    guard let timestamp = checkSession.currentTimestamp,
      let latest = checkHistory.last,
      latest.timestamp == timestamp
    else { return nil }
    return latest
  }

  private var firstCheckRow: some View {
    VStack(alignment: .leading, spacing: LayoutScale.small) {
      HStack(alignment: .firstTextBaseline) {
        Text("First check today")
          .font(TypographyScale.rowTitle)
        Spacer()
        Text("0% since a prior check")
          .font(TypographyScale.rowValue)
      }
      Text("Your next check will show the time and waking-day percentage since this one.")
        .font(TypographyScale.detail)
        .foregroundStyle(.secondary)
    }
  }

  private func checkHistoryRow(
    displayedCheck: InteractionHistory.Check,
    currentCheck: InteractionHistory.Check?,
    count: Int,
    at date: Date
  ) -> some View {
    let displayedDate = Date(timeIntervalSince1970: displayedCheck.timestamp)
    let comparisonDate = currentCheck.map { Date(timeIntervalSince1970: $0.timestamp) } ?? date
    let elapsed = max(comparisonDate.timeIntervalSince(displayedDate), 0)
    let dayPercentage = wakingDayPercentage(from: displayedDate, to: comparisonDate)
    return VStack(alignment: .leading, spacing: LayoutScale.small) {
      HStack(alignment: .firstTextBaseline) {
        Text(count == 1 ? "1 check today" : "\(count) checks today")
          .font(TypographyScale.rowTitle)
        Spacer()
        VStack(alignment: .trailing, spacing: LayoutScale.xSmall) {
          Text(
            "\(elapsedSince(displayedDate, at: comparisonDate)) · \(dayPercentage.formatted(.number.precision(.fractionLength(1))))%"
          )
          .font(TypographyScale.rowValue)
          Text("Since last check")
            .supportingTextStyle()
        }
      }
      if elapsed >= Double(awarenessThresholdMinutes * 60) {
        Label("Longer than your reminder interval", systemImage: "bell")
          .font(TypographyScale.detail)
          .foregroundStyle(.orange)
      }
    }
  }

  private func checksToday(at date: Date) -> [InteractionHistory.Check] {
    let calendar = Calendar.autoupdatingCurrent
    return checkHistory.filter {
      calendar.isDate(Date(timeIntervalSince1970: $0.timestamp), inSameDayAs: date)
    }
  }

  private var typicalCheckGap: String {
    let checks = checkHistory
    guard checks.count > 2 else { return "not enough data yet" }
    let gaps = zip(checks.dropFirst(), checks).map { $0.timestamp - $1.timestamp }
    let average = gaps.reduce(0, +) / Double(gaps.count)
    return elapsedSince(Date(timeIntervalSince1970: 0), at: Date(timeIntervalSince1970: average))
  }

  private var checkSourceNames: [String: String] {
    var names = Dictionary(uniqueKeysWithValues: [
      ("day", "Day"), ("week", "Week"), ("month", "Month"),
      ("quarter", "Quarter"), ("year", "Year"), ("life", "Life"),
    ])
    for counter in counters {
      names["counter:\(counter.id)"] = counter.name
    }
    return names
  }

  private func sourceLabel(_ source: String) -> String {
    checkSourceNames[source] ?? (source.hasPrefix("counter:") ? "Deleted counter" : "Unknown")
  }

  private func wakingDayPercentage(from start: Date, to end: Date) -> Double {
    let progress = ProgressCalculator.activeDay(
      at: end,
      startMinutes: dayStartMinutes,
      endMinutes: dayEndMinutes)
    let duration = progress.end.timeIntervalSince(progress.start)
    guard duration > 0 else { return 0 }
    return min(max(end.timeIntervalSince(start) / duration * 100, 0), 100)
  }

  private func elapsedSince(_ start: Date, at end: Date) -> String {
    let seconds = max(end.timeIntervalSince(start), 0)
    if seconds < 60 { return "less than 1 min" }
    let minutes = Int(seconds / 60)
    let hours = minutes / 60
    let days = hours / 24
    if days > 0 {
      let remainderHours = hours % 24
      return remainderHours == 0 ? "\(days) d" : "\(days) d \(remainderHours) hr"
    }
    let remainderMinutes = minutes % 60
    if hours == 0 { return "\(minutes) min" }
    return remainderMinutes == 0 ? "\(hours) hr" : "\(hours) hr \(remainderMinutes) min"
  }
}

private struct SolarStrip: View {
  let interval: TimeProgress
  let events: SolarEvents

  private var positions: (sunrise: Double, sunset: Double) {
    let duration = interval.end.timeIntervalSince(interval.start)
    return (
      min(max(events.sunrise.timeIntervalSince(interval.start) / duration, 0), 1),
      min(max(events.sunset.timeIntervalSince(interval.start) / duration, 0), 1)
    )
  }

  var body: some View {
    VStack(spacing: LayoutScale.none) {
      HStack {
        solarLabel(for: events.sunrise, systemImage: "sunrise")
        Spacer()
        solarLabel(for: events.sunset, systemImage: "sunset")
      }
      .supportingTextStyle()

      GeometryReader { geometry in
        let values = positions
        ZStack(alignment: .leading) {
          Capsule().fill(.indigo.opacity(0.16))
          if values.sunset > values.sunrise {
            Capsule()
              .fill(.yellow.opacity(0.7))
              .frame(width: geometry.size.width * (values.sunset - values.sunrise))
              .offset(x: geometry.size.width * values.sunrise)
          }
        }
      }
      .frame(height: 4)
      .padding(.top, LayoutScale.xSmall)
      .accessibilityLabel(
        "Daylight from \(events.sunrise.formatted(date: .omitted, time: .shortened)) to \(events.sunset.formatted(date: .omitted, time: .shortened))"
      )
    }
  }

  private func solarLabel(for date: Date, systemImage: String) -> some View {
    HStack(spacing: LayoutScale.xSmall) {
      Image(systemName: systemImage)
      Text(date.formatted(date: .omitted, time: .shortened))
    }
    .fixedSize()
  }
}

private struct ProgressRow: View {
  let title: String
  var detail: String? = nil
  let progress: TimeProgress
  let period: ProgressPeriod
  let showRemaining: Bool
  let precision: Int
  let accent: Color
  var rangeStart: Date? = nil
  var rangeEnd: Date? = nil
  var rangeDisplay: RangeDisplay = .times
  var markerDate: Date? = nil
  var markerDescription: String? = nil
  var isCollapsed = false
  var isStatusSource = false
  var onToggleCollapsed: (() -> Void)? = nil
  var onSelect: (() -> Void)? = nil

  private var displayedProgress: Double {
    showRemaining ? 1 - progress.elapsed : progress.elapsed
  }

  var body: some View {
    VStack(alignment: .leading, spacing: LayoutScale.none) {
      HStack(alignment: .firstTextBaseline, spacing: LayoutScale.small) {
        Button {
          onToggleCollapsed?()
        } label: {
          HStack(alignment: .firstTextBaseline, spacing: LayoutScale.small) {
            HStack(alignment: .firstTextBaseline, spacing: LayoutScale.small) {
              Text(title).font(TypographyScale.rowTitle)
              if let detail {
                Text(detail)
                  .font(TypographyScale.detail)
                  .foregroundStyle(.secondary)
              }
              Text("\(remainingDuration) left")
                .supportingTextStyle()
            }
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
              .font(TypographyScale.detail)
              .foregroundStyle(.secondary)
          }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(isCollapsed ? "Show" : "Hide") \(title) progress bar")

        Spacer(minLength: LayoutScale.small)

        Text("1% = \(onePercentDuration)")
          .supportingTextStyle()
        Button {
          onSelect?()
        } label: {
          HStack(alignment: .firstTextBaseline, spacing: LayoutScale.xSmall) {
            Text(displayedProgress, format: .percent.precision(.fractionLength(precision)))
              .font(TypographyScale.rowValue)
            if isStatusSource {
              Text("★")
                .font(TypographyScale.supporting)
                .foregroundStyle(.secondary)
            }
          }
        }
        .buttonStyle(.plain)
        .help(menuBarActionLabel)
        .accessibilityLabel(menuBarActionLabel)
      }

      if !isCollapsed {
        if let rangeStart, let rangeEnd {
          HStack {
            Text(rangeLabel(for: rangeStart, isEnd: false))
            Spacer()
            Text(rangeLabel(for: rangeEnd, isEnd: true))
          }
          .supportingTextStyle()
          .padding(.top, LayoutScale.small)
        }
        ZStack {
          ProgressView(value: displayedProgress)
            .tint(accent)

          if let markerPosition {
            GeometryReader { geometry in
              Circle()
                .fill(.primary)
                .frame(width: 7, height: 7)
                .position(
                  x: 3.5 + markerPosition * max(geometry.size.width - 7, 0),
                  y: geometry.size.height / 2
                )
            }
            .accessibilityElement()
            .accessibilityLabel(markerDescription ?? "Marker")
          }
        }
        .frame(height: 8)
        .padding(.top, rangeStart == nil ? LayoutScale.medium : LayoutScale.xSmall)
      }
    }
  }

  private var duration: TimeInterval {
    progress.end.timeIntervalSince(progress.start)
  }

  private var menuBarActionLabel: String {
    isStatusSource ? "Showing \(title) in the menu bar" : "Show \(title) in the menu bar"
  }

  private var remainingDuration: String {
    if period == .year {
      let current = progress.start.addingTimeInterval(duration * progress.elapsed)
      let components = Calendar.autoupdatingCurrent.dateComponents(
        [.month, .day], from: current, to: progress.end)
      return "\(max(components.month ?? 0, 0))mo \(max(components.day ?? 0, 0))d"
    }
    return format(duration * (1 - progress.elapsed), for: period, isOnePercent: false)
  }

  private var markerPosition: Double? {
    guard let markerDate, duration > 0 else { return nil }
    return min(max(markerDate.timeIntervalSince(progress.start) / duration, 0), 1)
  }

  private func rangeLabel(for date: Date, isEnd: Bool) -> String {
    switch rangeDisplay {
    case .times:
      return date.formatted(date: .omitted, time: .shortened)
    case .inclusiveDates:
      let displayedDate =
        isEnd
        ? Calendar.autoupdatingCurrent.date(byAdding: .day, value: -1, to: date) ?? date
        : date
      return displayedDate.formatted(.dateTime.month(.abbreviated).day())
    }
  }

  private var onePercentDuration: String {
    format(duration / 100, for: period, isOnePercent: true)
  }

  private func format(_ seconds: TimeInterval, for period: ProgressPeriod, isOnePercent: Bool)
    -> String
  {
    let seconds = max(seconds, 0)
    let day = 24.0 * 60 * 60

    if period == .life {
      if isOnePercent {
        let months = seconds / (365.2425 / 12 * day)
        return "\(months.formatted(.number.precision(.fractionLength(0...1))))mo"
      }
      let years = seconds / (365.2425 * day)
      return "\(years.formatted(.number.precision(.fractionLength(1))))y"
    }

    if seconds >= 30 * day {
      return "\(Int((seconds / day).rounded(.down)))d"
    }
    if seconds >= day {
      let days = Int(seconds / day)
      let hours = Int(seconds.truncatingRemainder(dividingBy: day) / 3600)
      return hours == 0 ? "\(days)d" : "\(days)d \(hours)h"
    }
    if seconds >= 3600 {
      let hours = Int(seconds / 3600)
      let minutes = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
      return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }

    let minutes = seconds / 60
    return "\(minutes.formatted(.number.precision(.fractionLength(0...1))))m"
  }
}

private enum ProgressPeriod {
  case day
  case week
  case month
  case quarter
  case year
  case life
  case counter
  case event
}

private enum RangeDisplay {
  case times
  case inclusiveDates
}

private struct CheckHistoryView: View {
  let checks: [InteractionHistory.Check]
  let sourceNames: [String: String]

  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      VStack(alignment: .leading, spacing: LayoutScale.medium) {
        HStack {
          Text("Check history")
            .font(TypographyScale.heading)
          Spacer()
          Text("\(checks.count) total")
            .font(TypographyScale.detail)
            .foregroundStyle(.secondary)
        }
        if checks.isEmpty {
          Text("No checks yet.")
            .foregroundStyle(.secondary)
        } else {
          ScrollView {
            LazyVStack(alignment: .leading, spacing: LayoutScale.small) {
              ForEach(Array(checks.reversed().enumerated()), id: \.offset) { _, check in
                HStack(alignment: .firstTextBaseline) {
                  VStack(alignment: .leading, spacing: LayoutScale.xSmall) {
                    Text(
                      Date(timeIntervalSince1970: check.timestamp)
                        .formatted(date: .abbreviated, time: .standard))
                    Text(sourceLabel(check.source))
                      .foregroundStyle(.secondary)
                  }
                  Spacer()
                  Text(elapsedSince(check.timestamp, at: context.date))
                    .foregroundStyle(.secondary)
                }
                .font(TypographyScale.detail)
              }
            }
          }
        }
      }
      .padding(LayoutScale.xLarge)
    }
    .frame(width: 430, height: 420)
  }

  private func elapsedSince(_ timestamp: TimeInterval, at now: Date) -> String {
    let minutes = max(Int(now.timeIntervalSince(Date(timeIntervalSince1970: timestamp)) / 60), 0)
    if minutes < 1 { return "now" }
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h ago" }
    return "\(hours / 24)d ago"
  }

  private func sourceLabel(_ source: String) -> String {
    sourceNames[source] ?? (source.hasPrefix("counter:") ? "Deleted counter" : "Unknown")
  }
}

private struct CounterEditor: View {
  @Environment(\.dismiss) private var dismiss
  @State private var counter: SharedCounter
  @State private var targetHours: Int
  @State private var targetMinuteComponent: Int
  @State private var elapsedHours: Int
  @State private var elapsedMinuteComponent: Int
  @State private var isRunning: Bool
  let isNew: Bool
  let onDelete: (() -> Void)?
  let onSave: (SharedCounter) -> Void

  init(
    counter: SharedCounter,
    isNew: Bool,
    onDelete: (() -> Void)? = nil,
    onSave: @escaping (SharedCounter) -> Void
  ) {
    var editable = counter
    editable.elapsedSeconds = counter.elapsed(at: Date())
    editable.startedAt = nil
    _counter = State(initialValue: editable)
    _targetHours = State(initialValue: editable.targetMinutes / 60)
    _targetMinuteComponent = State(initialValue: editable.targetMinutes % 60)
    let elapsedMinutes = max(Int(editable.elapsedSeconds.rounded() / 60), 0)
    _elapsedHours = State(initialValue: elapsedMinutes / 60)
    _elapsedMinuteComponent = State(initialValue: elapsedMinutes % 60)
    _isRunning = State(initialValue: counter.startedAt != nil)
    self.isNew = isNew
    self.onDelete = onDelete
    self.onSave = onSave
  }

  var body: some View {
    VStack(alignment: .leading, spacing: LayoutScale.large) {
      Text(isNew ? "Add counter" : "Edit counter")
        .font(TypographyScale.heading)
      TextField("Counter name", text: $counter.name)
      durationFields(
        title: "Target duration",
        hours: $targetHours,
        minutes: $targetMinuteComponent)
      durationFields(
        title: "Elapsed time",
        hours: $elapsedHours,
        minutes: $elapsedMinuteComponent)
      Toggle(isNew ? "Start now" : "Keep running", isOn: $isRunning)
      Text("Durations use hours and minutes. You can adjust elapsed time before saving.")
        .font(TypographyScale.detail)
        .foregroundStyle(.secondary)
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
        if !isNew, let onDelete {
          Button("Delete", role: .destructive) {
            onDelete()
            dismiss()
          }
        }
        Button("Save") {
          counter.targetMinutes = targetDuration
          counter.elapsedSeconds = Double(min(elapsedDuration, targetDuration) * 60)
          counter.startedAt =
            isRunning
            ? ISO8601DateFormatter().string(from: Date())
            : nil
          onSave(counter)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(counter.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(LayoutScale.xxLarge)
    .frame(width: 390)
  }

  private func durationFields(
    title: String,
    hours: Binding<Int>,
    minutes: Binding<Int>
  ) -> some View {
    VStack(alignment: .leading, spacing: LayoutScale.small) {
      Text(title)
        .font(TypographyScale.rowTitle)
      HStack(spacing: LayoutScale.small) {
        TextField("Hours", value: hours, format: .number)
          .multilineTextAlignment(.trailing)
          .frame(width: 68)
        Text("hr")
          .foregroundStyle(.secondary)
        TextField("Minutes", value: minutes, format: .number)
          .multilineTextAlignment(.trailing)
          .frame(width: 68)
        Text("min")
          .foregroundStyle(.secondary)
      }
    }
  }

  private var targetDuration: Int {
    let hours = min(max(targetHours, 0), 168)
    let minutes = min(max(targetMinuteComponent, 0), 59)
    return min(max(hours * 60 + minutes, 1), 10_080)
  }

  private var elapsedDuration: Int {
    let hours = max(elapsedHours, 0)
    let minutes = min(max(elapsedMinuteComponent, 0), 59)
    return max(hours * 60 + minutes, 0)
  }
}

private struct SupportingTextStyle: ViewModifier {
  func body(content: Content) -> some View {
    content
      .font(TypographyScale.supporting)
      .foregroundStyle(.secondary)
  }
}

extension View {
  fileprivate func supportingTextStyle() -> some View {
    modifier(SupportingTextStyle())
  }
}
