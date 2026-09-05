import CoreLocation
import Foundation

@MainActor
final class LocationProvider: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate
{
  @Published private(set) var message: String?

  private let manager = CLLocationManager()
  private var completion: ((CLLocationCoordinate2D) -> Void)?
  @Published private(set) var isRequesting = false

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
  }

  func requestLocation(completion: @escaping (CLLocationCoordinate2D) -> Void) {
    self.completion = completion
    message = "Requesting location…"
    isRequesting = true

    switch manager.authorizationStatus {
    case .authorized, .authorizedAlways:
      manager.requestLocation()
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
    case .denied, .restricted:
      message = "Location access is disabled in System Settings."
      self.completion = nil
      isRequesting = false
    @unknown default:
      message = "Location is unavailable."
      self.completion = nil
      isRequesting = false
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if manager.authorizationStatus == .authorized
      || manager.authorizationStatus == .authorizedAlways
    {
      manager.requestLocation()
    } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
      message = "Location access is disabled in System Settings."
      completion = nil
      isRequesting = false
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let coordinate = locations.last?.coordinate else { return }
    completion?(coordinate)
    completion = nil
    isRequesting = false
    message = "Location updated."
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    message = "Couldn’t determine the current location."
    completion = nil
    isRequesting = false
  }
}
