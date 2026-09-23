import AppKit
import ServiceManagement

@MainActor
final class LaunchAtLoginController: ObservableObject {
  @Published private(set) var isRegistered = false
  @Published private(set) var requiresApproval = false
  @Published private(set) var errorMessage: String?

  init() {
    refresh()
  }

  func refresh() {
    let status = SMAppService.mainApp.status
    isRegistered = status == .enabled || status == .requiresApproval
    requiresApproval = status == .requiresApproval
  }

  func setRegistered(_ shouldRegister: Bool) {
    errorMessage = nil

    do {
      if shouldRegister {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
          break
        case .notRegistered, .notFound:
          try SMAppService.mainApp.register()
        @unknown default:
          try SMAppService.mainApp.register()
        }
      } else {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
          try SMAppService.mainApp.unregister()
        case .notRegistered, .notFound:
          break
        @unknown default:
          try SMAppService.mainApp.unregister()
        }
      }
    } catch {
      errorMessage = error.localizedDescription
    }

    refresh()
  }

  func openSystemSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }
}
