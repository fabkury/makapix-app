import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kAnimationAutoplayPrefKey = 'club.animation_autoplay';

/// The local "Play animations" setting (default ON). Purely device-local — it's a
/// motion/battery preference, not account state — so it persists via SharedPreferences
/// (same pattern as `RulesGateController`) and applies immediately, no Save button.
/// The OS reduce-motion signal (`MediaQuery.disableAnimations`) is honored separately
/// at the widget layer; either one being "off" freezes animated posts on frame 0.
class AnimationAutoplayController extends StateNotifier<bool> {
  AnimationAutoplayController() : super(true) {
    _restore();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool(kAnimationAutoplayPrefKey);
      if (v != null && mounted) state = v;
    } catch (_) {
      // Best-effort: default stays ON.
    }
  }

  Future<void> set(bool value) async {
    state = value; // apply live first; persistence is best-effort
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kAnimationAutoplayPrefKey, value);
    } catch (_) {}
  }
}

final animationAutoplayProvider = StateNotifierProvider<AnimationAutoplayController, bool>(
    (ref) => AnimationAutoplayController());
