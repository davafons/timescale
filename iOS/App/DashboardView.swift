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
                    tint: tint
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
            Text("\(model.checks.count) check-ins saved")
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
          EventDetailScreen(event: event)
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
            model.settings.visible.contains($0) && model.settings.snapshot(for: $0) != nil
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
        VStack(alignment: .leading, spacing: 8) {
          Text(selected.current != nil ? "Current event" : "Next event").font(.headline)
          Text(event.title).font(.title3)
          Text("\(event.start.formatted(date: .abbreviated, time: .shortened)) – \(event.end.formatted(date: .abbreviated, time: .shortened))")
            .font(.caption).foregroundStyle(.secondary)
          if selected.current != nil {
            ProgressView(value: event.progress(at: model.now)).tint(tint)
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
  let toggle: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Button(action: toggle) {
        HStack {
          Text(snapshot.period.title).font(.headline)
          Spacer()
          Text(snapshot.displayedFraction, format: .percent.precision(
            .fractionLength(precision)))
            .font(.title3.monospacedDigit())
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
        ProgressView(value: snapshot.elapsedFraction)
          .tint(tint)
        Text("\(snapshot.start.formatted(date: .abbreviated, time: .shortened)) – \(snapshot.end.formatted(date: .abbreviated, time: .shortened))")
          .font(.caption).foregroundStyle(.secondary)
        Text("Time left: \(timeLeft) · 1%: \(onePercent)")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding()
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    .accessibilityElement(children: .combine)
  }
}
