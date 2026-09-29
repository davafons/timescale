import EventKit
import SwiftUI

@MainActor
final class MacCalendarSettingsModel: ObservableObject {
  @Published var calendars: [EKCalendar] = []
  @Published var message: String?
  private let store = EKEventStore()

  var authorized: Bool {
    EKEventStore.authorizationStatus(for: .event) == .fullAccess
  }

  func refresh() {
    guard authorized else {
      calendars = []
      if EKEventStore.authorizationStatus(for: .event) == .denied {
        message = "Calendar access was denied. Enable full access in System Settings."
      }
      return
    }
    message = nil
    calendars = store.calendars(for: .event).sorted {
      $0.title.localizedStandardCompare($1.title) == .orderedAscending
    }
  }

  func request() {
    Task {
      do {
        if try await store.requestFullAccessToEvents() {
          refresh()
          NotificationCenter.default.post(name: .timescaleCalendarSelectionChanged, object: nil)
        } else {
          message = "Calendar access was denied. Enable full access in System Settings."
        }
      } catch {
        message = error.localizedDescription
      }
    }
  }
}

@MainActor
struct MacCalendarSettings: View {
  @StateObject private var model = MacCalendarSettingsModel()
  @AppStorage(SettingsKey.enableHEYCLI) private var enableHEYCLI = true
  @AppStorage(SettingsKey.appleCalendarIDsJSON) private var selectedIDsJSON = ""

  var body: some View {
    Group {
      Toggle("Include HEY CLI events", isOn: $enableHEYCLI)
        .onChange(of: enableHEYCLI) { _, _ in notify() }
      if model.authorized {
        ForEach(model.calendars, id: \.calendarIdentifier) { calendar in
          Toggle(
            calendar.title,
            isOn: Binding(
              get: { selectedIDs?.contains(calendar.calendarIdentifier) ?? true },
              set: { enabled in
                var ids = selectedIDs ?? model.calendars.map(\.calendarIdentifier)
                if enabled {
                  if !ids.contains(calendar.calendarIdentifier) {
                    ids.append(calendar.calendarIdentifier)
                  }
                } else {
                  ids.removeAll { $0 == calendar.calendarIdentifier }
                }
                selectedIDsJSON =
                  String(
                    data: (try? JSONEncoder().encode(ids)) ?? Data("[]".utf8),
                    encoding: .utf8) ?? "[]"
                notify()
              }))
        }
        if missingCalendarCount > 0 {
          Text(
            "\(missingCalendarCount) selected calendar\(missingCalendarCount == 1 ? " is" : "s are") unavailable. Check its subscription in Apple Calendar."
          )
          .font(TypographyScale.detail)
          .foregroundStyle(.secondary)
        }
      } else {
        Button("Connect Apple Calendar") { model.request() }
      }
      Text(
        "Subscribed HEY calendars appear after you add their read-only feed in Apple Calendar. Subscription refresh may lag."
      )
      .font(TypographyScale.detail)
      .foregroundStyle(.secondary)
      if let message = model.message {
        Text(message).font(TypographyScale.detail).foregroundStyle(.secondary)
      }
    }
    .onAppear { model.refresh() }
  }

  private var selectedIDs: [String]? {
    guard !selectedIDsJSON.isEmpty,
      let data = selectedIDsJSON.data(using: .utf8)
    else { return nil }
    return try? JSONDecoder().decode([String].self, from: data)
  }

  private var missingCalendarCount: Int {
    guard let selectedIDs else { return 0 }
    return Set(selectedIDs).subtracting(model.calendars.map(\.calendarIdentifier)).count
  }

  private func notify() {
    NotificationCenter.default.post(name: .timescaleCalendarSelectionChanged, object: nil)
  }
}
