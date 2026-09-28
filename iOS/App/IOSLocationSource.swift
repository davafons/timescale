import CoreLocation
import Foundation

@MainActor
final class IOSLocationSource: NSObject, CLLocationManagerDelegate {
  private let manager = CLLocationManager()
  var onCoordinate: ((CLLocationCoordinate2D) -> Void)?
  var onMessage: ((String?) -> Void)?

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyKilometer
  }

  func refresh() {
    switch manager.authorizationStatus {
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
    case .authorizedAlways, .authorizedWhenInUse:
      manager.requestLocation()
    case .denied, .restricted:
      onMessage?("Location is unavailable. Enable access in Settings or use manual coordinates.")
    @unknown default:
      onMessage?("Location is unavailable. Use manual coordinates.")
    }
  }

  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    Task { @MainActor in
      if manager.authorizationStatus == .authorizedWhenInUse
        || manager.authorizationStatus == .authorizedAlways
      {
        manager.requestLocation()
      } else if manager.authorizationStatus == .denied {
        onMessage?("Location is unavailable. Enable access in Settings or use manual coordinates.")
      }
    }
  }

  nonisolated func locationManager(
    _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
  ) {
    guard let coordinate = locations.last?.coordinate else { return }
    Task { @MainActor in
      onCoordinate?(coordinate)
      onMessage?(nil)
    }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    Task { @MainActor in onMessage?(error.localizedDescription) }
  }
}
