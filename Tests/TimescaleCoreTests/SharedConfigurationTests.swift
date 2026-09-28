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
    #expect(object["routine"] == nil)
    #expect(object["counters"] == nil)
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
    #expect(configuration == SharedConfiguration())
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

    var collapsed = SharedConfiguration()
    collapsed.awareness.collapsedSources = ["day", "day"]
    #expect(throws: SharedConfigurationError.self) {
      try collapsed.validate()
    }
  }

  @Test("Legacy timer fields are ignored and their menu source resets")
  func backwardCompatibleDecode() throws {
    let data =
      #"{"version":1,"timeZone":"local","day":{"start":"08:00","end":"23:00"},"routine":{"name":"Work","durationMinutes":480,"startedAt":null},"counters":[{"id":"old","name":"Work","targetMinutes":480,"elapsedSeconds":0,"startedAt":null}],"week":{"startsOn":"monday"},"quarter":{"cycle":"calendar"},"solar":{"enabled":true,"latitude":null,"longitude":null},"life":{"birthDate":null,"country":"Japan","expectancyYears":84},"visible":["day"],"macOS":{"accent":"system","precision":1,"showRemaining":false,"statusItemSource":"counter:old"},"tui":{"theme":"auto","motion":"full"},"awareness":{"thresholdMinutes":90,"collapsedSources":["day","counter:old"],"checks":[]}}"#
      .data(using: .utf8)!
    let configuration = try JSONDecoder().decode(SharedConfiguration.self, from: data)
    #expect(configuration.macOS.statusItemSource == "day")
    #expect(configuration.awareness.collapsedSources == ["day"])
    let encoded = try JSONEncoder().encode(configuration)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(object["routine"] == nil)
    #expect(object["counters"] == nil)
    let awareness = try #require(object["awareness"] as? [String: Any])
    #expect(awareness["collapsedSources"] as? [String] == ["day"])
  }
}
