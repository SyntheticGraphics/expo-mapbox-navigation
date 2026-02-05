import ExpoModulesCore
import MapboxNavigationCore
import MapboxMaps
import MapboxNavigationUIKit
import MapboxDirections
import Combine
import Foundation

@MainActor
public class NavigationProviderManager {
    public static let shared = NavigationProviderManager()
    
    private var currentProvider: MapboxNavigationProvider?
    private var isSimulation: Bool = false
    private var hasBeenInitialized: Bool = false
    
    public var isNavigationSessionActive: Bool = false
    
    private init() {}
    
    public func getProvider(forSimulation simulation: Bool, initialLocation: CLLocation? = nil) -> MapboxNavigationProvider {
        if let provider = currentProvider {
            return provider
        }

        let coreConfig = CoreConfig(
            routingConfig: RoutingConfig(fasterRouteDetectionConfig: nil),
            locationSource: simulation ? .simulation(initialLocation: initialLocation) : .live
        )
        
        let newProvider = MapboxNavigationProvider(coreConfig: coreConfig)
        currentProvider = newProvider
        isSimulation = simulation
        hasBeenInitialized = true
        
        return newProvider
    }
    
    public var currentMode: Bool {
        return isSimulation
    }
    
    public weak var currentNavigationViewController: NavigationViewController?
    
    public func stopActiveNavigation() {
        if let navVC = currentNavigationViewController {
            navVC.delegate = nil
            navVC.willMove(toParent: nil)
            navVC.view.removeFromSuperview()
            navVC.removeFromParent()
            currentNavigationViewController = nil
        }
        
        if isNavigationSessionActive, let provider = currentProvider {
            provider.mapboxNavigation.tripSession().setToIdle()
            isNavigationSessionActive = false
        }
    }
    
    public func registerNavigationViewController(_ navigationVC: NavigationViewController) {
        if let oldVC = currentNavigationViewController {
            oldVC.delegate = nil
            oldVC.willMove(toParent: nil)
            oldVC.view.removeFromSuperview()
            oldVC.removeFromParent()
        }
        
        if isNavigationSessionActive, let provider = currentProvider {
            provider.mapboxNavigation.tripSession().setToIdle()
        }
        
        currentNavigationViewController = navigationVC
        isNavigationSessionActive = true
    }
    
    public func cleanup() {
        stopActiveNavigation()
    }
}

class CustomBottomBarViewController: ContainerViewController {}

class ExpoMapboxNavigationView: ExpoView {
    private let onRouteProgressChanged = EventDispatcher()
    private let onCancelNavigation = EventDispatcher()
    private let onWaypointArrival = EventDispatcher()
    private let onFinalDestinationArrival = EventDispatcher()
    private let onRouteChanged = EventDispatcher()
    private let onUserOffRoute = EventDispatcher()
    private let onRoutesLoaded = EventDispatcher()
    private let onRouteFailedToLoad = EventDispatcher()
    private let onNavigationLocationUpdate = EventDispatcher()

    let controller = ExpoMapboxNavigationViewController()

    required init(appContext: AppContext? = nil) {
        super.init(appContext: appContext)
        clipsToBounds = true
        addSubview(controller.view)

        controller.onRouteProgressChanged = onRouteProgressChanged
        controller.onCancelNavigation = onCancelNavigation
        controller.onWaypointArrival = onWaypointArrival
        controller.onFinalDestinationArrival = onFinalDestinationArrival
        controller.onRouteChanged = onRouteChanged
        controller.onUserOffRoute = onUserOffRoute
        controller.onRoutesLoaded = onRoutesLoaded
        controller.onRouteFailedToLoad = onRouteFailedToLoad
        controller.onNavigationLocationUpdate = onNavigationLocationUpdate
    }

    override func layoutSubviews() {
        controller.view.frame = bounds
    }
}

