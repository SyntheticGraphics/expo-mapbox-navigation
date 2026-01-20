import Foundation
import MapboxNavigationCore
import MapboxNavigationUIKit
import MapboxDirections
import CoreLocation

/// Manages the state shared between the main app and CarPlay
public class CarPlayStateManager {
    
    public static let shared = CarPlayStateManager()
    
    private init() {
        setupNotificationObservers()
    }
    
    // MARK: - Current Trip State
    
    /// Current navigation routes being displayed
    public var currentRoutes: NavigationRoutes?
    
    /// Current trip status
    public var tripStatus: String = "IDLE"
    
    /// Current stop information
    public var currentStopInfo: [String: Any]?
    
    /// Passenger information for current stop
    public var passengerInfo: [[String: Any]] = []
    
    /// Callback for CarPlay actions
    public var onActionCallback: ((String, [String: Any]?) -> Void)?
    
    // MARK: - State Updates
    
    /// Update the CarPlay state with trip information
    /// - Parameters:
    ///   - status: Current trip status (IDLE, EN_ROUTE, AT_STOP, COMPLETED)
    ///   - stopInfo: Information about the current stop
    ///   - passengers: List of passengers for the current stop
    public func updateState(
        status: String,
        stopInfo: [String: Any]?,
        passengers: [[String: Any]]
    ) {
        self.tripStatus = status
        self.currentStopInfo = stopInfo
        self.passengerInfo = passengers
        
        // Post notification for CarPlay UI updates
        NotificationCenter.default.post(
            name: Notification.Name("CarPlayStateDidUpdate"),
            object: nil,
            userInfo: [
                "status": status,
                "stopInfo": stopInfo as Any,
                "passengers": passengers
            ]
        )
        
        // Handle special states
        if status == "COMPLETED" {
            handleNavigationCompleted()
        }
    }
    
    /// Start navigation to the given coordinates on CarPlay
    /// - Parameters:
    ///   - coordinates: Array of coordinates for the route
    ///   - waypointIndices: Indices of waypoints that should be treated as stops
    public func startCarPlayNavigation(
        coordinates: [CLLocationCoordinate2D],
        waypointIndices: [Int]?
    ) {
        guard let carPlayManager = CarPlaySceneDelegate.carPlayManager,
              !coordinates.isEmpty else {
            return
        }
        
        // Create waypoints from coordinates
        let waypoints = coordinates.enumerated().map { (index, coordinate) -> Waypoint in
            var waypoint = Waypoint(coordinate: coordinate)
            if let indices = waypointIndices {
                waypoint.separatesLegs = indices.contains(index)
            } else {
                waypoint.separatesLegs = true
            }
            return waypoint
        }
        
        // Request routes and start navigation
        Task { @MainActor in
            let routeOptions = NavigationRouteOptions(waypoints: waypoints)
            
            let routingProvider = CarPlaySceneDelegate.navigationProvider.mapboxNavigation.routingProvider()
            
            switch await routingProvider.calculateRoutes(options: routeOptions).result {
            case .success(let navigationRoutes):
                self.currentRoutes = navigationRoutes
                
                // Preview routes on CarPlay
                await carPlayManager.previewRoutes(for: navigationRoutes)
                
            case .failure(let error):
                print("CarPlay: Failed to calculate routes: \(error.localizedDescription)")
            }
        }
    }
    
    /// Check if there's active navigation in the main app and mirror it to CarPlay
    public func checkForActiveNavigation() {
        // Post notification to check for active navigation
        NotificationCenter.default.post(
            name: Notification.Name("CarPlayCheckActiveNavigation"),
            object: nil
        )
    }
    
    /// Send an action from CarPlay to the main app
    public func sendAction(_ action: String, data: [String: Any]? = nil) {
        onActionCallback?(action, data)
    }
    
    // MARK: - Private Methods
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNavigationRoutesUpdated(_:)),
            name: Notification.Name("NavigationRoutesUpdated"),
            object: nil
        )
    }
    
    @objc private func handleNavigationRoutesUpdated(_ notification: Notification) {
        guard let routes = notification.userInfo?["routes"] as? NavigationRoutes else {
            return
        }
        
        currentRoutes = routes
        
        // If CarPlay is connected, update the routes there too
        if CarPlayManager.isConnected {
            Task { @MainActor in
                await CarPlaySceneDelegate.carPlayManager?.previewRoutes(for: routes)
            }
        }
    }
    
    private func handleNavigationCompleted() {
        currentRoutes = nil
        currentStopInfo = nil
        passengerInfo = []
        tripStatus = "IDLE"
    }
}
