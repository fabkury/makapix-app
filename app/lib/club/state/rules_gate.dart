import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'publish_providers.dart';

/// Bump when the community rules change materially — installs that accepted an
/// older version are re-prompted on next launch.
/// v2 (server msg 0006): the gate now also references the formal Terms of Service,
/// so previously-accepted installs re-accept once to agree to the Terms.
const int kRulesVersion = 2;
const String kRulesPrefKey = 'club.rules_accepted_version';

enum RulesGate { show, passed }

/// The reactive first-run community-rules gate (ugc-safety A1/A12). It shows
/// **only** once the config has resolved with a `moderation` block AND this
/// install hasn't accepted the current rules version. It never blocks on the
/// config fetch: while config is loading, while the feature is off (pre-flip),
/// or offline (fallback config), it stays `passed` — so a pre-flip or offline
/// server behaves exactly as today. The gate re-arms every launch until
/// accepted.
class RulesGateController extends StateNotifier<RulesGate> {
  final Ref ref;
  int? _acceptedVersion;
  bool _restored = false;

  RulesGateController(this.ref) : super(RulesGate.passed) {
    _restore();
    // Recompute whenever the server config resolves (or refreshes).
    ref.listen(serverConfigProvider, (_, _) => _recompute(), fireImmediately: true);
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _acceptedVersion = prefs.getInt(kRulesPrefKey);
    } catch (_) {
      _acceptedVersion = null;
    }
    _restored = true;
    _recompute();
  }

  void _recompute() {
    // Never gate before we know whether the rules were accepted — avoids
    // flashing the gate at an accepted install while prefs load.
    if (!_restored) {
      state = RulesGate.passed;
      return;
    }
    final moderation = ref.read(serverConfigProvider).valueOrNull?.moderation;
    final accepted = (_acceptedVersion ?? 0) >= kRulesVersion;
    state = (moderation != null && !accepted) ? RulesGate.show : RulesGate.passed;
  }

  Future<void> accept() async {
    _acceptedVersion = kRulesVersion;
    state = RulesGate.passed;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(kRulesPrefKey, kRulesVersion);
    } catch (_) {
      // Best-effort; if the write fails the gate simply re-arms next launch.
    }
  }
}

final rulesGateProvider =
    StateNotifierProvider<RulesGateController, RulesGate>((ref) => RulesGateController(ref));
