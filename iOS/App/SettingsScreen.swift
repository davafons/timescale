import SwiftUI
import TimescaleCore

struct SettingsScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Bindable var model: AppModel

  var body: some View {
    NavigationStack {
      Form {
        Section("Visible progress") {
          ForEach(SharedPeriod.allCases, id: \.self) { period in
            Toggle(period.title, isOn: Binding(
              get: { model.settings.visible.contains(period) },
              set: { enabled in
                if enabled {
                  if !model.settings.visible.contains(period) {
                    model.settings.visible.append(period)
                  }
                } else {
                  model.settings.visible.removeAll { $0 == period }
                }
              }))
          }
          Picker("Headline", selection: $model.settings.headline) {
            ForEach(SharedPeriod.allCases, id: \.self) { period in
              Text(period.title).tag(period)
            }
          }
        }
        Section("Waking day") {
          TimePickerRow(title: "Start", minutes: $model.settings.dayStartMinutes)
          TimePickerRow(title: "End", minutes: $model.settings.dayEndMinutes)
          Text("Overnight schedules are supported.")
            .font(.footnote).foregroundStyle(.secondary)
        }
        Section("Calendar cycles") {
          Picker("Week starts", selection: $model.settings.weekStartsOn) {
            Text("Monday").tag(SharedWeekStart.monday)
            Text("Sunday").tag(SharedWeekStart.sunday)
          }
          Picker("Quarter", selection: $model.settings.quarterCycle) {
            Text("Calendar year").tag(SharedQuarterCycle.calendar)
            Text("Japan fiscal year").tag(SharedQuarterCycle.japanFiscal)
          }
        }
        Section("Appearance") {
          Toggle("Show remaining", isOn: $model.settings.showRemaining)
          Picker("Decimal places", selection: $model.settings.precision) {
            ForEach(0...3, id: \.self) { value in Text("\(value)").tag(value) }
          }
          Picker("Accent", selection: $model.settings.accent) {
            ForEach(["orange", "blue", "green", "purple", "monochrome"], id: \.self) {
              Text($0.capitalized).tag($0)
            }
          }
        }
        Section("Life") {
          Toggle("Birth date set", isOn: Binding(
            get: { model.settings.birthDate != nil },
            set: { model.settings.birthDate = $0 ? .now : nil }))
          if model.settings.birthDate != nil {
            DatePicker("Birth date", selection: Binding(
              get: { model.settings.birthDate ?? .now },
              set: { model.settings.birthDate = $0 }),
              in: ...Date.now, displayedComponents: .date)
            TextField("Country", text: $model.settings.country)
            Stepper(
              "Population expectancy: \(model.settings.expectedYears.formatted()) years",
              value: $model.settings.expectedYears, in: 1...150, step: 0.5)
            Text("This is a population-average visualization, not a personal prediction.")
              .font(.footnote).foregroundStyle(.secondary)
          }
        }
        Section("Sun") {
          Picker("Location mode", selection: Binding(
            get: { model.settings.locationMode },
            set: { mode in
              if mode == "automatic" {
                model.useAutomaticLocation()
              } else {
                model.settings.locationMode = "manual"
              }
            })) {
              Text("Manual").tag("manual")
              Text("Automatic").tag("automatic")
            }
          Text("Manual coordinates work offline. Automatic location updates while travelling.")
            .font(.footnote).foregroundStyle(.secondary)
          if model.settings.locationMode == "manual" {
            OptionalCoordinateField(title: "Latitude", value: $model.settings.latitude)
            OptionalCoordinateField(title: "Longitude", value: $model.settings.longitude)
          } else if let message = model.locationMessage {
            Text(message).font(.footnote).foregroundStyle(.secondary)
          }
        }
        Section("Time awareness") {
          Stepper(
            "Long gap: \(model.settings.longGapMinutes) min",
            value: $model.settings.longGapMinutes, in: 5...480, step: 1)
          Toggle("Long-gap reminder", isOn: Binding(
            get: { model.settings.remindersEnabled },
            set: { enabled in
              Task {
                let granted = await ReminderManager.setEnabled(
                  enabled, settings: model.settings, checks: model.checks)
                model.settings.remindersEnabled = enabled && granted
              }
            }))
          Text("Reminders begin after your first check-in during waking hours.")
            .font(.footnote).foregroundStyle(.secondary)
        }
        Section("Calendars") {
          if model.calendar.accessGranted {
            ForEach(model.calendar.calendars, id: \.calendarIdentifier) { calendar in
              Toggle(calendar.title, isOn: Binding(
                get: {
                  model.settings.selectedCalendarIDs?
                    .contains(calendar.calendarIdentifier) ?? true
                },
                set: { enabled in
                  var ids = model.settings.selectedCalendarIDs
                    ?? model.calendar.calendars.map(\.calendarIdentifier)
                  if enabled {
                    if !ids.contains(calendar.calendarIdentifier) {
                      ids.append(calendar.calendarIdentifier)
                    }
                  } else {
                    ids.removeAll { $0 == calendar.calendarIdentifier }
                  }
                  model.settings.selectedCalendarIDs = ids
                  model.calendar.refresh(selectedIDs: ids)
                }))
            }
            if missingCalendarCount > 0 {
              Text("\(missingCalendarCount) selected calendar\(missingCalendarCount == 1 ? " is" : "s are") unavailable. Check its subscription in Apple Calendar.")
                .font(.footnote).foregroundStyle(.secondary)
            }
          } else {
            Button("Connect Apple Calendar") {
              Task { await model.calendar.requestAccess() }
            }
          }
          Text("Subscribe to a read-only HEY calendar in Apple Calendar, then enable it here. Subscription refresh may lag.")
            .font(.footnote).foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Settings")
      .toolbar { ToolbarItem(placement: .confirmationAction) {
        Button("Done") { dismiss() }
      }}
    }
  }

  private var missingCalendarCount: Int {
    guard let selected = model.settings.selectedCalendarIDs else { return 0 }
    return Set(selected).subtracting(model.calendar.calendars.map(\.calendarIdentifier)).count
  }
}

private struct TimePickerRow: View {
  let title: String
  @Binding var minutes: Int

  var body: some View {
    DatePicker(title, selection: Binding(
      get: {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar.date(from: DateComponents(
          year: 2001, month: 1, day: 15,
          hour: minutes / 60, minute: minutes % 60)) ?? .now
      },
      set: {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
        minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
      }), displayedComponents: .hourAndMinute)
  }
}

private struct OptionalCoordinateField: View {
  let title: String
  @Binding var value: Double?

  var body: some View {
    TextField(title, text: Binding(
      get: { value.map { String($0) } ?? "" },
      set: { value = Double($0) }))
      .keyboardType(.numbersAndPunctuation)
  }
}
