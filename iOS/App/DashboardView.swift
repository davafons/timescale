import SwiftUI
import TimescaleCore

struct DashboardView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        VStack(alignment: .leading, spacing: 22) {
          dashboardHeader

          if let headline = model.settings.snapshot(for: model.settings.headline, at: model.now) {
            HeadlineProgressCard(snapshot: headline, settings: model.settings, tint: tint)
          } else {
            Button {
              showingSettings = true
            } label: {
              Label("Add your birth date to see Life progress", systemImage: "heart")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
                .dashboardGlass()
            }
            .buttonStyle(.plain)
          }

          VStack(alignment: .leading, spacing: 12) {
            sectionHeading("The bigger picture", subtitle: "Your time, at a glance")
            VStack(spacing: 0) {
              let visible = SharedPeriod.allCases.filter { model.settings.visible.contains($0) }
              ForEach(visible, id: \.self) { period in
                if let snapshot = model.settings.snapshot(for: period, at: model.now) {
                  ProgressRow(
                    snapshot: snapshot, precision: model.settings.precision,
                    collapsed: model.settings.collapsed.contains(period),
                    tint: tint, settings: model.settings
                  ) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                      if model.settings.collapsed.contains(period) {
                        model.settings.collapsed.remove(period)
                      } else {
                        model.settings.collapsed.insert(period)
                      }
                    }
                  }
                } else if period == .life {
                  Button {
                    showingSettings = true
                  } label: {
                    Label("Set your birth date to show Life", systemImage: "heart")
                      .font(.subheadline)
                      .frame(maxWidth: .infinity, alignment: .leading)
                      .padding(20)
                  }
                  .buttonStyle(.plain)
                }
                if period != visible.last {
                  Divider().overlay(.primary.opacity(0.03)).padding(.horizontal, 20)
                }
              }
            }
            .dashboardGlass()
          }

          if let latitude = model.settings.latitude,
            let longitude = model.settings.longitude,
            let solar = SolarCalculator.events(
              on: model.now, latitude: latitude, longitude: longitude)
          {
            solarCard(solar)
          }

          calendarSection
          trackingSection
          awarenessCard

        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 24)
      }
      .scrollIndicators(.hidden)
      .background { DashboardSky(date: model.now, tint: tint).ignoresSafeArea() }
      .navigationTitle("Timescale")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .tint(tint)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("History", systemImage: "clock.arrow.circlepath") {
            showingHistory = true
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Settings", systemImage: "slider.horizontal.3") {
            showingSettings = true
          }
        }
      }
      .sheet(isPresented: $showingSettings) { SettingsScreen(model: model) }
      .sheet(isPresented: $showingHistory) { HistoryScreen(model: model) }
      .sheet(
        item: Binding(
          get: { selectedEventID.map(EventID.init) },
          set: { selectedEventID = $0?.id }
        )
      ) { selection in
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
        Text(
          "A Live Activity is a temporary tracking session. It ends after up to eight hours, even when the selected period lasts longer."
        )
      }
    }
  }

  private var dashboardHeader: some View {
    HStack(alignment: .center) {
      VStack(alignment: .leading, spacing: 5) {
        Text(model.now, format: .dateTime.weekday(.wide))
          .font(.system(.largeTitle, design: .rounded, weight: .bold))
        Text(model.now, format: .dateTime.month(.wide).day().year())
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 12)
      Button {
        showingHistory = true
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "sparkle")
            .foregroundStyle(tint)
          Text("\(todayCheckCount)").monospacedDigit()
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .modifier(DashboardGlassControl())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(todayCheckCount) check-ins today. View history")
    }
    .padding(.horizontal, 2)
  }

  private func sectionHeading(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title).font(.system(.title3, design: .rounded, weight: .semibold))
      Text(subtitle).font(.caption).foregroundStyle(.secondary)
    }
    .padding(.horizontal, 4)
  }

  private func solarCard(_ solar: SolarEvents) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      Label("A day in the light", systemImage: "sun.max")
        .font(.system(.headline, design: .rounded))
      HStack(spacing: 20) {
        solarTime("Sunrise", symbol: "sunrise.fill", date: solar.sunrise)
        Spacer()
        Rectangle().fill(.primary.opacity(0.1)).frame(width: 1, height: 42)
        Spacer()
        solarTime("Sunset", symbol: "sunset.fill", date: solar.sunset)
      }
    }
    .padding(22)
    .dashboardGlass()
  }

  private func solarTime(_ title: String, symbol: String, date: Date) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
      Text(date, format: .dateTime.hour().minute())
        .font(.system(.title3, design: .rounded, weight: .medium))
        .monospacedDigit()
    }
  }

  private var awarenessCard: some View {
    Button {
      showingHistory = true
    } label: {
      HStack(spacing: 14) {
        Image(systemName: "sparkles")
          .font(.title3)
          .foregroundStyle(tint)
          .frame(width: 46, height: 46)
          .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
        VStack(alignment: .leading, spacing: 4) {
          Text("Time awareness").font(.system(.headline, design: .rounded))
          Text("\(todayCheckCount) check-ins today").font(.subheadline)
          if let last = model.checks.last {
            Text(
              "Last at \(Date(timeIntervalSince1970: last.timestamp).formatted(date: .omitted, time: .shortened))"
            )
            .font(.caption).foregroundStyle(.secondary)
          }
        }
        Spacer()
        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
      .padding(20)
      .dashboardGlass()
    }
    .buttonStyle(.plain)
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
          ForEach(
            SharedPeriod.allCases.filter {
              model.settings.visible.contains($0)
                && (model.settings.snapshot(for: $0, at: model.now)?.end ?? .distantPast)
                  > model.now
            }, id: \.self
          ) { period in
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
    .dashboardGlass()
  }

  @ViewBuilder
  private var calendarSection: some View {
    if model.calendar.accessGranted {
      let selected = TimedEvents.select(model.calendar.events, at: model.now)
      if let event = selected.current ?? selected.next {
        let wakingDay = ProgressCalculator.activeDay(
          at: model.now, startMinutes: model.settings.dayStartMinutes,
          endMinutes: model.settings.dayEndMinutes)
        let leadIn =
          selected.current == nil
          ? TimedEvents.leadIn(to: event.start, at: model.now, wakingDay: wakingDay)
          : nil
        VStack(alignment: .leading, spacing: 8) {
          Text(selected.current != nil ? "Current event" : "Next event").font(.headline)
          Text(event.title).font(.title3)
          Text(
            "\(event.start.formatted(date: .abbreviated, time: .shortened)) – \(event.end.formatted(date: .abbreviated, time: .shortened))"
          )
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
          if let message = model.calendar.missingSelectedMessage {
            Text(message)
              .font(.caption).foregroundStyle(.secondary)
          }
          Button("Open in Calendar") { selectedEventID = event.id }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .dashboardGlass()
      } else {
        VStack(alignment: .leading, spacing: 8) {
          Text("Calendar").font(.headline)
          Text(
            model.settings.selectedCalendarIDs?.isEmpty == true
              ? "Select a calendar in Settings to show timed events."
              : "No current or upcoming timed events in the selected calendars."
          )
          .font(.subheadline).foregroundStyle(.secondary)
          if let message = model.calendar.missingSelectedMessage {
            Text(message)
              .font(.caption).foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .dashboardGlass()
      }
    } else {
      VStack(alignment: .leading, spacing: 8) {
        Text("Calendar").font(.headline)
        Text(
          "Connect Apple Calendar to see current and upcoming timed events. Subscribed HEY calendars can appear here too."
        )
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
      .dashboardGlass()
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
        [
          ProgressMarker(
            label: "Sunrise", symbol: "sunrise.fill", date: solar.sunrise,
            detail: solar.sunrise.formatted(date: .omitted, time: .shortened)),
          ProgressMarker(
            label: "Sunset", symbol: "sunset.fill", date: solar.sunset,
            detail: solar.sunset.formatted(date: .omitted, time: .shortened)),
        ]
      }.filter { snapshot.start <= $0.date && $0.date <= snapshot.end }
        .uniqued()
    case .year:
      guard let birthDate = settings.birthDate?.date(),
        let birthday = BirthdayCalculator.birthday(
          inYearOf: snapshot.start, birthDate: birthDate)
      else { return [] }
      return [
        ProgressMarker(
          label: "Birthday", symbol: "gift.fill", date: birthday,
          detail: birthday.formatted(.dateTime.month(.wide).day()))
      ]
    default:
      return []
    }
  }

  private var lifeContext: String? {
    guard snapshot.period == .life,
      let birthDate = settings.birthDate?.date()
    else { return nil }
    let age = max(
      0,
      Calendar.current.dateComponents(
        [.year], from: birthDate, to: snapshot.calculatedAt
      ).year ?? 0)
    return
      "Age \(age) · \(settings.country) population average \(settings.expectedYears.formatted()) years"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Button(action: toggle) {
        HStack {
          Image(systemName: snapshot.period.dashboardSymbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
          Text(snapshot.period.title).font(.system(.headline, design: .rounded))
          Spacer()
          VStack(alignment: .trailing, spacing: 1) {
            Text(
              snapshot.displayedFraction,
              format: .percent.precision(
                .fractionLength(precision))
            )
            .font(.system(.title3, design: .rounded, weight: .medium).monospacedDigit())
            Text(settings.showRemaining ? "remaining" : "elapsed")
              .font(.caption2).foregroundStyle(.secondary)
          }
          Image(systemName: collapsed ? "chevron.down" : "chevron.up")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      if !collapsed {
        let timeLeft = Duration.seconds(snapshot.remainingDuration)
          .formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated))
        let onePercent = Duration.seconds(snapshot.onePercentDuration)
          .formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated))
        MarkerProgressBar(
          progress: snapshot.elapsedFraction, markers: markers,
          start: snapshot.start, end: snapshot.end, tint: tint
        )
        .frame(height: 16)
        if !markers.isEmpty {
          ForEach(markers) { marker in
            Label(
              "\(marker.label) \(marker.detail)",
              systemImage: marker.symbol
            )
            .font(.caption).foregroundStyle(.secondary)
          }
        }
        if let lifeContext {
          Text(lifeContext).font(.caption).foregroundStyle(.secondary)
        }
        Text(
          "\(snapshot.start.formatted(date: .abbreviated, time: .shortened)) – \(snapshot.end.formatted(date: .abbreviated, time: .shortened))"
        )
        .font(.caption).foregroundStyle(.secondary)
        Text("Time left: \(timeLeft) · 1%: \(onePercent)")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(20)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(snapshot.period.title), \(settings.showRemaining ? "remaining" : "elapsed"), \(snapshot.displayedFraction.formatted(.percent.precision(.fractionLength(precision)))), from \(snapshot.start.formatted()), to \(snapshot.end.formatted())"
    )
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
        Capsule().fill(.primary.opacity(0.08)).frame(height: 7)
        Capsule().fill(
          LinearGradient(
            colors: [tint.opacity(0.55), tint], startPoint: .leading, endPoint: .trailing)
        )
        .frame(width: geometry.size.width * min(max(progress, 0), 1), height: 7)
        ForEach(markers) { marker in
          let fraction =
            end > start
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

private struct HeadlineProgressCard: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let snapshot: PeriodSnapshot
  let settings: IOSSettings
  let tint: Color

  private var title: String {
    snapshot.period == .day ? "Your waking day" : "Your \(snapshot.period.title.lowercased())"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 12) {
          headlineLabel
          modeBadge
        }
      } else {
        HStack {
          headlineLabel
          Spacer()
          modeBadge
        }
      }

      Text(
        snapshot.displayedFraction,
        format: .percent.precision(
          .fractionLength(settings.precision))
      )
      .font(.system(size: 72, weight: .light, design: .rounded))
      .tracking(-3)
      .monospacedDigit()
      .lineLimit(1)
      .minimumScaleFactor(0.55)
      .contentTransition(.numericText())
      .accessibilityLabel(
        "\(title), \(snapshot.displayedFraction.formatted(.percent.precision(.fractionLength(settings.precision)))) \(settings.showRemaining ? "remaining" : "elapsed")"
      )

      VStack(spacing: 8) {
        DayOrbit(
          progress: snapshot.elapsedFraction, symbol: snapshot.period.dashboardSymbol, tint: tint
        )
        .frame(height: 80)
        .accessibilityHidden(true)
        HStack {
          Text(boundary(snapshot.start))
          Spacer()
          Text(boundary(snapshot.end))
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
      }

      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 16) {
          metric("Time left", value: duration(snapshot.remainingDuration), symbol: "hourglass")
          metric("Each 1%", value: duration(snapshot.onePercentDuration), symbol: "circle.dotted")
        }
      } else {
        HStack(spacing: 16) {
          metric("Time left", value: duration(snapshot.remainingDuration), symbol: "hourglass")
          Rectangle().fill(.primary.opacity(0.08)).frame(width: 1, height: 34)
          metric("Each 1%", value: duration(snapshot.onePercentDuration), symbol: "circle.dotted")
        }
        .padding(.top, 4)
      }
    }
    .padding(24)
    .dashboardGlass(cornerRadius: 30)
  }

  private var headlineLabel: some View {
    Label(title, systemImage: snapshot.period.dashboardSymbol)
      .font(.subheadline.weight(.medium))
      .foregroundStyle(.secondary)
  }

  private var modeBadge: some View {
    Text(settings.showRemaining ? "REMAINING" : "ELAPSED")
      .font(.system(size: 10, weight: .semibold))
      .tracking(1.4)
      .foregroundStyle(tint)
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(tint.opacity(0.09), in: Capsule())
  }

  private func metric(_ title: String, value: String, symbol: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(title, systemImage: symbol)
        .font(.caption).foregroundStyle(.secondary)
      Text(value)
        .font(.system(.subheadline, design: .rounded, weight: .semibold))
        .monospacedDigit()
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func duration(_ seconds: TimeInterval) -> String {
    Duration.seconds(seconds).formatted(
      .units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
  }

  private func boundary(_ date: Date) -> String {
    snapshot.period == .day
      ? date.formatted(date: .omitted, time: .shortened)
      : date.formatted(.dateTime.month(.abbreviated).day())
  }
}

private struct DayOrbit: View {
  let progress: Double
  let symbol: String
  let tint: Color

  var body: some View {
    GeometryReader { geometry in
      let width = max(0, geometry.size.width - 24)
      let height = max(0, geometry.size.height - 24)
      let fraction = min(max(progress, 0), 1)
      ZStack(alignment: .topLeading) {
        OrbitPath(fraction: 1)
          .stroke(tint.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [3, 5]))
        OrbitPath(fraction: fraction)
          .stroke(
            LinearGradient(
              colors: [tint.opacity(0.15), tint], startPoint: .leading, endPoint: .trailing),
            style: StrokeStyle(lineWidth: 2, lineCap: .round))
        Image(systemName: symbol)
          .font(.system(size: 22, weight: .medium))
          .foregroundStyle(tint)
          .frame(width: 32, height: 32)
          .background(tint.opacity(0.12), in: Circle())
          .shadow(color: tint.opacity(0.4), radius: 14)
          .position(x: 12 + width * fraction, y: 12 + height * (1 - sin(.pi * fraction)))
      }
    }
  }
}

private struct OrbitPath: Shape {
  var fraction: Double

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let width = max(0, rect.width - 24)
    let height = max(0, rect.height - 24)
    path.move(to: CGPoint(x: 12, y: 12 + height))
    for step in 1...80 {
      let progress = fraction * Double(step) / 80
      path.addLine(
        to: CGPoint(
          x: 12 + width * progress,
          y: 12 + height * (1 - sin(.pi * progress))))
    }
    return path
  }
}

private struct DashboardSky: View {
  let date: Date
  let tint: Color
  @Environment(\.colorScheme) private var colorScheme

  private var isEvening: Bool {
    let hour = Calendar.current.component(.hour, from: date)
    return hour < 6 || hour >= 18
  }

  var body: some View {
    GeometryReader { geometry in
      let dark = colorScheme == .dark
      ZStack {
        LinearGradient(
          colors: dark
            ? [
              Color(red: 0.09, green: 0.12, blue: 0.23), Color(red: 0.045, green: 0.06, blue: 0.12),
            ]
            : [
              Color(red: 0.87, green: 0.9, blue: 0.98), Color(red: 0.97, green: 0.95, blue: 0.93),
            ],
          startPoint: .topLeading, endPoint: .bottomTrailing)
        RadialGradient(
          colors: [tint.opacity(dark ? 0.24 : 0.2), .clear],
          center: .init(x: 0.95, y: 0.3), startRadius: 0,
          endRadius: geometry.size.width * 0.95)
        RadialGradient(
          colors: [Color.purple.opacity(dark ? 0.15 : 0.12), .clear],
          center: .init(x: 0.05, y: 0.05), startRadius: 0,
          endRadius: geometry.size.width * 1.1)
        if dark && isEvening {
          Canvas { context, size in
            for index in 0..<48 {
              let x = Double((index * 137 + 43) % 997) / 997 * size.width
              let y = Double((index * 73 + 19) % 499) / 499 * size.height * 0.65
              let diameter = index % 4 == 0 ? 2.0 : 1.0
              context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter)),
                with: .color(.white.opacity(index % 3 == 0 ? 0.3 : 0.12)))
            }
          }
        }
      }
    }
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }
}

