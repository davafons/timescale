import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
  static let shared = SettingsWindowController()

  private init() {
    let hostingController = NSHostingController(
      rootView: SettingsView().frame(width: 460, height: 580))
    let window = NSWindow(contentViewController: hostingController)
    window.title = "Timescale Settings"
    window.styleMask = [.titled, .closable]
    window.isReleasedWhenClosed = false
    window.center()
    super.init(window: window)
    window.delegate = self
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func show() {
    guard let window else { return }
    window.center()
    showWindow(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }
}
