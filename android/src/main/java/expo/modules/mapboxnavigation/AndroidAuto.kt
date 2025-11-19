// AndroidAuto.kt
package expo.mapbox.navigation

import android.content.Intent
import androidx.car.app.CarAppService
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator
import com.mapbox.navigation.core.MapboxNavigation
import com.mapbox.navigation.core.MapboxNavigationApp
import com.mapbox.navigation.ui.car.NavigationCarScreen

// 1. El Servicio
class NavigationCarAppService : CarAppService() {
    override fun createHostValidator(): HostValidator {
        return HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
    }

    override fun onCreateSession(): Session {
        return NavigationSession()
    }
}

// 2. La Sesión
class NavigationSession : Session() {
    override fun onCreateScreen(intent: Intent): Screen {
        return MyCarScreen(carContext)
    }
}

// 3. LA PANTALLA CORRECTA Y DEFINITIVA
class MyCarScreen(carContext: androidx.car.app.CarContext) : NavigationCarScreen(carContext) {

    /**
     * Este método es llamado por la pantalla del coche para obtener la instancia de navegación
     * que se está ejecutando en el teléfono.
     */
    override fun getMapboxNavigation(): MapboxNavigation? {
        // Le pedimos al Singleton oficial de Mapbox que nos dé la instancia actual.
        return MapboxNavigationApp.current()
    }
}