class ExpoMapboxNavigationViewController: UIViewController {   
    var currentProvider: MapboxNavigationProvider? = nil
    var mapboxNavigation: MapboxNavigation? = nil
    var routingProvider: RoutingProvider? = nil
    var navigation: NavigationController? = nil
    var tripSession: SessionController? = nil
    var navigationViewController: NavigationViewController? = nil
    var currentCoordinates: Array<CLLocationCoordinate2D>? = nil
    var initialLocation: CLLocationCoordinate2D? = nil
    var initialLocationZoom: Double? = nil
    var currentWaypointIndices: Array<Int>? = nil
    var currentLocale: Locale = Locale.current
    var currentRouteProfile: String? = nil
    var currentRouteExcludeList: Array<String>? = nil
    var currentMapStyle: String? = nil
    var currentCustomRasterSourceUrl: String? = nil
    var currentPlaceCustomRasterLayerAbove: String? = nil
    var currentDisableAlternativeRoutes: Bool? = nil
    var currentFollowingZoom: Double? = nil
    var isUsingRouteMatchingApi: Bool = false
    var vehicleMaxHeight: Double? = nil
    var vehicleMaxWidth: Double? = nil
    var isSimulationEnabled: Bool = false
    var hasInitializedProvider: Bool = false
    var onRouteProgressChanged: EventDispatcher? = nil
    var onCancelNavigation: EventDispatcher? = nil
    var onWaypointArrival: EventDispatcher? = nil
    var onFinalDestinationArrival: EventDispatcher? = nil
    var onRouteChanged: EventDispatcher? = nil
    var onUserOffRoute: EventDispatcher? = nil
    var onRoutesLoaded: EventDispatcher? = nil
    var onRouteFailedToLoad: EventDispatcher? = nil
    var onNavigationLocationUpdate: EventDispatcher? = nil
    var calculateRoutesTask: Task<Void, Error>? = nil

    private var routeProgressCancellable: AnyCancellable? = nil
    private var waypointArrivalCancellable: AnyCancellable? = nil
    private var reroutingCancellable: AnyCancellable? = nil
    private var sessionCancellable: AnyCancellable? = nil
    private var locationMatchingCancellable: AnyCancellable? = nil
    private var isCalculatingRoutes: Bool = false
    private var pendingUpdate: Bool = false
    private var lastUpdateTime: Date? = nil

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    func setupNavigationReferences(provider: MapboxNavigationProvider) {
        mapboxNavigation = provider.mapboxNavigation
        routingProvider = mapboxNavigation!.routingProvider()
        navigation = mapboxNavigation!.navigation()
        tripSession = mapboxNavigation!.tripSession()
        
        subscribeToEvents()
    }

    func unsubscribeFromEvents() {
        routeProgressCancellable?.cancel()
        waypointArrivalCancellable?.cancel()
        reroutingCancellable?.cancel()
        sessionCancellable?.cancel()
        locationMatchingCancellable?.cancel()
    }

    func subscribeToEvents() {
        locationMatchingCancellable = navigation!.locationMatching.sink { state in
             let enhancedLocation = state.enhancedLocation
             self.onNavigationLocationUpdate?([
                 "latitude": enhancedLocation.coordinate.latitude,
                 "longitude": enhancedLocation.coordinate.longitude,
                 "heading": enhancedLocation.course,
                 "speed": enhancedLocation.speed,
                 "timestamp": enhancedLocation.timestamp.description
             ])
        }

        routeProgressCancellable = navigation!.routeProgress.sink { progressState in
            if(progressState != nil){
               self.onRouteProgressChanged?([
                    "distanceRemaining": progressState!.routeProgress.distanceRemaining,
                    "distanceTraveled": progressState!.routeProgress.distanceTraveled,
                    "durationRemaining": progressState!.routeProgress.durationRemaining,
                    "fractionTraveled": progressState!.routeProgress.fractionTraveled,
                    "legDistanceRemaining": progressState!.routeProgress.currentLegProgress.distanceRemaining,
                    "legDurationRemaining": progressState!.routeProgress.currentLegProgress.durationRemaining,
                    "legFractionTraveled": progressState!.routeProgress.currentLegProgress.fractionTraveled,
                    "legIndex": progressState!.routeProgress.legIndex,
                    "currentLeg": progressState!.routeProgress.currentLegProgress,
                ])
            }
        }

        waypointArrivalCancellable = navigation!.waypointsArrival.sink { arrivalStatus in
            let event = arrivalStatus.event
            if event is WaypointArrivalStatus.Events.ToFinalDestination {
                self.onFinalDestinationArrival?()
            } else if event is WaypointArrivalStatus.Events.ToWaypoint {
                self.onWaypointArrival?()
            }
        }

        reroutingCancellable = navigation!.rerouting.sink { rerouteStatus in
            self.onRouteChanged?()            
        }

        sessionCancellable = tripSession!.session.sink { session in 
            let state = session.state
            switch state {
                case .activeGuidance(let activeGuidanceState):
                    switch(activeGuidanceState){
                        case .offRoute:
                            self.onUserOffRoute?()
                        default: break
                    }
                default: break
            }
        }
    }

