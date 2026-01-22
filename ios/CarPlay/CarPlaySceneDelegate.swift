import CarPlay
import MapboxNavigationCore
import MapboxNavigationUIKit
import MapboxDirections
import CoreLocation
import MapboxMaps

public class CarPlaySceneDelegate: NSObject, CPTemplateApplicationSceneDelegate {
    
    public static var carPlayManager: CarPlayManager?
    
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
       
    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        if CarPlaySceneDelegate.carPlayManager == nil {
            CarPlaySceneDelegate.carPlayManager = CarPlayManager(
                navigationProvider: CarPlaySceneDelegate.navigationProvider
            )
        }
        
        guard let carPlayManager = CarPlaySceneDelegate.carPlayManager else { return }
        
        carPlayManager.delegate = self
        
        carPlayManager.templateApplicationScene(
            templateApplicationScene,
            didConnectCarInterfaceController: interfaceController,
            to: window
        )
        
        NotificationCenter.default.post(
            name: Notification.Name("CarPlayDidConnect"),
            object: nil,
            userInfo: [
                "interfaceController": interfaceController,
                "window": window
            ]
        )
        
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
        
        NotificationCenter.default.post(
            name: Notification.Name("CarPlayDidDisconnect"),
            object: nil
        )
    }
}

extension CarPlaySceneDelegate: CarPlayManagerDelegate {
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
        NotificationCenter.default.post(
            name: Notification.Name("CarPlayNavigationDidBegin"),
            object: nil
        )
    }
    
    public func carPlayManagerDidEndNavigation(_ carPlayManager: CarPlayManager) {
        NotificationCenter.default.post(
            name: Notification.Name("CarPlayNavigationDidEnd"),
            object: nil,
            userInfo: ["canceled": false]
        )
    }
    
    public func carPlayManagerDidEndNavigation(_ carPlayManager: CarPlayManager, byCanceling canceled: Bool) {
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