private struct DashboardGlass: ViewModifier {
  var cornerRadius: CGFloat
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    let dark = colorScheme == .dark
    content
      .background {
        if reduceTransparency {
          shape.fill(Color(uiColor: .secondarySystemGroupedBackground))
        } else {
          shape.fill(contrast == .increased ? .regularMaterial : .ultraThinMaterial)
            .overlay(shape.fill(.white.opacity(dark ? 0.025 : 0.12)))
        }
      }
      .overlay {
        shape.strokeBorder(
          LinearGradient(
            colors: [.white.opacity(dark ? 0.2 : 0.75), .white.opacity(dark ? 0.04 : 0.2)],
            startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1
        )
        .allowsHitTesting(false)
      }
      .shadow(color: .black.opacity(dark ? 0.16 : 0.045), radius: 18, x: 0, y: 8)
  }
}

private extension View {
  func dashboardGlass(cornerRadius: CGFloat = 24) -> some View {
    modifier(DashboardGlass(cornerRadius: cornerRadius))
  }
}

private extension SharedPeriod {
  var dashboardSymbol: String {
    switch self {
    case .day: "sun.max.fill"
    case .week: "calendar"
    case .month: "moonphase.waning.crescent"
    case .quarter: "square.grid.2x2"
    case .year: "sparkles"
    case .life: "heart.fill"
    }
  }
}

private struct DashboardGlassControl: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  func body(content: Content) -> some View {
    if reduceTransparency {
      content.background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
    } else if #available(iOS 26.0, *) {
      content.glassEffect(.regular.interactive(), in: Capsule())
    } else {
      content.background(.thinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
    }
  }
}
