import EventKit
import EventKitUI
import SwiftUI
import TimescaleCore
import WidgetKit

@MainActor
@Observable final class CalendarSource {
  let store = EKEventStore()
  var calendars: [EKCalendar] = []
  var events: [TimedEvent] = IOSStore.loadEvents().events
  var updatedAt: Date? = IOSStore.loadEvents().updated
  var errorMessage: String?
  var missingSelectedCount = 0

  var missingSelectedMessage: String? {
    guard missingSelectedCount > 0 else { return nil }
    return "\(missingSelectedCount) selected calendar\(missingSelectedCount == 1 ? " is" : "s are") unavailable. Check \(missingSelectedCount == 1 ? "its" : "their") subscription in Apple Calendar."
  }

  var accessGranted: Bool {
    EKEventStore.authorizationStatus(for: .event) == .fullAccess
  }

  init() {
    NotificationCenter.default.addObserver(
      forName: .EKEventStoreChanged, object: store, queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.refresh(selectedIDs: IOSStore.loadSettings().selectedCalendarIDs)
      }
    }
  }

  func requestAccess() async {
    do {
      let granted = try await store.requestFullAccessToEvents()
      refresh(selectedIDs: IOSStore.loadSettings().selectedCalendarIDs)
      if !granted {
        errorMessage = "Calendar access was denied. Enable full access in Settings to show events."
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func refresh(selectedIDs: [String]?) {
    guard accessGranted else {
      let status = EKEventStore.authorizationStatus(for: .event)
      IOSStore.setCalendarAccessDenied(status == .denied || status == .restricted)
      missingSelectedCount = 0
      IOSStore.setMissingCalendarCount(0)
      calendars = []
      events = []
      updatedAt = nil
      IOSStore.clearEvents()
      WidgetCenter.shared.reloadAllTimelines()
      if EKEventStore.authorizationStatus(for: .event) == .denied {
        errorMessage = "Calendar access was denied. Enable full access in Settings to show events."
      }
      return
    }
    IOSStore.setCalendarAccessDenied(false)
    calendars = store.calendars(for: .event).sorted {
      $0.title.localizedStandardCompare($1.title) == .orderedAscending
    }
    missingSelectedCount = selectedIDs.map {
      Set($0).subtracting(calendars.map(\.calendarIdentifier)).count
    } ?? 0
    IOSStore.setMissingCalendarCount(missingSelectedCount)
    let selected = calendars.filter {
      selectedIDs == nil || selectedIDs!.contains($0.calendarIdentifier)
    }
    let now = Date.now
    if selected.isEmpty {
      events = []
      updatedAt = now
      errorMessage = nil
      IOSStore.saveEvents([], at: now)
      WidgetCenter.shared.reloadAllTimelines()
      return
    }
    let start = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
    let end = Calendar.current.date(byAdding: .day, value: 8, to: now) ?? now
    let predicate = store.predicateForEvents(withStart: start, end: end, calendars: selected)
    events = TimedEvents.deduplicated(
      store.events(matching: predicate)
        .filter { !$0.isAllDay }
        .compactMap { event -> TimedEvent? in
          guard let identifier = event.eventIdentifier else { return nil }
          return TimedEvent(
            id: identifier,
            source: event.calendar.title,
            sourceIdentifier: "eventkit:\(event.calendar.calendarIdentifier)",
            externalUID: event.calendarItemExternalIdentifier,
            title: event.title ?? "Untitled event",
            detail: event.notes,
            start: event.startDate,
            end: event.endDate)
        })
    updatedAt = now
    errorMessage = nil
    IOSStore.saveEvents(events, at: now)
    WidgetCenter.shared.reloadAllTimelines()
  }

  func event(for id: String) -> EKEvent? {
    store.event(withIdentifier: id)
  }
}

struct EventDetailScreen: UIViewControllerRepresentable {
  let event: EKEvent

  func makeUIViewController(context: Context) -> EKEventViewController {
    let controller = EKEventViewController()
    controller.event = event
    controller.allowsEditing = false
    return controller
  }

  func updateUIViewController(_ controller: EKEventViewController, context: Context) {}
}
