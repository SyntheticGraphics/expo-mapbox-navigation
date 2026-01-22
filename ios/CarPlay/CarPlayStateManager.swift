import Foundation
import MapboxNavigationCore
import MapboxNavigationUIKit
import MapboxDirections
import CoreLocation
import CarPlay

public class CarPlayStateManager {
    
    public static let shared = CarPlayStateManager()
    
    private init() {
        setupNotificationObservers()
    }
    
    public var carPlayManager: CarPlayManager?
    
    public var interfaceController: CPInterfaceController?
    
    public var carPlayWindow: CPWindow?
    
    public var isConnected: Bool {
        return interfaceController != nil
    }
    
    public var currentRoutes: NavigationRoutes?
    
    public var tripStatus: String = "IDLE"
    
    public var currentStopInfo: [String: Any]?
    
    public var passengerInfo: [[String: Any]] = []
    
    public var onActionCallback: ((String, [String: Any]?) -> Void)?
    
    public func updateState(
        status: String,
        stopInfo: [String: Any]?,
        passengers: [[String: Any]]
    ) {
        self.tripStatus = status
        self.currentStopInfo = stopInfo
        self.passengerInfo = passengers
        
        NotificationCenter.default.post(
            name: Notification.Name("CarPlayStateDidUpdate"),
            object: nil,
            userInfo: [
                "status": status,
                "stopInfo": stopInfo as Any,
                "passengers": passengers
            ]
        )
        
        if status == "COMPLETED" {
            handleNavigationCompleted()
        }
    }
    
    public func previewRoutesOnCarPlay(_ routes: NavigationRoutes) {
        guard isConnected, let carPlayManager = self.carPlayManager else {
            print("CarPlay: Not connected, cannot preview routes")
            return
        }
        
        self.currentRoutes = routes
        
        Task { @MainActor in
            await carPlayManager.previewRoutes(for: routes)
        }
    }
    
    public func checkForActiveNavigation() {
        NotificationCenter.default.post(
            name: Notification.Name("CarPlayCheckActiveNavigation"),
            object: nil
        )
    }

    public func sendAction(_ action: String, data: [String: Any]? = nil) {
        onActionCallback?(action, data)
    }
     
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
        
        if isConnected, let carPlayManager = self.carPlayManager {
            Task { @MainActor in
                await carPlayManager.previewRoutes(for: routes)
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