    deinit {
        routeProgressCancellable?.cancel()
        waypointArrivalCancellable?.cancel()
        reroutingCancellable?.cancel()
        sessionCancellable?.cancel()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        fatalError("This controller should not be loaded through a story board")
    }

    func addCustomRasterLayer() {
        let navigationMapView = navigationViewController?.navigationMapView
        let sourceId = "raster-source"
        let layerId = "raster-layer"

        if(currentCustomRasterSourceUrl == nil){
            if let mapView = navigationMapView?.mapView.mapboxMap {
                if mapView.layerExists(withId: layerId) {
                    try? mapView.removeLayer(withId: layerId)
                }
                if mapView.sourceExists(withId: sourceId) {
                    try? mapView.removeSource(withId: sourceId)
                }
            }
            return
        }

        let sourceUrl = currentCustomRasterSourceUrl! 

        var rasterSource = RasterSource(id: sourceId)

        rasterSource.tiles = [sourceUrl]
        rasterSource.tileSize = 256

        let rasterLayer = RasterLayer(id: layerId, source: sourceId)


        if let mapView = navigationMapView?.mapView.mapboxMap {
            if mapView.layerExists(withId: layerId) {
                try? mapView.removeLayer(withId: layerId)
            }
            if mapView.sourceExists(withId: sourceId) {
                try? mapView.removeSource(withId: sourceId)
            }

            try? mapView.addSource(rasterSource)
            try? mapView.addLayer(rasterLayer, layerPosition: .above(currentPlaceCustomRasterLayerAbove ?? "water"))    
        }
    }


    func setCoordinates(coordinates: Array<CLLocationCoordinate2D>) {
        currentCoordinates = coordinates
        update()
    }

    func setVehicleMaxHeight(maxHeight: Double?) {
        vehicleMaxHeight = maxHeight
    }
    
    func setSimulation(simulation: Bool?) {
        let newValue = simulation == true

        if isSimulationEnabled != newValue {
            isSimulationEnabled = newValue
            update()
        }
    }

    func setVehicleMaxWidth(maxWidth: Double?) {
        vehicleMaxWidth = maxWidth
    }

    func setLocale(locale: String?) {
        if(locale != nil){
            currentLocale = Locale(identifier: locale!)
        } else {
            currentLocale = Locale.current
        }
        update()
    }

    func setIsUsingRouteMatchingApi(useRouteMatchingApi: Bool?){
        isUsingRouteMatchingApi = useRouteMatchingApi ?? false
        update()
    }

    func setWaypointIndices(waypointIndices: Array<Int>?){
        currentWaypointIndices = waypointIndices
        update()
    }

    func setRouteProfile(profile: String?){
        currentRouteProfile = profile
        update()
    }

    func setRouteExcludeList(excludeList: Array<String>?){
        currentRouteExcludeList = excludeList
        update()
    }

    func setMapStyle(style: String?){
        currentMapStyle = style
        update()
    }

    func setCustomRasterSourceUrl(url: String?){
        currentCustomRasterSourceUrl = url
        update()
    }

    func setPlaceCustomRasterLayerAbove(layerId: String?){
        currentPlaceCustomRasterLayerAbove = layerId
        update()
    }

    func setDisableAlternativeRoutes(disableAlternativeRoutes: Bool?){
        currentDisableAlternativeRoutes = disableAlternativeRoutes
        update()
    }

    func recenterMap(){
        let navigationMapView = navigationViewController?.navigationMapView
        navigationMapView?.navigationCamera.update(cameraState: .following)
    }

    func setIsMuted(isMuted: Bool?){
        if let muted = isMuted, let provider = currentProvider {
            provider.routeVoiceController.speechSynthesizer.muted = muted
        }
    }

