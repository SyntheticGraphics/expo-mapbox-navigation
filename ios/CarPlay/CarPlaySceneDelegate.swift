import CarPlay
import MapboxNavigationCore
import MapboxNavigationUIKit
import MapboxDirections
import CoreLocation
import MapboxMaps

/// The CarPlay scene delegate that handles CarPlay connections and disconnections.
/// This class integrates with the Mapbox Navigation SDK's CarPlayManager.
public class CarPlaySceneDelegate: NSObject, CPTemplateApplicationSceneDelegate {
    
    /// Singleton CarPlayManager instance shared across the app
    public static var carPlayManager: CarPlayManager?
    
    /// The navigation provider for CarPlay - shared with main app
    private static var _navigationProvider: MapboxNavigationProvider?
    
    public static var navigationProvider: MapboxNavigationProvider {
        if _navigationProvider == nil {
            _navigationProvider = MapboxNavigationProvider(
                coreConfig: CoreConfig(
                    routingConfig: RoutingConfig(
                        fasterRouteDetectionConfig: nil
                    ),
                    locationSource: .live
                )
            )
        }
        return _navigationProvider!
    }
    
    // MARK: - CPTemplateApplicationSceneDelegate
    
    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        // Initialize CarPlayManager if not already done
        if CarPlaySceneDelegate.carPlayManager == nil {
            CarPlaySceneDelegate.carPlayManager = CarPlayManager(
                navigationProvider: CarPlaySceneDelegate.navigationProvider
            )
        }
        
        guard let carPlayManager = CarPlaySceneDelegate.carPlayManager else { return }
        
        // Set delegate
        carPlayManager.delegate = self
        
        // Connect to CarPlay
        carPlayManager.templateApplicationScene(
            templateApplicationScene,
            didConnectCarInterfaceController: interfaceController,
            to: window
        )
        
        // Notify the main app that CarPlay connected
        NotificationCenter.default.post(
            name: Notification.Name("CarPlayDidConnect"),
            object: nil,
            userInfo: [
                "interfaceController": interfaceController,
                "window": window
            ]
        )
        
        // Check if there's an active navigation to mirror
        CarPlayStateManager.shared.checkForActiveNavigation()
    }
    
    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        guard let carPlayManager = CarPlaySceneDelegate.carPlayManager else { return }
        
        carPlayManager.templateApplicationScene(
            templateApplicationScene,
            didDisconnectCarInterfaceController: interfaceController,
            from: window
        )
        
        // Notify the main app that CarPlay disconnected
        NotificationCenter.default.post(
            name: Notification.Name("CarPlayDidDisconnect"),
            object: nil
        )
    }
}

// MARK: - CarPlayManagerDelegate

extension CarPlaySceneDelegate: CarPlayManagerDelegate {
    
    // MARK: Required method with cameraState parameter
    @_spi(MapboxInternal)
    public func carPlayManager(
        _ carPlayManager: CarPlayManager,
        leadingNavigationBarButtonsCompatibleWith traitCollection: UITraitCollection,
        in carPlayTemplate: CPMapTemplate,
        for activity: CarPlayActivity,
        cameraState: NavigationCameraState
    ) -> [CPBarButton]? {
        return nil
    }
    
    public func carPlayManager(
        _ carPlayManager: CarPlayManager,
        didSetup navigationMapView: NavigationMapView
    ) {
        // Optional: customize the map view after setup
    }
    
    public func carPlayManagerDidBeginNavigation(_ carPlayManager: CarPlayManager) {
        // Notify React Native that CarPlay navigation started
        NotificationCenter.default.post(
            name: Notification.Name("CarPlayNavigationDidBegin"),
            object: nil
        )
    }
    
    public func carPlayManagerDidEndNavigation(_ carPlayManager: CarPlayManager) {
        // Notify React Native that CarPlay navigation ended (legacy method)
        NotificationCenter.default.post(
            name: Notification.Name("CarPlayNavigationDidEnd"),
            object: nil,
            userInfo: ["canceled": false]
        )
    }
    
    public func carPlayManagerDidEndNavigation(_ carPlayManager: CarPlayManager, byCanceling canceled: Bool) {
        // Notify React Native that CarPlay navigation ended
        NotificationCenter.default.post(
            name: Notification.Name("CarPlayNavigationDidEnd"),
            object: nil,
            userInfo: ["canceled": canceled]
        )
    }
    
    public func carPlayManager(
        _ carPlayManager: CarPlayManager,
        shouldPresentArrivalUIFor waypoint: Waypoint
    ) -> Bool {
        return true
    }
}
