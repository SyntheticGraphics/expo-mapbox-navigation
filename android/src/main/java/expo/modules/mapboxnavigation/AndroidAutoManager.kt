package expo.modules.mapboxnavigation

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.ScreenManager
import androidx.car.app.model.Action
import androidx.car.app.model.CarColor
import androidx.car.app.model.Pane
import androidx.car.app.model.PaneTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

object AndroidAutoManager {
    private val _tripStatus = MutableStateFlow("IDLE")
    val tripStatus: StateFlow<String> = _tripStatus.asStateFlow()

    private val _currentStopInfo = MutableStateFlow<Map<String, Any?>?>(null)
    val currentStopInfo: StateFlow<Map<String, Any?>?> = _currentStopInfo.asStateFlow()

    private val _passengerInfo = MutableStateFlow<List<Map<String, Any>>>(emptyList())
    val passengerInfo: StateFlow<List<Map<String, Any>>> = _passengerInfo.asStateFlow()

    var onActionCallback: ((String, Map<String, Any>?) -> Unit)? = null

    fun updateState(status: String, stopInfo: Map<String, Any?>?, passengers: List<Map<String, Any>>) {
        _tripStatus.value = status
        _currentStopInfo.value = stopInfo
        _passengerInfo.value = passengers
    }

    fun resetTripState() {
        _tripStatus.value = "IDLE"
        _currentStopInfo.value = null
        _passengerInfo.value = emptyList()
    }

    fun sendAction(action: String, data: Map<String, Any>? = null) {
        onActionCallback?.invoke(action, data)
    }
}
