package expo.modules.mapboxnavigation

import android.content.Intent
import androidx.car.app.Screen
import androidx.car.app.Session

class NavigationSession : Session() {
    override fun onCreateScreen(intent: Intent): Screen {
        // Esta es la primera pantalla que verá el usuario en el coche
        return NavigationMapScreen(carContext)
    }
}