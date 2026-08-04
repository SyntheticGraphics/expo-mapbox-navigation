package expo.modules.mapboxnavigation

import android.annotation.SuppressLint
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import androidx.car.app.CarAppService
import androidx.car.app.ScreenManager
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.lifecycleScope
import com.mapbox.android.core.permissions.PermissionsManager
import com.mapbox.common.MapboxOptions
import com.mapbox.maps.MapInitOptions
import com.mapbox.maps.ContextMode
import com.mapbox.maps.MapOptions
import com.mapbox.maps.extension.androidauto.MapboxCarMap
import com.mapbox.navigation.base.options.NavigationOptions
import com.mapbox.navigation.core.MapboxNavigation
import com.mapbox.navigation.core.lifecycle.MapboxNavigationApp
import com.mapbox.navigation.core.lifecycle.MapboxNavigationObserver
import com.mapbox.navigation.core.replay.route.ReplayRouteSession
import com.mapbox.navigation.ui.androidauto.MapboxCarContext
import com.mapbox.navigation.ui.androidauto.deeplink.GeoDeeplinkNavigateAction
import com.mapbox.navigation.ui.androidauto.map.MapboxCarMapLoader
import com.mapbox.navigation.ui.androidauto.notification.MapboxCarNotificationOptions
import com.mapbox.navigation.ui.androidauto.screenmanager.MapboxScreen
import com.mapbox.navigation.ui.androidauto.screenmanager.MapboxScreenManager
import com.mapbox.navigation.ui.androidauto.screenmanager.prepareScreens
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

@androidx.annotation.OptIn(com.mapbox.navigation.base.ExperimentalPreviewMapboxNavigationAPI::class)
class MainCarAppService : CarAppService() {
    override fun createHostValidator(): HostValidator {
        return if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
        } else {
            HostValidator.Builder(this)
                .addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample)
                .build()
        }
    }

    @OptIn(com.mapbox.navigation.base.ExperimentalPreviewMapboxNavigationAPI::class)
    override fun onCreateSession(): Session {
        return MainSession()
    }
}

@com.mapbox.navigation.base.ExperimentalPreviewMapboxNavigationAPI
class MainSession : Session() {
    // Create the MapboxCarContext and MapboxCarMap. You can use them to build
    // your own customizations.
    private val carMapLoader = MapboxCarMapLoader()
    private val mapboxCarMap = MapboxCarMap()
    private val mapboxCarContext = MapboxCarContext(lifecycle, mapboxCarMap)
    private val replayRouteSession = ReplayRouteSession()
    private var replayRouteSessionRegistered = false

    private val tripSessionObserver = object : MapboxNavigationObserver {
        @SuppressLint("MissingPermission")
        override fun onAttached(mapboxNavigation: MapboxNavigation) {
            if (PermissionsManager.areLocationPermissionsGranted(carContext)) {
                mapboxNavigation.startTripSession(withForegroundService = true)
            }
        }

        override fun onDetached(mapboxNavigation: MapboxNavigation) = Unit
    }

    init {
        mapboxCarMap.registerObserver(carMapLoader)

        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onCreate(owner: LifecycleOwner) {
                // 1. Try to recover access token from metadata FIRST
                if (MapboxOptions.accessToken.isBlank()) {
                    try {
                        val appInfo = carContext.packageManager.getApplicationInfo(carContext.packageName, PackageManager.GET_META_DATA)
                        val token = appInfo.metaData?.getString("MBXAccessToken") 
                            ?: appInfo.metaData?.getString("com.mapbox.token")
                            ?: appInfo.metaData?.getString("mapbox_access_token")
                        
                        if (!token.isNullOrEmpty()) {
                            MapboxOptions.accessToken = token
                        }
                    } catch (e: Exception) {
                        // Ignore
                    }
                }

                // 2. Setup NavigationApp
                if (!MapboxNavigationApp.isSetup()) {
                    MapboxNavigationApp.setup {
                        NavigationOptions.Builder(carContext)
                            .build()
                    }
                }

                MapboxNavigationApp.registerObserver(tripSessionObserver)
                MapboxNavigationApp.attach(owner)

                // 3. Setup CarMap
                mapboxCarMap.setup(
                    carContext,
                    MapInitOptions(
                        context = carContext,
                        mapOptions = MapOptions.Builder()
                            .contextMode(ContextMode.SHARED)
                            .build()
                    )
                )

                // Customize the MapboxCarOptions.
                mapboxCarContext.customize {
                    notificationOptions = MapboxCarNotificationOptions.Builder()
                        .startAppService(MainCarAppService::class.java)
                        .build()
                }

                owner.lifecycleScope.launch {
                    mapboxCarContext.mapboxNavigationManager.autoDriveEnabledFlow
                        .filter { it }
                        .first()

                    if (!replayRouteSessionRegistered) {
                        replayRouteSessionRegistered = true
                        MapboxNavigationApp.registerObserver(replayRouteSession)
                    }
                }

                owner.lifecycleScope.launch {
                    AndroidAutoManager.tripStatus.collect { status ->
                        val screenManager = carContext.getCarService(ScreenManager::class.java)
                        if (status == "AT_STOP") {
                            screenManager.push(PassengerActionScreen(carContext))
                        } else if (status == "COMPLETED") {
                            carContext.finishCarApp()
                        }
                    }
                }
            }

            override fun onDestroy(owner: LifecycleOwner) {
                if (replayRouteSessionRegistered) {
                    MapboxNavigationApp.unregisterObserver(replayRouteSession)
                    replayRouteSessionRegistered = false
                }
                MapboxNavigationApp.unregisterObserver(tripSessionObserver)
                MapboxNavigationApp.detach(owner)
                mapboxCarMap.clearObservers()
            }
        })
    }

    override fun onCreateScreen(intent: Intent): Screen {
        // Prepare screens before creating the first screen
        mapboxCarContext.prepareScreens()

        GeoDeeplinkNavigateAction(mapboxCarContext).onNewIntent(intent)

        val hasLocationPermission =
            PermissionsManager.areLocationPermissionsGranted(carContext)

        val currentScreenKey = MapboxScreenManager.current()?.key

        val firstScreenKey = when {
            !hasLocationPermission ->
                MapboxScreen.NEEDS_LOCATION_PERMISSION

            currentScreenKey == MapboxScreen.NEEDS_LOCATION_PERMISSION ->
                MapboxScreen.FREE_DRIVE

            else ->
                currentScreenKey ?: MapboxScreen.FREE_DRIVE
        }

        return mapboxCarContext.mapboxScreenManager.createScreen(firstScreenKey)
    }

    override fun onCarConfigurationChanged(newConfiguration: Configuration) {
        carMapLoader.onCarConfigurationChanged(carContext)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        GeoDeeplinkNavigateAction(mapboxCarContext).onNewIntent(intent)
    }
}
