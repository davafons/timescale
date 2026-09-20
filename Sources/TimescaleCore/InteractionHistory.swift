import Foundation

public enum InteractionHistory {
  public static let maximumCount = 500

  public struct Check: Codable, Equatable, Sendable {
    public let timestamp: TimeInterval
    public let source: String
    public let appName: String?
    public let bundleIdentifier: String?

    public init(
      timestamp: TimeInterval,
      source: String,
      appName: String? = nil,
      bundleIdentifier: String? = nil
    ) {
      self.timestamp = timestamp
      self.source = source
      self.appName = appName
      self.bundleIdentifier = bundleIdentifier
    }

    private enum CodingKeys: String, CodingKey {
      case timestamp, source, appName, bundleIdentifier
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
      source = try container.decode(String.self, forKey: .source)
      appName = try container.decodeIfPresent(String.self, forKey: .appName)
      bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
    }
  }

  public static func checks(from value: String) -> [Check] {
    guard let data = value.data(using: .utf8) else { return [] }
    if let checks = try? JSONDecoder().decode([Check].self, from: data) {
      return checks.sorted { $0.timestamp < $1.timestamp }
    }
    guard let timestamps = try? JSONDecoder().decode([TimeInterval].self, from: data) else {
      return []
    }
    return timestamps.sorted().map { Check(timestamp: $0, source: "day") }
  }

  public static func merging(
    _ existing: [Check], with additions: [Check], maximumCount: Int = maximumCount
  ) -> [Check] {
    var merged = existing
    for check in additions where !merged.contains(check) {
      merged.append(check)
    }
    merged.sort { $0.timestamp < $1.timestamp }
    return Array(merged.suffix(max(maximumCount, 1)))
  }

  public static func reconciling(
    previous: [Check], local: [Check], incoming: [Check], maximumCount: Int = maximumCount
  ) -> [Check] {
    let locallyAdded = local.filter { !previous.contains($0) }
    let externallyAdded = incoming.filter { !previous.contains($0) }
    if !externallyAdded.isEmpty {
      return merging(
        incoming, with: previous + locallyAdded, maximumCount: maximumCount)
    }
    if !locallyAdded.isEmpty {
      return merging(incoming, with: locallyAdded, maximumCount: maximumCount)
    }
    return incoming
  }

  public static func timestamps(from value: String) -> [TimeInterval] {
    checks(from: value).map(\.timestamp)
  }

  public static func appending(
    timestamp: TimeInterval,
    source: String,
    appName: String? = nil,
    bundleIdentifier: String? = nil,
    to value: String,
    maximumCount: Int = maximumCount
  ) -> String? {
    var checks = checks(from: value)
    checks.append(
      Check(
        timestamp: timestamp,
        source: source,
        appName: appName,
        bundleIdentifier: bundleIdentifier))
    checks = Array(checks.suffix(max(maximumCount, 1)))
    guard let data = try? JSONEncoder().encode(checks) else { return nil }
    return String(data: data, encoding: .utf8)
  }
}
