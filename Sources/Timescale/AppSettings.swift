import SwiftUI

enum AccentChoice: String, CaseIterable, Identifiable {
  case system, orange, blue, green, purple, monochrome

  var id: String { rawValue }
  var title: String { rawValue.capitalized }

  var color: Color {
    switch self {
    case .system: .accentColor
    case .orange: .orange
    case .blue: .blue
    case .green: .green
    case .purple: .purple
    case .monochrome: .primary
    }
  }
}

enum QuarterCycle: String, CaseIterable, Identifiable {
  case calendar
  case japanFiscal

  var id: String { rawValue }
  var startMonth: Int { self == .calendar ? 1 : 4 }

  var title: String {
    switch self {
    case .calendar: "Calendar year (Jan–Dec)"
    case .japanFiscal: "Japan fiscal year (Apr–Mar)"
    }
  }
}

enum Country: String, CaseIterable, Identifiable {
  case australia = "Australia"
  case canada = "Canada"
  case france = "France"
  case germany = "Germany"
  case italy = "Italy"
  case japan = "Japan"
  case spain = "Spain"
  case switzerland = "Switzerland"
  case unitedKingdom = "United Kingdom"
  case unitedStates = "United States"

  var id: String { rawValue }

  var lifeExpectancy: Double {
    switch self {
    case .japan, .spain, .switzerland: 84
    case .australia, .france: 83
    case .italy: 84
    case .canada: 82
    case .germany, .unitedKingdom: 81
    case .unitedStates: 79
    }
  }
}

enum SettingsKey {
  static let birthTimestamp = "birthTimestamp"
  static let birthDateConfigured = "birthDateConfigured"
  static let birthYear = "birthYear"
  static let birthMonth = "birthMonth"
  static let birthDay = "birthDay"
  static let country = "country"
  static let lifeExpectancy = "lifeExpectancy"
  static let showDay = "showDay"
  static let showWeek = "showWeek"
  static let showMonth = "showMonth"
  static let showQuarter = "showQuarter"
  static let quarterCycle = "quarterCycle"
  static let showYear = "showYear"
  static let showLife = "showLife"
  static let showRemaining = "showRemaining"
  static let precision = "precision"
  static let accent = "accent"
  static let dayStartMinutes = "dayStartMinutes"
  static let dayEndMinutes = "dayEndMinutes"
  static let showSolarEvents = "showSolarEvents"
  static let locationConfigured = "locationConfigured"
  static let latitude = "latitude"
  static let longitude = "longitude"
}
