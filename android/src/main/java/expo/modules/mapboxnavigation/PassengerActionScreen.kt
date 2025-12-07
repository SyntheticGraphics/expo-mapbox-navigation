package expo.modules.mapboxnavigation

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.*
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

class PassengerActionScreen(carContext: CarContext) : Screen(carContext) {

    init {
        lifecycleScope.launch {
            AndroidAutoManager.passengerInfo.collect {
                invalidate()
            }
        }
    }

    override fun onGetTemplate(): Template {
        val stopInfo = AndroidAutoManager.currentStopInfo.value
        val passengers = AndroidAutoManager.passengerInfo.value
        val stopType = stopInfo?.get("type") as? String ?: "pickup"
        val address = stopInfo?.get("address") as? String ?: "Stop"

        val listBuilder = ItemList.Builder()

        if (passengers.isEmpty()) {
            listBuilder.addItem(
                Row.Builder()
                    .setTitle("No passengers")
                    .build()
            )
        } else {
            passengers.forEach { passenger ->
                val name = passenger["name"] as? String ?: "Unknown"
                val id = passenger["passengerId"] as? String ?: ""
                val isPicked = passenger["status"] == "picked_up"
                val isDropped = passenger["status"] == "dropped_off"
                val isSelected = isPicked || isDropped

                val rowBuilder = Row.Builder()
                    .setTitle(name)

                if (stopType == "pickup") {
                    rowBuilder.setToggle(
                        Toggle.Builder { isChecked ->
                            AndroidAutoManager.sendAction(
                                if (isChecked) "PASSENGER_PICKUP" else "PASSENGER_NOLOAD", // Assuming uncheck means noload/undo? Or just toggle state
                                mapOf("passengerId" to id, "isChecked" to isChecked)
                            )
                        }
                        .setChecked(isSelected)
                        .build()
                    )
                } else {
                     // For dropoff, maybe just a click to confirm? Or a toggle too?
                     // User asked for "checkbox" to mark as pickup or noload.
                     // For dropoff, usually it's "dropped off".
                     rowBuilder.setToggle(
                        Toggle.Builder { isChecked ->
                            AndroidAutoManager.sendAction(
                                "PASSENGER_DROPOFF",
                                mapOf("passengerId" to id, "isChecked" to isChecked)
                            )
                        }
                        .setChecked(isSelected)
                        .build()
                    )
                }

                listBuilder.addItem(rowBuilder.build())
            }
        }

        return ListTemplate.Builder()
            .setTitle(address)
            .setSingleList(listBuilder.build())
            .setHeaderAction(Action.BACK)
            .setActionStrip(
                ActionStrip.Builder()
                    .addAction(
                        Action.Builder()
                            .setTitle("Depart")
                            .setOnClickListener {
                                AndroidAutoManager.sendAction("DEPART_STOP")
                                screenManager.pop()
                            }
                            .build()
                    )
                    .build()
            )
            .build()
    }
}
