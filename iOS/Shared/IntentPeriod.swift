import AppIntents
import TimescaleCore

enum IntentPeriod: String, AppEnum {
  case day, week, month, quarter, year, life

  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Period"
  static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .day: "Day", .week: "Week", .month: "Month",
    .quarter: "Quarter", .year: "Year", .life: "Life",
  ]

  var shared: SharedPeriod { SharedPeriod(rawValue: rawValue)! }
}
