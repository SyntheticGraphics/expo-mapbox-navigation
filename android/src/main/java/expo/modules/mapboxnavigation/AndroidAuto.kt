package expo.modules.mapboxnavigation

import android.content.Intent
import android.content.res.Configuration
import androidx.car.app.CarAppService
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.mapbox.android.core.permissions.PermissionsManager
import com.mapbox.maps.MapInitOptions
import com.mapbox.navigation.base.options.NavigationOptions
import com.mapbox.navigation.core.lifecycle.MapboxNavigationApp
import com.mapbox.navigation.ui.androidauto.MapboxCarContext
import com.mapbox.navigation.ui.androidauto.map.MapboxCarMapLoader
import com.mapbox.maps.extension.androidauto.MapboxCarMap
import com.mapbox.navigation.ui.androidauto.deeplink.GeoDeeplinkNavigateAction
import com.mapbox.navigation.ui.androidauto.notification.MapboxCarNotificationOptions
import com.mapbox.navigation.ui.androidauto.screenmanager.MapboxScreen
import com.mapbox.navigation.ui.androidauto.screenmanager.MapboxScreenManager
import com.mapbox.navigation.ui.androidauto.screenmanager.prepareScreens

import androidx.core.content.ContextCompat
import android.Manifest
import android.content.pm.PackageManager
import com.mapbox.common.MapboxOptions
import com.mapbox.maps.ContextMode
import com.mapbox.maps.MapOptions
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import androidx.car.app.ScreenManager
import androidx.car.app.CarContext
import android.net.Uri

@androidx.annotation.OptIn(com.mapbox.navigation.base.ExperimentalPreviewMapboxNavigationAPI::class)
class MainCarAppService : CarAppService() {
    override fun createHostValidator(): HostValidator {
        return HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
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

    init {
        mapboxCarMap.registerObserver(carMapLoader)

        // Attach the car lifecycle to MapboxNavigationApp.
        MapboxNavigationApp.attach(lifecycleOwner = this)

        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onCreate(owner: LifecycleOwner) {
                // 1. Try to recover access token from metadata FIRST
                if (MapboxOptions.accessToken == null) {
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
                    AndroidAutoManager.tripStatus.collect { status ->
                        val screenManager = carContext.getCarService(ScreenManager::class.java)
                        if (status == "AT_STOP") {
                            screenManager.push(PassengerActionScreen(carContext))
                        } else if (status == "COMPLETED") {
                            try {
                                val intent = Intent(CarContext.ACTION_NAVIGATE, Uri.parse("geo:0,0?q="))
                                intent.setPackage("com.google.android.apps.maps")
                                carContext.startCarApp(intent)
                            } catch (e: Exception) {
                                // Fallback or ignore if not supported
                            }
                            carContext.finishCarApp()
                        }
                    }
                }
            }

            override fun onDestroy(owner: LifecycleOwner) {
                mapboxCarMap.clearObservers()
            }
        })
    }

    override fun onCreateScreen(intent: Intent): Screen {
        // Prepare screens before creating the first screen
        mapboxCarContext.prepareScreens()

        // Check for permissions but default to Free Drive to avoid crashes if factory is missing
        val hasLocationPermission = ContextCompat.checkSelfPermission(carContext, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        
        // For now, we force Free Drive or current screen to ensure stability.
        // If permission is missing, the map might just be empty or request it.
        val firstScreenKey = MapboxScreenManager.current()?.key ?: MapboxScreen.FREE_DRIVE

        return mapboxCarContext.mapboxScreenManager.createScreen(firstScreenKey)
    }

    override fun onCarConfigurationChanged(newConfiguration: Configuration) {
        // carMapLoader.updateMapStyle(carContext.isDarkMode)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        GeoDeeplinkNavigateAction(mapboxCarContext).onNewIntent(intent)
    }
}