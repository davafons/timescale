import Foundation
import Testing

@testable import TimescaleCore

@Suite("Shared configuration")
struct SharedConfigurationTests {
  @Test("Default configuration round-trips through JSON")
  func roundTrip() throws {
    let configuration = SharedConfiguration()
    let data = try JSONEncoder().encode(configuration)
    let decoded = try JSONDecoder().decode(SharedConfiguration.self, from: data)
    try decoded.validate()
    #expect(decoded == configuration)
  }

  @Test("Configuration uses the cross-platform field names")
  func fieldNames() throws {
    let data = try JSONEncoder().encode(SharedConfiguration())
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["macOS"] != nil)
    let tui = try #require(object["tui"] as? [String: Any])
    #expect(tui["motion"] as? String == "full")
  }

  @Test("Repository example matches the Swift model")
  func sharedExample() throws {
    let projectRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let data = try Data(contentsOf: projectRoot.appendingPathComponent("config/example.json"))
    let configuration = try JSONDecoder().decode(SharedConfiguration.self, from: data)
    try configuration.validate()
    #expect(configuration.tui.motion == .full)
  }

  @Test("Wall-clock settings require HH:MM")
  func times() throws {
    #expect(try SharedConfiguration.minutes("08:30") == 510)
    #expect(throws: SharedConfigurationError.self) {
      try SharedConfiguration.minutes("8:30")
    }
  }

  @Test("Configuration rejects invalid dates and duplicate periods")
  func validation() throws {
    var invalidDate = SharedConfiguration()
    invalidDate.life.birthDate = "2026-02-30"
    #expect(throws: SharedConfigurationError.self) {
      try invalidDate.validate()
    }

    var duplicates = SharedConfiguration()
    duplicates.visible = [.day, .day]
    #expect(throws: SharedConfigurationError.self) {
      try duplicates.validate()
    }
  }

  @Test("Routine configuration validates its name, duration, and start")
  func routineValidation() throws {
    var configuration = SharedConfiguration()
    configuration.routine = SharedRoutineSettings(
      name: "Work", durationMinutes: 480, startedAt: "2026-09-06T08:00:00+09:00")
    try configuration.validate()

    configuration.routine.name = " "
    #expect(throws: SharedConfigurationError.self) {
      try configuration.validate()
    }
  }
}