    func setInitialLocation(location: CLLocationCoordinate2D, zoom: Double?){
        initialLocation = location
        initialLocationZoom = zoom
        let navigationMapView = navigationViewController?.navigationMapView
        if(initialLocation != nil && navigationMapView != nil){
            navigationMapView!.mapView.mapboxMap.setCamera(to: CameraOptions(center: initialLocation!, zoom: initialLocationZoom ?? 15))
        }
    }

    func setFollowingZoom(followingZoom: Double?){
        let navigationMapView = navigationViewController?.navigationMapView
        currentFollowingZoom = followingZoom
        if(navigationMapView != nil && followingZoom != nil){
            let newDataSource = MobileViewportDataSource(navigationMapView!.mapView)
            newDataSource.options.followingCameraOptions.zoomRange = followingZoom!...followingZoom!
            navigationMapView?.navigationCamera.viewportDataSource = newDataSource
        }
    }

    func update(){
        calculateRoutesTask?.cancel()
        calculateRoutesTask = nil

        guard let coordinates = currentCoordinates, coordinates.count >= 2 else {
            return
        }
        
        let now = Date()
        let debounceInterval = 0.5
        
        if let lastUpdate = lastUpdateTime, now.timeIntervalSince(lastUpdate) < debounceInterval {
            pendingUpdate = true
            return
        }

        if lastUpdateTime == nil || now.timeIntervalSince(lastUpdateTime!) >= debounceInterval {
            lastUpdateTime = now
            pendingUpdate = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval) { [weak self] in
                guard let self = self, self.pendingUpdate else { 
                    return 
                }
                self.pendingUpdate = false
                self.executeUpdate()
            }
            return
        }
    }
    
    private func executeUpdate() {
        guard let coordinates = currentCoordinates, coordinates.count >= 2 else {
            return
        }
        
        if isCalculatingRoutes {
            pendingUpdate = true
            lastUpdateTime = nil
            update()
            return
        }
        
        let provider = setupProviderForCurrentMode()
        
        let waypoints = coordinates.enumerated().map {
            let index = $0
            let coordinate = $1
            var waypoint = Waypoint(coordinate: coordinate) 
            waypoint.separatesLegs = currentWaypointIndices == nil ? true : currentWaypointIndices!.contains(index)
            return waypoint
        }

        if(isUsingRouteMatchingApi){
            calculateMapMatchingRoutes(waypoints: waypoints, provider: provider)
        } else {
            calculateRoutes(waypoints: waypoints, provider: provider)
        }
    }
    
    func setupProviderForCurrentMode() -> MapboxNavigationProvider {
        var simInitialLocation: CLLocation? = nil
        if let coord = currentCoordinates?.first {
            simInitialLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        }
        
        let provider = NavigationProviderManager.shared.getProvider(
            forSimulation: isSimulationEnabled,
            initialLocation: simInitialLocation
        )
    
        let providerChanged = currentProvider !== provider
        
        if providerChanged {
            unsubscribeFromEvents()
            
            if let vc = navigationViewController {
                vc.delegate = nil
                vc.willMove(toParent: nil)
                vc.view.removeFromSuperview()
                vc.removeFromParent()
                navigationViewController = nil
            }
            
            currentProvider = provider
            setupNavigationReferences(provider: provider)
        }
        
        return provider
    }

    func calculateRoutes(waypoints: Array<Waypoint>, provider: MapboxNavigationProvider){       
        isCalculatingRoutes = true
        
        let routeOptions = NavigationRouteOptions(
            waypoints: waypoints, 
            profileIdentifier: currentRouteProfile != nil ? ProfileIdentifier(rawValue: currentRouteProfile!) : nil,
            queryItems: [
                URLQueryItem(name: "exclude", value: currentRouteExcludeList?.joined(separator: ",")),
                URLQueryItem(name: "max_height", value: String(format: "%.1f", vehicleMaxHeight ?? 0.0)),
                URLQueryItem(name: "max_width", value: String(format: "%.1f", vehicleMaxWidth ?? 0.0))
            ],
            locale: currentLocale, 
            distanceUnit: currentLocale.usesMetricSystem ? LengthFormatter.Unit.meter : LengthFormatter.Unit.mile
        )

        calculateRoutesTask = Task {
            defer {
                Task { @MainActor in
                    self.isCalculatingRoutes = false
                    if self.pendingUpdate {
                        self.update()
                    }
                }
            }
            
            if Task.isCancelled {
                return
            }
            
            switch await self.routingProvider!.calculateRoutes(options: routeOptions).result {
            case .failure(let error):
                await MainActor.run {
                    self.onRouteFailedToLoad?([
                        "errorMessage": error.localizedDescription
                    ])
                }
            case .success(let navigationRoutes):
                if Task.isCancelled {
                    return
                }
                await MainActor.run {
                    self.onRoutesCalculated(navigationRoutes: navigationRoutes, provider: provider)
                }
            }
        }
    }

    func calculateMapMatchingRoutes(waypoints: Array<Waypoint>, provider: MapboxNavigationProvider){       
        isCalculatingRoutes = true
        
        let matchOptions = NavigationMatchOptions(
            waypoints: waypoints, 
            profileIdentifier: currentRouteProfile != nil ? ProfileIdentifier(rawValue: currentRouteProfile!) : nil,
            queryItems: [URLQueryItem(name: "exclude", value: currentRouteExcludeList?.joined(separator: ","))],
            distanceUnit: currentLocale.usesMetricSystem ? LengthFormatter.Unit.meter : LengthFormatter.Unit.mile
        )
        matchOptions.locale = currentLocale


        calculateRoutesTask = Task {
            defer {
                Task { @MainActor in
                    self.isCalculatingRoutes = false
                    if self.pendingUpdate {
                        self.update()
                    }
                }
            }
            
            if Task.isCancelled {
                return
            }
            
            switch await self.routingProvider!.calculateRoutes(options: matchOptions).result {
            case .failure(let error):
                await MainActor.run {
                    self.onRouteFailedToLoad?([
                        "errorMessage": error.localizedDescription
                    ])
                }
            case .success(let navigationRoutes):
                if Task.isCancelled {
                    return
                }
                await MainActor.run {
                    self.onRoutesCalculated(navigationRoutes: navigationRoutes, provider: provider)
                }
            }
        }
    }

    @objc func cancelButtonClicked(_ sender: AnyObject?) {
        onCancelNavigation?()
    }

    func convertRoute(route: Route) -> Any {
        return [
            "distance": route.distance,
            "expectedTravelTime": route.expectedTravelTime,
            "legs": route.legs.map { leg in
                return [
                    "source": leg.source != nil ? [
                        "latitude": leg.source!.coordinate.latitude,
                        "longitude": leg.source!.coordinate.longitude
                    ] : nil,
                    "destination": leg.destination != nil ? [
                        "latitude": leg.destination!.coordinate.latitude,
                        "longitude": leg.destination!.coordinate.longitude
                    ] : nil,
                    "steps": leg.steps.map { step in
                        return [
                            "shape": step.shape != nil ? [
                                "coordinates": step.shape!.coordinates.map { coordinate in
                                    return [
                                        "latitude": coordinate.latitude,
                                        "longitude": coordinate.longitude,
                                    ]
                                }
                            ] : nil
                        ]
                    }
                ]
            }
        ]
    }

    func onRoutesCalculated(navigationRoutes: NavigationRoutes, provider: MapboxNavigationProvider){       
        onRoutesLoaded?([
            "routes": [
                "mainRoute": convertRoute(route: navigationRoutes.mainRoute.route),
                "alternativeRoutes": navigationRoutes.alternativeRoutes.map { convertRoute(route: $0.route) }
            ]
        ])

        let topBanner = TopBannerViewController()
        topBanner.instructionsBannerView.distanceFormatter.locale = currentLocale
        let bottomBanner = CustomBottomBarViewController()

        startNavigationWithRoutes(navigationRoutes: navigationRoutes, provider: provider, topBanner: topBanner, bottomBanner: bottomBanner)
    }
    
    func startNavigationWithRoutes(navigationRoutes: NavigationRoutes, provider: MapboxNavigationProvider, topBanner: TopBannerViewController, bottomBanner: CustomBottomBarViewController) {  
        guard let mapboxNav = self.mapboxNavigation else {
            return
        }
        
        // Obtener la posición inicial del driver (primer coordenada) ANTES de destruir el VC
        let driverPosition: CLLocationCoordinate2D? = currentCoordinates?.first
        
        // Marcar que estamos actualizando waypoints para evitar la animación desde el mundo
        let wasNavigating = navigationViewController != nil
        
        NavigationProviderManager.shared.stopActiveNavigation()

        navigationViewController = nil
        
        let navigationOptions = NavigationOptions(
            mapboxNavigation: mapboxNav,
            voiceController: provider.routeVoiceController,
            eventsManager: provider.eventsManager(),
            styles: [DayStyle()],
            topBanner: topBanner,
            bottomBanner: bottomBanner
        )
        
        navigationViewController = NavigationViewController(
            navigationRoutes: navigationRoutes,
            navigationOptions: navigationOptions
        )
        
        let navVC = navigationViewController!

        navVC.showsContinuousAlternatives = currentDisableAlternativeRoutes != true
        navVC.usesNightStyleWhileInTunnel = false
        navVC.automaticallyAdjustsStyleForTimeOfDay = false

        let navigationMapView = navVC.navigationMapView
        navigationMapView!.puckType = .puck2D(.navigationDefault)

        // IMPORTANTE: Establecer la cámara INMEDIATAMENTE a la posición del driver
        // ANTES de mostrar la vista, para evitar la animación "fly from space"
        if let driverPos = driverPosition {
            navigationMapView!.mapView.mapboxMap.setCamera(to: CameraOptions(
                center: driverPos, 
                zoom: currentFollowingZoom ?? 16.0,
                bearing: 0,
                pitch: 45
            ))
        } else if let initialLoc = initialLocation {
            navigationMapView!.mapView.mapboxMap.setCamera(to: CameraOptions(
                center: initialLoc, 
                zoom: initialLocationZoom ?? 16.0
            ))
        }

        let style = currentMapStyle != nil ? StyleURI(rawValue: currentMapStyle!) : StyleURI.streets
        navigationMapView!.mapView.mapboxMap.loadStyle(style!, completion: { _ in
            navigationMapView!.localizeLabels(locale: self.currentLocale)
            do{
                try navigationMapView!.mapView.mapboxMap.localizeLabels(into: self.currentLocale)
            } catch {}
            self.addCustomRasterLayer()
        })
        
        navVC.delegate = self
        addChild(navVC)
        view.addSubview(navVC.view)
        navVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            navVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 0),
            navVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 0),
            navVC.view.topAnchor.constraint(equalTo: view.topAnchor, constant: 0),
            navVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0),
        ])
        didMove(toParent: self)

        NavigationProviderManager.shared.registerNavigationViewController(navVC)
        
        // IMPORTANTE: Activar el modo "following" INMEDIATAMENTE para evitar 
        // que la cámara empiece desde la vista mundial
        // Usar transición instantánea (sin animación) cuando estamos actualizando waypoints
        if wasNavigating {
            // Transición instantánea cuando ya estábamos navegando
            navigationMapView?.navigationCamera.update(cameraState: .following)
        } else {
            // Primera vez - pequeño delay para que el SDK se configure
            DispatchQueue.main.async {
                navigationMapView?.navigationCamera.update(cameraState: .following)
            }
        }
    }
    
    func stopNavigation() {
        NavigationProviderManager.shared.stopActiveNavigation()
    }
}

extension ExpoMapboxNavigationViewController: NavigationViewControllerDelegate {
    func navigationViewController(_ navigationViewController: NavigationViewController, didRerouteAlong route: Route) {
        onRoutesLoaded?([
            "routes": [
                "mainRoute": convertRoute(route: route),
                "alternativeRoutes": []
            ]
        ])
    }

    func navigationViewControllerDidDismiss(
        _ navigationViewController: NavigationViewController,
        byCanceling canceled: Bool
    ) { }
}

extension UIView {
    func findViews<T: UIView>(subclassOf: T.Type) -> [T] {
        return recursiveSubviews.compactMap { $0 as? T }
    }

    var recursiveSubviews: [UIView] {
        return subviews + subviews.flatMap { $0.recursiveSubviews }
    }
}
