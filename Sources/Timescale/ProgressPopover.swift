import AppKit
import SwiftUI
import TimescaleCore

struct ProgressPopover: View {
  @AppStorage(SettingsKey.birthTimestamp) private var birthTimestamp = 0.0
  @AppStorage(SettingsKey.birthDateConfigured) private var birthDateConfigured = false
  @AppStorage(SettingsKey.birthYear) private var birthYear = 0
  @AppStorage(SettingsKey.birthMonth) private var birthMonth = 0
  @AppStorage(SettingsKey.birthDay) private var birthDay = 0
  @AppStorage(SettingsKey.lifeExpectancy) private var lifeExpectancy = 84.0
  @AppStorage(SettingsKey.showDay) private var showDay = true
  @AppStorage(SettingsKey.showWeek) private var showWeek = true
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
  @AppStorage(SettingsKey.showSolarEvents) private var showSolarEvents = true
  @AppStorage(SettingsKey.locationConfigured) private var locationConfigured = false
  @AppStorage(SettingsKey.latitude) private var latitude = 0.0
  @AppStorage(SettingsKey.longitude) private var longitude = 0.0

  private var accent: Color {
    AccentChoice(rawValue: accentRawValue)?.color ?? .accentColor
  }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 30)) { context in
      VStack(alignment: .leading, spacing: LayoutScale.xLarge) {
        header(date: context.date)

        VStack(spacing: LayoutScale.xLarge) {
          if showDay {
            dayRow(at: context.date)
          }
          if showWeek {
            ProgressRow(
              title:
                "Week \(Calendar.autoupdatingCurrent.component(.weekOfYear, from: context.date))",
              progress: ProgressCalculator.week(at: context.date),
              period: .week,
              showRemaining: showRemaining,
              precision: precision,
              accent: accent
            )
          }
          if showMonth {
            ProgressRow(
              title: context.date.formatted(.dateTime.month(.wide)),
              progress: ProgressCalculator.month(at: context.date),
              period: .month,
              showRemaining: showRemaining, precision: precision, accent: accent)
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
              rangeDisplay: .inclusiveDates
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
              }
            )
          }
          if showLife {
            lifeRow(at: context.date)
          }
        }

        HStack {
          Button {
            SettingsWindowController.shared.show()
          } label: {
            Label("Settings", systemImage: "gearshape")
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
    }
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
        rangeEnd: progress.end
      )
      if let solar {
        SolarStrip(interval: progress, events: solar)
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
        accent: accent
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

  private var displayedProgress: Double {
    showRemaining ? 1 - progress.elapsed : progress.elapsed
  }

  var body: some View {
    VStack(alignment: .leading, spacing: LayoutScale.none) {
      HStack(alignment: .firstTextBaseline) {
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

        Spacer(minLength: LayoutScale.small)

        HStack(alignment: .firstTextBaseline, spacing: LayoutScale.small) {
          Text("1% = \(onePercentDuration)")
            .supportingTextStyle()
          Text(displayedProgress, format: .percent.precision(.fractionLength(precision)))
            .font(TypographyScale.rowValue)
        }
      }

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
    .accessibilityElement(children: .combine)
    .accessibilityLabel(title)
    .accessibilityValue(
      "\(displayedProgress.formatted(.percent.precision(.fractionLength(precision)))) \(showRemaining ? "remaining" : "elapsed"), \(remainingDuration) left, one percent equals \(onePercentDuration)"
    )
  }

  private var duration: TimeInterval {
    progress.end.timeIntervalSince(progress.start)
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
}

private enum RangeDisplay {
  case times
  case inclusiveDates
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
