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

  @Test("Counters accumulate only while running")
  func counterElapsedTime() throws {
    let start = Date(timeIntervalSince1970: 1_000)
    let formatter = ISO8601DateFormatter()
    let counter = SharedCounter(
      name: "Work",
      targetMinutes: 420,
      elapsedSeconds: 3_600,
      startedAt: formatter.string(from: start))

    #expect(counter.elapsed(at: start.addingTimeInterval(1_800)) == 5_400)
    var paused = counter
    paused.startedAt = nil
    #expect(paused.elapsed(at: start.addingTimeInterval(1_800)) == 3_600)
  }

  @Test("Older shared files default new counter fields")
  func backwardCompatibleDecode() throws {
    let data = #"{"version":1,"timeZone":"local","day":{"start":"08:00","end":"23:00"},"routine":{"name":"Work","durationMinutes":480,"startedAt":null},"week":{"startsOn":"monday"},"quarter":{"cycle":"calendar"},"solar":{"enabled":true,"latitude":null,"longitude":null},"life":{"birthDate":null,"country":"Japan","expectancyYears":84},"visible":["day"],"macOS":{"accent":"system","precision":1,"showRemaining":false},"tui":{"theme":"auto","motion":"full"}}"#.data(using: .utf8)!
    let configuration = try JSONDecoder().decode(SharedConfiguration.self, from: data)
    #expect(configuration.counters.isEmpty)
    #expect(configuration.macOS.statusItemSource == "day")
  }
}
