import SwiftUI

struct SettingsView: View {
  @StateObject private var locationProvider = LocationProvider()
  @AppStorage(SettingsKey.birthTimestamp) private var birthTimestamp = 0.0
  @AppStorage(SettingsKey.birthDateConfigured) private var birthDateConfigured = false
  @AppStorage(SettingsKey.birthYear) private var birthYear = 0
  @AppStorage(SettingsKey.birthMonth) private var birthMonth = 0
  @AppStorage(SettingsKey.birthDay) private var birthDay = 0
  @AppStorage(SettingsKey.country) private var countryRawValue = Country.japan.rawValue
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

  private var birthDate: Binding<Date> {
    Binding(
      get: {
        guard birthDateConfigured, birthYear > 0, birthMonth > 0, birthDay > 0 else {
          return Date(timeIntervalSince1970: birthTimestamp)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar.date(
          from: DateComponents(year: birthYear, month: birthMonth, day: birthDay, hour: 12))
          ?? Date(timeIntervalSince1970: birthTimestamp)
      },
      set: {
        birthTimestamp = $0.timeIntervalSince1970
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let components = calendar.dateComponents([.year, .month, .day], from: $0)
        birthYear = components.year ?? 0
        birthMonth = components.month ?? 0
        birthDay = components.day ?? 0
        birthDateConfigured = birthYear > 0 && birthMonth > 0 && birthDay > 0
      }
    )
  }

  private var lifeExpectancyBinding: Binding<Double> {
    Binding(
      get: { lifeExpectancy },
      set: { lifeExpectancy = min(max($0, 1), 150) }
    )
  }

  var body: some View {
    Form {
      Section("Visible progress") {
        Toggle("Day", isOn: $showDay)
        Toggle("Week", isOn: $showWeek)
        Toggle("Month", isOn: $showMonth)
        Toggle("Quarter", isOn: $showQuarter)
        if showQuarter {
          Picker("Quarter cycle", selection: $quarterCycleRawValue) {
            ForEach(QuarterCycle.allCases) { cycle in
              Text(cycle.title).tag(cycle.rawValue)
            }
          }
        }
        Toggle("Year", isOn: $showYear)
        Toggle("Life estimate", isOn: $showLife)
      }

      Section("Waking day") {
        DatePicker(
          "Starts", selection: timeBinding($dayStartMinutes), displayedComponents: .hourAndMinute)
        DatePicker(
          "Ends", selection: timeBinding($dayEndMinutes), displayedComponents: .hourAndMinute)
        Text(
          "Day progress is 0% at your start time and 100% at your end time. Overnight schedules are supported."
        )
        .font(TypographyScale.detail)
        .foregroundStyle(.secondary)
      }

      Section("Sun") {
        Toggle("Show sunrise and sunset", isOn: $showSolarEvents)
        Button(locationConfigured ? "Update Current Location" : "Use Current Location") {
          locationProvider.requestLocation { coordinate in
            latitude = coordinate.latitude
            longitude = coordinate.longitude
            locationConfigured = true
          }
        }
        .disabled(locationProvider.isRequesting)
        if let message = locationProvider.message {
          Text(message).font(TypographyScale.detail).foregroundStyle(.secondary)
        } else if locationConfigured {
          Text(
            "Location saved locally: \(latitude.formatted(.number.precision(.fractionLength(2))))°, \(longitude.formatted(.number.precision(.fractionLength(2))))°"
          )
          .font(TypographyScale.detail)
          .foregroundStyle(.secondary)
        }
      }

      Section("Life estimate") {
        DatePicker("Birth date", selection: birthDate, in: ...Date(), displayedComponents: .date)
        if !birthDateConfigured {
          Button("Use This Birth Date") {
            birthDate.wrappedValue = birthDate.wrappedValue
          }
        }

        Picker("Country", selection: $countryRawValue) {
          ForEach(Country.allCases) { country in
            Text(country.rawValue).tag(country.rawValue)
          }
        }
        .onChange(of: countryRawValue) { _, newValue in
          if let country = Country(rawValue: newValue) {
            lifeExpectancy = country.lifeExpectancy
          }
        }

        HStack {
          Text("Life expectancy")
          Spacer()
          TextField(
            "Years", value: lifeExpectancyBinding, format: .number.precision(.fractionLength(0...1))
          )
          .multilineTextAlignment(.trailing)
          .frame(width: 70)
          Text("years").foregroundStyle(.secondary)
        }

        Text(
          "Rounded 2024 World Bank life expectancy at birth. This is a population average, not a personal or medical prediction. You can edit it directly."
        )
        .font(TypographyScale.detail)
        .foregroundStyle(.secondary)
      }

      Section("Appearance") {
        Picker("Display", selection: $showRemaining) {
          Text("Elapsed").tag(false)
          Text("Remaining").tag(true)
        }
        .pickerStyle(.segmented)

        Picker("Decimal places", selection: $precision) {
          Text("0").tag(0)
          Text("1").tag(1)
          Text("2").tag(2)
        }

        Picker("Accent", selection: $accentRawValue) {
          ForEach(AccentChoice.allCases) { choice in
            Text(choice.title).tag(choice.rawValue)
          }
        }
      }

      Text("All settings stay on this Mac.")
        .font(TypographyScale.detail)
        .foregroundStyle(.secondary)
    }
    .formStyle(.grouped)
    .padding(.vertical, LayoutScale.small)
  }

  private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
    Binding(
      get: {
        Calendar.current.date(
          bySettingHour: minutes.wrappedValue / 60,
          minute: minutes.wrappedValue % 60,
          second: 0,
          of: Date()
        ) ?? Date()
      },
      set: {
        let components = Calendar.current.dateComponents([.hour, .minute], from: $0)
        minutes.wrappedValue = (components.hour ?? 0) * 60 + (components.minute ?? 0)
      }
    )
  }
}
