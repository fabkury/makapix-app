import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/account_providers.dart';
import '../../state/auth_controller.dart';
import '../../state/onboarding_controller.dart';

/// The welcome wizard shown once after account creation (gated by
/// `me.needsWelcome` in [ClubHomePage]). Steps: set your password (only when a
/// temporary password is known, i.e. the email+temp-password signup) · pick a
/// handle (live availability) · optional avatar + bio · finish.
class OnboardingWizard extends ConsumerStatefulWidget {
  const OnboardingWizard({super.key});
  @override
  ConsumerState<OnboardingWizard> createState() => _OnboardingWizardState();
}

enum _Step { password, handle, profile }

class _OnboardingWizardState extends ConsumerState<OnboardingWizard> {
  int _index = 0;

  final _newPassword = TextEditingController();
  final _confirm = TextEditingController();
  final _handle = TextEditingController();
  final _bio = TextEditingController();
  bool _obscure = true;
  Timer? _handleDebounce;
  List<int>? _avatarBytes;
  String? _avatarName;
  bool _handleInit = false;

  @override
  void dispose() {
    _handleDebounce?.cancel();
    _newPassword.dispose();
    _confirm.dispose();
    _handle.dispose();
    _bio.dispose();
    super.dispose();
  }

  List<_Step> _steps(bool hasPasswordStep) =>
      [if (hasPasswordStep) _Step.password, _Step.handle, _Step.profile];

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _pickAvatar() async {
    final res = await FilePicker.pickFiles(type: FileType.image, withData: true);
    final file = res?.files.firstOrNull;
    if (file?.bytes != null) {
      setState(() {
        _avatarBytes = file!.bytes!;
        _avatarName = file.name;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authControllerProvider).me;
    final tempPw = ref.watch(pendingWelcomePasswordProvider);
    final st = ref.watch(onboardingControllerProvider);
    final ctrl = ref.read(onboardingControllerProvider.notifier);
    final hasPasswordStep = tempPw != null && tempPw.isNotEmpty;
    final steps = _steps(hasPasswordStep);
    final i = _index.clamp(0, steps.length - 1);
    final step = steps[i];
    final isLast = i == steps.length - 1;

    // Seed the handle field once from the current (auto-generated) handle.
    if (!_handleInit && me != null) {
      _handle.text = me.user.handle;
      _handleInit = true;
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Welcome to Makapix Club'),
        actions: [
          TextButton(
            onPressed: st.busy
                ? null
                : () => ref.read(welcomeDismissedProvider.notifier).state = true,
            child: const Text('Skip for now'),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Progress(index: i, count: steps.length),
                const SizedBox(height: 20),
                ...switch (step) {
                  _Step.password => _passwordStep(),
                  _Step.handle => _handleStep(me?.user.handle ?? '', st, ctrl),
                  _Step.profile => _profileStep(),
                },
                const SizedBox(height: 24),
                Row(children: [
                  if (!_isPasswordStep(step))
                    TextButton(
                      onPressed: st.busy ? null : () => _advance(isLast, ctrl),
                      child: const Text('Skip'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: st.busy ? null : () => _submit(step, isLast, ctrl, me, tempPw),
                    child: st.busy
                        ? const SizedBox(
                            height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(isLast ? 'Finish' : 'Continue'),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isPasswordStep(_Step s) => s == _Step.password;

  // Skip the current step (no save) and advance / finish.
  Future<void> _advance(bool isLast, OnboardingController ctrl) async {
    if (isLast) {
      await _finish(ctrl);
    } else {
      setState(() => _index = _index + 1);
    }
  }

  // Run the current step's save, then advance / finish. On error, stay put.
  Future<void> _submit(
      _Step step, bool isLast, OnboardingController ctrl, dynamic me, String? tempPw) async {
    String? error;
    switch (step) {
      case _Step.password:
        if (_newPassword.text != _confirm.text) {
          _toast('Passwords don\'t match.');
          return;
        }
        error = await ctrl.setPassword(tempPw ?? '', _newPassword.text);
      case _Step.handle:
        final handle = _handle.text.trim();
        if (me != null && handle.toLowerCase() != me.user.handle.toLowerCase()) {
          error = await ctrl.saveHandle(handle);
        }
      case _Step.profile:
        final userKey = me?.user.userKey ?? '';
        final bio = _bio.text.trim();
        if (userKey.isNotEmpty && (bio.isNotEmpty || _avatarBytes != null)) {
          error = await ctrl.saveProfile(
            userKey,
            bio: bio.isNotEmpty ? bio : null,
            avatarBytes: _avatarBytes,
            avatarFilename: _avatarName,
          );
        }
    }
    if (error != null) {
      _toast(error);
      return;
    }
    if (isLast) {
      await _finish(ctrl);
    } else {
      setState(() => _index = _index + 1);
    }
  }

  Future<void> _finish(OnboardingController ctrl) async {
    final error = await ctrl.finish();
    if (error != null && mounted) _toast(error);
    // On success, /auth/me reloads with needs_welcome=false and the gate drops
    // this wizard automatically — no explicit navigation needed.
  }

  // ---- steps ----

  List<Widget> _passwordStep() => [
        _title('Set your password',
            'You signed in with a temporary password. Choose your own to finish.'),
        TextField(
          controller: _newPassword,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: 'New password',
            border: const OutlineInputBorder(),
            helperText: 'At least 8 characters, with a letter and a number.',
            helperMaxLines: 2,
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirm,
          obscureText: _obscure,
          decoration: const InputDecoration(
              labelText: 'Confirm password', border: OutlineInputBorder()),
        ),
      ];

  List<Widget> _handleStep(String currentHandle, OnboardingState st, OnboardingController ctrl) {
    final (color, text) = switch (st.handleCheck) {
      HandleCheck.checking => (Colors.white54, st.handleMessage),
      HandleCheck.available => (Colors.greenAccent, st.handleMessage),
      HandleCheck.taken => (Colors.redAccent, st.handleMessage),
      HandleCheck.invalid => (Colors.orangeAccent, st.handleMessage),
      HandleCheck.idle => (Colors.white54, ''),
    };
    return [
      _title('Pick a handle',
          'This is your @name across Makapix Club. You can change it later in Settings.'),
      TextField(
        controller: _handle,
        autocorrect: false,
        decoration: const InputDecoration(
            labelText: 'Handle', prefixText: '@', border: OutlineInputBorder()),
        onChanged: (v) {
          _handleDebounce?.cancel();
          _handleDebounce = Timer(const Duration(milliseconds: 400),
              () => ctrl.checkHandle(v, currentHandle: currentHandle));
        },
      ),
      if (text.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text(text, style: TextStyle(color: color, fontSize: 12)),
        ),
    ];
  }

  List<Widget> _profileStep() => [
        _title('Add a touch (optional)',
            'A photo and a short bio help people recognise you. You can skip and do this later.'),
        Center(
          child: GestureDetector(
            onTap: _pickAvatar,
            child: CircleAvatar(
              radius: 44,
              backgroundColor: const Color(0xFF2A2D31),
              backgroundImage: _avatarBytes != null ? MemoryImage(_bytesToUint8(_avatarBytes!)) : null,
              child: _avatarBytes == null
                  ? const Icon(Icons.add_a_photo_outlined, color: Colors.white54)
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _bio,
          maxLines: 3,
          maxLength: 280,
          decoration: const InputDecoration(
              labelText: 'Bio', border: OutlineInputBorder(), alignLabelWithHint: true),
        ),
      ];

  Widget _title(String t, String s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(s, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 16),
        ],
      );
}

// file_picker returns `Uint8List` already; this keeps the type explicit for
// MemoryImage without importing dart:typed_data widely.
Uint8List _bytesToUint8(List<int> b) => b is Uint8List ? b : Uint8List.fromList(b);

class _Progress extends StatelessWidget {
  final int index;
  final int count;
  const _Progress({required this.index, required this.count});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: i <= index ? cs.primary : Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (i < count - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}
