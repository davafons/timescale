import Foundation
import Testing
@testable import TimescaleCore

@Suite("Calendar events")
struct CalendarEventTests {
  @Test("Progress is clamped to the event range")
  func progressIsClamped() {
    let start = Date(timeIntervalSince1970: 100)
    let event = CalendarEvent(
      id: 1, title: "Meeting", start: start, end: start.addingTimeInterval(100))

    #expect(event.progress(at: start.addingTimeInterval(-1)) == 0)
    #expect(event.progress(at: start.addingTimeInterval(50)) == 0.5)
    #expect(event.progress(at: start.addingTimeInterval(101)) == 1)
  }

  @Test("All-day events are never ongoing")
  func allDayEventsAreNotOngoing() {
    let start = Date(timeIntervalSince1970: 100)
    let event = CalendarEvent(
      id: 1, title: "Holiday", start: start, end: start.addingTimeInterval(86_400), allDay: true)

    #expect(!event.isOngoing(at: start.addingTimeInterval(1)))
  }

  @Test("Event details retain their HEY edit link")
  func eventRetainsEditLink() throws {
    let editURL = try #require(URL(string: "https://app.hey.com/calendar/events/123/edit"))
    let event = CalendarEvent(
      id: 123,
      title: "Meeting",
      description: "Bring the notes",
      editURL: editURL,
      start: Date(timeIntervalSince1970: 100),
      end: Date(timeIntervalSince1970: 200))

    #expect(event.description == "Bring the notes")
    #expect(event.editURL == editURL)
  }
}
