import SwiftUI
import TimescaleCore

struct DashboardView: View {
  @Bindable var model: AppModel
  @State private var showingSettings = false
  @State private var showingHistory = false
  @State private var selectedEventID: String?
  @State private var proposedTrackingPeriod: SharedPeriod?

  private var tint: Color {
    switch model.settings.accent {
    case "blue": .blue
    case "green": .green
    case "purple": .purple
    case "monochrome": .primary
    default: .orange
    }
  }

  private var todayCheckCount: Int {
    model.checks.filter {
      Calendar.current.isDateInToday(Date(timeIntervalSince1970: $0.timestamp))
    }.count
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          if let headline = model.settings.snapshot(for: model.settings.headline, at: model.now) {
            VStack(alignment: .leading, spacing: 8) {
              Text(model.now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.subheadline).foregroundStyle(.secondary)
              Text(headline.period.title).font(.largeTitle.bold())
              Text(headline.displayedFraction, format: .percent.precision(
                .fractionLength(model.settings.precision)))
                .font(.system(size: 54, weight: .light, design: .rounded))
                .monospacedDigit()
              Text(model.settings.showRemaining ? "remaining" : "elapsed")
                .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
          }

          VStack(spacing: 12) {
            ForEach(SharedPeriod.allCases, id: \.self) { period in
              if model.settings.visible.contains(period) {
                if let snapshot = model.settings.snapshot(for: period, at: model.now) {
                  ProgressRow(
                    snapshot: snapshot, precision: model.settings.precision,
                    collapsed: model.settings.collapsed.contains(period),
                    tint: tint, settings: model.settings
                  ) {
                    if model.settings.collapsed.contains(period) {
                      model.settings.collapsed.remove(period)
                    } else {
                      model.settings.collapsed.insert(period)
                    }
                  }
                } else if period == .life {
                  Label("Set your birth date to show Life", systemImage: "heart")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
              }
            }
          }

          if let latitude = model.settings.latitude,
            let longitude = model.settings.longitude,
            let solar = SolarCalculator.events(
              on: model.now, latitude: latitude, longitude: longitude)
          {
            VStack(alignment: .leading, spacing: 8) {
              Text("Sun").font(.headline)
              Text("Sunrise \(solar.sunrise.formatted(date: .omitted, time: .shortened))")
              Text("Sunset \(solar.sunset.formatted(date: .omitted, time: .shortened))")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
          }

          calendarSection
          trackingSection

          VStack(alignment: .leading, spacing: 6) {
            Text("Time awareness").font(.headline)
            Text("\(todayCheckCount) check-ins today")
            if let last = model.checks.last {
              let date = Date(timeIntervalSince1970: last.timestamp)
              Text("Last check-in \(date.formatted(date: .abbreviated, time: .shortened))")
                .foregroundStyle(.secondary)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding()
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .padding()
      }
      .background(Color(uiColor: .systemGroupedBackground))
      .navigationTitle("Timescale")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("History", systemImage: "clock.arrow.circlepath") {
            showingHistory = true
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Settings", systemImage: "gearshape") {
            showingSettings = true
          }
        }
      }
      .sheet(isPresented: $showingSettings) { SettingsScreen(model: model) }
      .sheet(isPresented: $showingHistory) { HistoryScreen(model: model) }
      .sheet(item: Binding(
        get: { selectedEventID.map(EventID.init) },
        set: { selectedEventID = $0?.id }
      )) { selection in
        if let event = model.calendar.event(for: selection.id) {
          NavigationStack {
            EventDetailScreen(event: event)
              .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                  Button("Done") { selectedEventID = nil }
                }
              }
          }
        }
      }
      .confirmationDialog(
        "Track \(proposedTrackingPeriod?.title ?? "progress")?",
        isPresented: Binding(
          get: { proposedTrackingPeriod != nil },
          set: { if !$0 { proposedTrackingPeriod = nil } })
      ) {
        Button("Start Tracking") {
          if let period = proposedTrackingPeriod { model.startTracking(period) }
          proposedTrackingPeriod = nil
        }
      } message: {
        Text("A Live Activity is a temporary tracking session. It ends after up to eight hours, even when the selected period lasts longer.")
      }
    }
  }

  @ViewBuilder
  private var trackingSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Live Activity").font(.headline)
      if let period = model.trackingPeriod {
        Text("Tracking \(period.title)")
        Button("Stop Tracking", role: .destructive) { model.stopTracking() }
      } else if ProgressActivityManager.isSupported {
        Menu("Start Tracking") {
          ForEach(SharedPeriod.allCases.filter {
            model.settings.visible.contains($0)
              && (model.settings.snapshot(for: $0, at: model.now)?.end ?? .distantPast)
                > model.now
          }, id: \.self) { period in
            Button(period.title) { proposedTrackingPeriod = period }
          }
        }
      } else {
        Text("Live Activities are unavailable on this device.")
          .font(.caption).foregroundStyle(.secondary)
      }
      if let error = model.trackingError {
        Text(error).font(.caption).foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
  }

  @ViewBuilder
  private var calendarSection: some View {
    if model.calendar.accessGranted {
      let selected = TimedEvents.select(model.calendar.events, at: model.now)
      if let event = selected.current ?? selected.next {
        let wakingDay = ProgressCalculator.activeDay(
          at: model.now, startMinutes: model.settings.dayStartMinutes,
          endMinutes: model.settings.dayEndMinutes)
        let leadIn = selected.current == nil
          ? TimedEvents.leadIn(to: event.start, at: model.now, wakingDay: wakingDay)
          : nil
        VStack(alignment: .leading, spacing: 8) {
          Text(selected.current != nil ? "Current event" : "Next event").font(.headline)
          Text(event.title).font(.title3)
          Text("\(event.start.formatted(date: .abbreviated, time: .shortened)) – \(event.end.formatted(date: .abbreviated, time: .shortened))")
            .font(.caption).foregroundStyle(.secondary)
          if selected.current != nil {
            ProgressView(value: event.progress(at: model.now)).tint(tint)
          } else if let leadIn {
            ProgressView(value: leadIn.elapsed).tint(tint)
            Text("Eight-hour lead-in · starts \(event.start, style: .relative)")
              .font(.caption).foregroundStyle(.secondary)
          }
          if let detail = event.detail, !detail.isEmpty {
            Text(detail).font(.caption).lineLimit(3)
          }
          Text(event.source).font(.caption2).foregroundStyle(.secondary)
          Button("Open in Calendar") { selectedEventID = event.id }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
      } else {
        VStack(alignment: .leading, spacing: 8) {
          Text("Calendar").font(.headline)
          Text(model.settings.selectedCalendarIDs?.isEmpty == true
            ? "Select a calendar in Settings to show timed events."
            : "No current or upcoming timed events in the selected calendars.")
            .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
      }
    } else {
      VStack(alignment: .leading, spacing: 8) {
        Text("Calendar").font(.headline)
        Text("Connect Apple Calendar to see current and upcoming timed events. Subscribed HEY calendars can appear here too.")
          .font(.subheadline).foregroundStyle(.secondary)
        Button("Connect Calendar") {
          Task { await model.calendar.requestAccess() }
        }
        if let error = model.calendar.errorMessage {
          Text(error).font(.caption).foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
  }
}

private struct EventID: Identifiable {
  let id: String
  init(_ id: String) { self.id = id }
}

private struct ProgressRow: View {
  let snapshot: PeriodSnapshot
  let precision: Int
  let collapsed: Bool
  let tint: Color
  let settings: IOSSettings
  let toggle: () -> Void

  private var markers: [ProgressMarker] {
    switch snapshot.period {
    case .day:
      guard let latitude = settings.latitude, let longitude = settings.longitude else {
        return []
      }
      let days = [snapshot.start, snapshot.end]
      let events = days.compactMap {
        SolarCalculator.events(on: $0, latitude: latitude, longitude: longitude)
      }
      return events.flatMap { solar in
        [ProgressMarker(
          label: "Sunrise", symbol: "sunrise.fill", date: solar.sunrise,
          detail: solar.sunrise.formatted(date: .omitted, time: .shortened)),
          ProgressMarker(
            label: "Sunset", symbol: "sunset.fill", date: solar.sunset,
            detail: solar.sunset.formatted(date: .omitted, time: .shortened))]
      }.filter { snapshot.start <= $0.date && $0.date <= snapshot.end }
        .uniqued()
    case .year:
      guard let birthDate = settings.birthDate,
        let birthday = BirthdayCalculator.birthday(
          inYearOf: snapshot.start, birthDate: birthDate)
      else { return [] }
      return [ProgressMarker(
        label: "Birthday", symbol: "gift.fill", date: birthday,
        detail: birthday.formatted(.dateTime.month(.wide).day()))]
    default:
      return []
    }
  }

  private var lifeContext: String? {
    guard snapshot.period == .life, let birthDate = settings.birthDate else { return nil }
    let age = max(0, Calendar.current.dateComponents(
      [.year], from: birthDate, to: snapshot.calculatedAt).year ?? 0)
    return "Age \(age) · \(settings.country) population average \(settings.expectedYears.formatted()) years"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Button(action: toggle) {
        HStack {
          Text(snapshot.period.title).font(.headline)
          Spacer()
          VStack(alignment: .trailing, spacing: 1) {
            Text(snapshot.displayedFraction, format: .percent.precision(
              .fractionLength(precision)))
              .font(.title3.monospacedDigit())
            Text(settings.showRemaining ? "remaining" : "elapsed")
              .font(.caption2).foregroundStyle(.secondary)
          }
          Image(systemName: collapsed ? "chevron.down" : "chevron.up")
            .font(.caption)
        }
      }
      .buttonStyle(.plain)
      if !collapsed {
        let timeLeft = Duration.seconds(snapshot.remainingDuration)
          .formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated))
        let onePercent = Duration.seconds(snapshot.onePercentDuration)
          .formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated))
        MarkerProgressBar(
          progress: snapshot.elapsedFraction, markers: markers,
          start: snapshot.start, end: snapshot.end, tint: tint)
          .frame(height: 16)
        if !markers.isEmpty {
          ForEach(markers) { marker in
            Label("\(marker.label) \(marker.detail)",
              systemImage: marker.symbol)
              .font(.caption).foregroundStyle(.secondary)
          }
        }
        if let lifeContext {
          Text(lifeContext).font(.caption).foregroundStyle(.secondary)
        }
        Text("\(snapshot.start.formatted(date: .abbreviated, time: .shortened)) – \(snapshot.end.formatted(date: .abbreviated, time: .shortened))")
          .font(.caption).foregroundStyle(.secondary)
        Text("Time left: \(timeLeft) · 1%: \(onePercent)")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding()
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(snapshot.period.title), \(settings.showRemaining ? "remaining" : "elapsed"), \(snapshot.displayedFraction.formatted(.percent.precision(.fractionLength(precision)))), from \(snapshot.start.formatted()), to \(snapshot.end.formatted())")
  }
}

private struct ProgressMarker: Identifiable {
  let label: String
  let symbol: String
  let date: Date
  let detail: String
  var id: String { "\(label)-\(date.timeIntervalSince1970)" }
}

private extension Array where Element == ProgressMarker {
  func uniqued() -> [ProgressMarker] {
    var seen = Set<String>()
    return filter { seen.insert($0.id).inserted }
  }
}

private struct MarkerProgressBar: View {
  let progress: Double
  let markers: [ProgressMarker]
  let start: Date
  let end: Date
  let tint: Color

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Capsule().fill(.secondary.opacity(0.2)).frame(height: 8)
        Capsule().fill(tint)
          .frame(width: geometry.size.width * min(max(progress, 0), 1), height: 8)
        ForEach(markers) { marker in
          let fraction = end > start
            ? min(max(marker.date.timeIntervalSince(start) / end.timeIntervalSince(start), 0), 1)
            : 0
          Circle().fill(.primary)
            .frame(width: 10, height: 10)
            .offset(x: geometry.size.width * fraction - 5)
        }
      }
      .frame(height: geometry.size.height)
    }
  }
}
