package expo.modules.mapboxnavigation

import android.Manifest
import android.annotation.SuppressLint
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.ParkedOnlyOnClickListener
import androidx.car.app.model.Template
import com.mapbox.android.core.permissions.PermissionsManager
import com.mapbox.navigation.core.lifecycle.MapboxNavigationApp
import com.mapbox.navigation.ui.androidauto.screenmanager.MapboxScreen
import com.mapbox.navigation.ui.androidauto.screenmanager.MapboxScreenManager

class LocationPermissionScreen(carContext: CarContext) : Screen(carContext) {
    @SuppressLint("MissingPermission")
    override fun onGetTemplate(): Template {
        val grantPermissionAction =
            Action.Builder()
                .setTitle("Grant on phone")
                .setOnClickListener(
                    ParkedOnlyOnClickListener.create {
                        carContext.requestPermissions(
                            listOf(
                                Manifest.permission.ACCESS_COARSE_LOCATION,
                                Manifest.permission.ACCESS_FINE_LOCATION,
                            ),
                        ) { _, _ ->
                            if (PermissionsManager.areLocationPermissionsGranted(carContext)) {
                                MapboxNavigationApp.current()
                                    ?.startTripSession(withForegroundService = true)
                                MapboxScreenManager.replaceTop(MapboxScreen.FREE_DRIVE)
                            } else {
                                invalidate()
                            }
                        }
                    },
                )
                .build()

        val closeAction =
            Action.Builder()
                .setTitle("Not now")
                .setOnClickListener { carContext.finishCarApp() }
                .build()

        return MessageTemplate.Builder(
            "For your safety, only use your phone when safely parked. " +
                "When parked, select Grant on phone and allow precise location for TAJPM Driver.",
        )
            .setTitle("Location permission required")
            .setHeaderAction(Action.APP_ICON)
            .addAction(grantPermissionAction)
            .addAction(closeAction)
            .build()
    }
}
