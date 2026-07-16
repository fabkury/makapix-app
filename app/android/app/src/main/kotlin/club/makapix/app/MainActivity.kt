package club.makapix.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Memory stress lab (tools/memlab): the lab flow is reachable ONLY through a launch-intent
        // extra - `adb shell am start -n club.makapix.app/.MainActivity -e memlab "<plan>"` - so it
        // can ride normal builds with no UI entry point. Dart polls this once at startup.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "club.makapix.app/memlab")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "plan" -> result.success(intent?.getStringExtra("memlab"))
                    else -> result.notImplemented()
                }
            }
    }
}
