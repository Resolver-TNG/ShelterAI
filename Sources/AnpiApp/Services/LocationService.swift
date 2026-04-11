import Foundation
import CoreLocation

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var latitude: Double?
    @Published var longitude: Double?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestPermission() { manager.requestWhenInUseAuthorization() }
    func start() { manager.startUpdatingLocation() }
    func stop() { manager.stopUpdatingLocation() }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        latitude = loc.coordinate.latitude
        longitude = loc.coordinate.longitude
    }
}
