package expo.modules.mapboxnavigation

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.CarIcon
import androidx.car.app.model.Template
import androidx.car.app.navigation.model.NavigationTemplate
import androidx.core.graphics.drawable.IconCompat
import com.mapbox.navigation.android.car.MapboxCarMap

class NavigationMapScreen(carContext: CarContext) : Screen(carContext) {

    private lateinit var mapboxCarMap: MapboxCarMap

    init {
        // Aquí inicializas el mapa de Mapbox para el coche.
        // Necesitarás configurar el acceso al token de Mapbox, etc.
        mapboxCarMap = MapboxCarMap.create(carContext, this)
    }

    override fun onGetTemplate(): Template {
        // El ActionStrip son los botones que aparecen en la barra superior.
        val actionStrip = ActionStrip.Builder()
            .addAction(
                Action.Builder()
                    .setTitle("Centrar")
                    .setIcon(
                        CarIcon.Builder(
                            IconCompat.createWithResource(carContext, R.drawable.ic_map_center) // Necesitarás añadir este icono
                        ).build()
                    )
                    .setOnClickListener { mapboxCarMap.recenter() }
                    .build()
            )
            .build()

        // La NavigationTemplate es la plantilla principal para apps de navegación
        return NavigationTemplate.Builder()
            .setActionStrip(actionStrip)
            .setMapActionStrip(ActionStrip.Builder().build()) // Puedes añadir botones de zoom aquí
            .build()
    }
}