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
      if granted {
        refresh(selectedIDs: IOSStore.loadSettings().selectedCalendarIDs)
      } else {
        errorMessage = "Calendar access was denied. Enable full access in Settings to show events."
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func refresh(selectedIDs: [String]?) {
    guard accessGranted else { return }
    calendars = store.calendars(for: .event).sorted {
      $0.title.localizedStandardCompare($1.title) == .orderedAscending
    }
    let selected = calendars.filter {
      selectedIDs == nil || selectedIDs!.contains($0.calendarIdentifier)
    }
    let now = Date.now
    if selected.isEmpty {
      events = []
      updatedAt = now
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
        .map {
          TimedEvent(
            id: $0.eventIdentifier,
            source: $0.calendar.title,
            externalUID: $0.calendarItemExternalIdentifier,
            title: $0.title ?? "Untitled event",
            detail: $0.notes,
            start: $0.startDate,
            end: $0.endDate)
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
