package expo.modules.mapboxnavigation

import android.content.Intent
import android.content.res.Configuration
import androidx.car.app.CarAppService
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.mapbox.android.core.permissions.PermissionsManager

// Maps SDK for Android Auto surfaces
import com.mapbox.maps.MapInitOptions
import com.mapbox.maps.extension.androidauto.MapboxCarMap

// Navigation core
import com.mapbox.navigation.base.options.NavigationOptions
import com.mapbox.navigation.core.lifecycle.MapboxNavigationApp

// Android Auto Navigation components
import com.mapbox.navigation.ui.androidauto.MapboxCarContext
import com.mapbox.navigation.ui.androidauto.map.MapboxCarMapLoader
import com.mapbox.navigation.ui.androidauto.notification.MapboxCarNotificationOptions
import com.mapbox.navigation.ui.androidauto.screenmanager.MapboxScreen
import com.mapbox.navigation.ui.androidauto.screenmanager.MapboxScreenManager
import com.mapbox.navigation.ui.androidauto.screenmanager.prepareScreens
import com.mapbox.navigation.ui.androidauto.deeplink.GeoDeeplinkNavigateAction

class MainCarAppService : CarAppService() {

    override fun createHostValidator(): HostValidator =
        HostValidator.ALLOW_ALL_HOSTS_VALIDATOR

    override fun onCreateSession(): Session =
        MainCarSession()
}

class MainCarSession : Session() {

    // Default loader to keep styles in sync with CarContext.isDarkMode
    private val carMapLoader = MapboxCarMapLoader()   // from ui.androidauto.map
    private val mapboxCarMap = MapboxCarMap().registerObserver(carMapLoader)
    private val mapboxCarContext = MapboxCarContext(lifecycle, mapboxCarMap)

    init {
        // Attach car lifecycle to MapboxNavigationApp
        MapboxNavigationApp.attach(lifecycleOwner = this)

        // Prepare default Mapbox screens (FREE_DRIVE, NEEDS_LOCATION_PERMISSION, etc.)
        mapboxCarContext.prepareScreens()

        // Customize MapboxCarOptions – particularly notification behavior
        mapboxCarContext.customize {
            // Tells which CarAppService to open when the user taps the car trip notification
            notificationOptions = MapboxCarNotificationOptions
                .Builder()
                .startAppService(MainCarAppService::class.java)
                .build()
        }

        lifecycle.addObserver(object : DefaultLifecycleObserver {

            override fun onCreate(owner: LifecycleOwner) {
                // Ensure Navigation is set up once in the process
                if (!MapboxNavigationApp.isSetup()) {
                    MapboxNavigationApp.setup {
                        NavigationOptions
                            .Builder(carContext)
                            // No accessToken(...) here in v3 –
                            // token is read from MapboxOptions / mapbox_access_token.xml
                            .build()
                    }
                }

                // Wire the Mapbox map to the Android Auto surface
                mapboxCarMap.setup(
                    carContext,
                    MapInitOptions(context = carContext)   // <- correct class
                )
            }

            override fun onDestroy(owner: LifecycleOwner) {
                // Clean up observers when the Session is destroyed
                mapboxCarMap.clearObservers()
            }
        })
    }

    override fun onCreateScreen(intent: Intent): Screen {
        // Choose first screen based on location permission
        val firstScreenKey = if (PermissionsManager.areLocationPermissionsGranted(carContext)) {
            MapboxScreenManager.current()?.key ?: MapboxScreen.FREE_DRIVE
        } else {
            MapboxScreen.NEEDS_LOCATION_PERMISSION
        }

        return mapboxCarContext.mapboxScreenManager.createScreen(firstScreenKey)
    }

    override fun onCarConfigurationChanged(newConfiguration: Configuration) {
        // Update map style when dark / light mode changes
        carMapLoader.onCarConfigurationChanged(carContext)
    }

    @OptIn(com.mapbox.navigation.base.ExperimentalPreviewMapboxNavigationAPI::class)
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Handle geo: deep links / voice navigation
        GeoDeeplinkNavigateAction(mapboxCarContext).onNewIntent(intent)
    }
}