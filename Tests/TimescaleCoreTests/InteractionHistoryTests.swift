import Foundation
import Testing

@testable import TimescaleCore

@Suite("Interaction history")
struct InteractionHistoryTests {
  @Test("Structured checks round-trip")
  func structuredChecksRoundTrip() throws {
    let encoded = try #require(
      InteractionHistory.appending(timestamp: 123, source: "week", to: "[]"))

    #expect(
      InteractionHistory.checks(from: encoded)
        == [InteractionHistory.Check(timestamp: 123, source: "week")])
  }

  @Test("Older checks decode without application context")
  func olderChecksDecodeWithoutApplicationContext() throws {
    let checks = InteractionHistory.checks(from: #"[{"timestamp":123,"source":"day"}]"#)
    #expect(
      checks == [
        InteractionHistory.Check(
          timestamp: 123,
          source: "day",
          appName: nil,
          bundleIdentifier: nil)
      ])
  }

  @Test("Checks retain the foreground application context")
  func checksRetainForegroundApplicationContext() throws {
    let encoded = try #require(
      InteractionHistory.appending(
        timestamp: 123,
        source: "day",
        appName: "Safari",
        bundleIdentifier: "com.apple.Safari",
        to: "[]"))
    #expect(
      InteractionHistory.checks(from: encoded) == [
        InteractionHistory.Check(
          timestamp: 123,
          source: "day",
          appName: "Safari",
          bundleIdentifier: "com.apple.Safari")
      ])
  }

  @Test("Legacy timestamp arrays migrate to day checks")
  func legacyTimestampsMigrate() {
    #expect(
      InteractionHistory.checks(from: "[100,200]")
        == [
          InteractionHistory.Check(timestamp: 100, source: "day"),
          InteractionHistory.Check(timestamp: 200, source: "day"),
        ])
  }

  @Test("Appending retains only the newest checks")
  func historyIsBounded() throws {
    var encoded = "[]"
    for timestamp in 1...5 {
      encoded = try #require(
        InteractionHistory.appending(
          timestamp: Double(timestamp), source: "day", to: encoded, maximumCount: 3))
    }

    #expect(InteractionHistory.timestamps(from: encoded) == [3, 4, 5])
  }

  @Test("Malformed history recovers when a check is appended")
  func malformedHistoryRecovers() throws {
    let encoded = try #require(
      InteractionHistory.appending(timestamp: 123, source: "month", to: "not json"))

    #expect(
      InteractionHistory.checks(from: encoded)
        == [InteractionHistory.Check(timestamp: 123, source: "month")])
  }

  @Test("Checks are normalized chronologically")
  func checksAreChronological() {
    #expect(InteractionHistory.timestamps(from: "[300,100,200]") == [100, 200, 300])
  }

  @Test("Concurrent histories merge without duplicates and remain bounded")
  func concurrentHistoriesMerge() {
    let first = InteractionHistory.Check(timestamp: 100, source: "day")
    let second = InteractionHistory.Check(timestamp: 200, source: "week")
    let third = InteractionHistory.Check(timestamp: 300, source: "month")

    #expect(
      InteractionHistory.merging([second, first], with: [second, third], maximumCount: 2)
        == [second, third])
  }

  @Test("Concurrent append-only writers preserve both checks while an explicit clear wins")
  func concurrentHistoriesReconcile() {
    let original = InteractionHistory.Check(timestamp: 100, source: "day")
    let native = InteractionHistory.Check(timestamp: 200, source: "week")
    let terminal = InteractionHistory.Check(timestamp: 300, source: "month")

    #expect(
      InteractionHistory.reconciling(
        previous: [original, native],
        local: [original, native],
        incoming: [original, terminal])
        == [original, native, terminal])
    #expect(
      InteractionHistory.reconciling(
        previous: [original], local: [original, native], incoming: [original])
        == [original, native])
    #expect(
      InteractionHistory.reconciling(
        previous: [original], local: [original], incoming: [])
        == [])
  }
}
