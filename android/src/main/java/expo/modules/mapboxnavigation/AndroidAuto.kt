// AndroidAuto.kt
package expo.mapbox.navigation

import android.content.Intent
import androidx.car.app.CarAppService
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.Template
import androidx.car.app.validation.HostValidator
import androidx.car.app.navigation.model.NavigationTemplate

// Importaciones del ciclo de vida de AndroidX
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

// Importación CORRECTA del Singleton de Mapbox para v3
import com.mapbox.navigation.core.lifecycle.MapboxNavigationApp

// Importaciones del SDK de Mapbox Maps para Android Auto (v3)
import com.mapbox.maps.android.auto.MapboxCarMap
import com.mapbox.maps.plugin.gestures.gestures
import com.mapbox.navigation.base.options.NavigationOptions
import com.mapbox.navigation.ui.androidauto.MapboxCarContext
import com.mapbox.navigation.ui.androidauto.MapboxCarMapLoader
import com.mapbox.navigation.ui.androidauto.navigation.CarNavigationCamera
import com.mapbox.navigation.ui.androidauto.navigation.MapboxCarNavigationManager
import com.mapbox.navigation.ui.maps.camera.NavigationCamera

// ------------------------------------------

/**
 * El servicio que actúa como punto de entrada para Android Auto.
 */
class NavigationCarAppService : CarAppService() {
    override fun createHostValidator(): HostValidator = HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
    override fun onCreateSession(): Session = MainCarSession() // Apuntamos a nuestra nueva Session
}

/**
 * La pantalla de navegación (ahora mucho más simple).
 */
class NavigationScreen(carContext: CarContext, val mapboxCarMap: MapboxCarMap) : Screen(carContext) {
    override fun onGetTemplate(): Template {
        // La plantilla de navegación ahora se construye usando el MapboxCarMap
        return NavigationTemplate.Builder()
            .setMapController(mapboxCarMap)
            .build()
    }
}

/**
 * La Sesión que gestiona TODA la lógica, como indica la documentación de v3.
 */
class MainCarSession : Session() {

    private val carMapLoader = MapboxCarMapLoader()
    private val mapboxCarMap = MapboxCarMap().apply {
        registerObserver(carMapLoader)
    }
    private val mapboxCarContext = MapboxCarContext(this, mapboxCarMap)

    init {
        // Adjuntamos el ciclo de vida de la sesión al Singleton de Mapbox
        MapboxNavigationApp.attach(lifecycleOwner = this)

        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onCreate(owner: LifecycleOwner) {
                // Configuramos el Singleton de Mapbox si no lo está ya
                if (!MapboxNavigationApp.isSetup()) {
                    MapboxNavigationApp.setup(
                        NavigationOptions.Builder(carContext)
                            // DEBES reemplazar esto con tu token de acceso real
                            .accessToken("TU_MAPBOX_ACCESS_TOKEN_AQUÍ")
                            .build()
                    )
                }

                // Preparamos las pantallas y el gestor de navegación
                mapboxCarContext.prepareScreens()
                val carNavigationManager = MapboxCarNavigationManager(
                    mapboxCarMap = mapboxCarMap,
                    carNavigationCamera = CarNavigationCamera(mapboxCarMap),
                    carNavigationInfoProvider = mapboxCarContext.getCarNavigationInfoProvider()
                )

                // Obtenemos el MapboxNavigation y lo registramos
                MapboxNavigationApp.current()?.registerObserver(carNavigationManager)
            }

            override fun onDestroy(owner: LifecycleOwner) {
                // Limpiamos los observadores al destruir la sesión
                mapboxCarMap.clearObservers()
                MapboxNavigationApp.detach(lifecycleOwner = owner)
            }
        })
    }

    override fun onCreateScreen(intent: Intent): Screen {
        // Devolvemos una instancia de nuestra pantalla simple
        return NavigationScreen(carContext, mapboxCarMap)
    }
}