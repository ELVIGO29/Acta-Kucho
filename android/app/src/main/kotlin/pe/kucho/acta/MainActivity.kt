package pe.kucho.acta

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "pe.kucho.acta/datos"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "obtenerDatosActa" -> {
                    val datos = extraerDatosIntent(intent)
                    result.success(datos)
                }
                "cerrarConExito" -> {
                    setResult(Activity.RESULT_OK)
                    finishAndRemoveTask()
                    result.success(true)
                }
                "cerrarCancelado" -> {
                    setResult(Activity.RESULT_CANCELED)
                    finishAndRemoveTask()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    private fun extraerDatosIntent(intent: Intent?): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        if (intent == null) return map

        // 1. Extraer desde Intent Extras
        intent.getStringExtra("idSolicitud")?.let { map["idSolicitud"] = it }
        intent.getStringExtra("nombreCliente")?.let { map["nombreCliente"] = it }
        intent.getStringExtra("categoria")?.let { map["categoria"] = it }
        intent.getStringExtra("distrito")?.let { map["distrito"] = it }
        intent.getStringExtra("token")?.let { map["token"] = it }
        if (intent.hasExtra("monto")) {
            map["monto"] = intent.getDoubleExtra("monto", 0.0)
        }

        // 2. Extraer desde Deep Link (kucho://acta?idSolicitud=...&monto=...)
        val dataUri: Uri? = intent.data
        if (dataUri != null) {
            dataUri.getQueryParameter("idSolicitud")?.let { map["idSolicitud"] = it }
            dataUri.getQueryParameter("nombreCliente")?.let { map["nombreCliente"] = it }
            dataUri.getQueryParameter("categoria")?.let { map["categoria"] = it }
            dataUri.getQueryParameter("distrito")?.let { map["distrito"] = it }
            dataUri.getQueryParameter("token")?.let { map["token"] = it }
            dataUri.getQueryParameter("monto")?.toDoubleOrNull()?.let { map["monto"] = it }
        }

        return map
    }
}

