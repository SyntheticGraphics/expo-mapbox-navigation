// NavigationCarAppService.kt
package com.youssefhenna.expo.mapbox.navigation // Asegúrate de que el package sea el correcto

import androidx.car.app.CarAppService
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator

class NavigationCarAppService : CarAppService() {
    override fun createHostValidator(): HostValidator {
        // Permite la conexión con cualquier host (para desarrollo)
        return HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
    }

    override fun onCreateSession(): Session {
        // Crea y devuelve una nueva sesión para el coche
        return NavigationSession()
    }
}