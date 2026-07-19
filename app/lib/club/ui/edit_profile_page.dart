import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../edit/profile_edit.dart';
import '../models/club_error.dart';
import '../models/user_profile.dart';
import '../state/auth_controller.dart';
import 'widgets/common.dart';

/// Edit the signed-in user's own profile (`SPEC-CLUB.md` §14): avatar
/// (upload/remove, applied immediately) plus tagline and bio (saved together
/// via one PATCH of only the changed fields). Handle change stays in
/// Settings → Account; website is not editable in the app yet.
class EditProfilePage extends ConsumerStatefulWidget {
  final UserProfile profile;
  const EditProfilePage({super.key, required this.profile});

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  late final TextEditingController _tagline;
  late final TextEditingController _bio;

  // Last-saved values (the dirty baseline); null and '' are equivalent.
  late String? _baseTagline;
  late String? _baseBio;

  String? _avatarUrl;
  bool _avatarBusy = false;
  bool _saving = false;

  static const _allowedExtensions = ['png', 'jpg', 'jpeg', 'gif', 'webp'];
  static const _maxAvatarBytes = 5 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    _tagline = TextEditingController(text: widget.profile.tagline ?? '');
    _bio = TextEditingController(text: widget.profile.bio ?? '');
    _baseTagline = widget.profile.tagline;
    _baseBio = widget.profile.bio;
    _avatarUrl = widget.profile.avatarUrl;
  }

  @override
  void dispose() {
    _tagline.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Map<String, String> get _patch => buildProfilePatchFrom(
      currentTagline: _baseTagline, currentBio: _baseBio, tagline: _tagline.text, bio: _bio.text);

  bool get _dirty => _patch.isNotEmpty;

  Future<void> _pickAvatar() async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
      withData: true,
    );
    final file = res?.files.firstOrNull;
    if (file == null || file.bytes == null) return;
    if (file.bytes!.length > _maxAvatarBytes) {
      _toast('That image is too large (max 5 MB).');
      return;
    }
    setState(() => _avatarBusy = true);
    try {
      final url = await ref
          .read(clubApiClientProvider)
          .uploadAvatar(widget.profile.userKey, file.bytes!, file.name);
      await ref.read(authControllerProvider.notifier).reloadMe();
      if (!mounted) return;
      setState(() {
        _avatarUrl = url ?? ref.read(authControllerProvider).me?.user.avatarUrl;
        _avatarBusy = false;
      });
      _toast('Avatar updated.');
    } on ClubError catch (e) {
      if (!mounted) return;
      setState(() => _avatarBusy = false);
      _toast(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _avatarBusy = false);
      _toast('Could not upload the avatar.');
    }
  }

  Future<void> _removeAvatar() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove photo?'),
        content: const Text('Your profile will show your initial instead. This applies immediately.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _avatarBusy = true);
    try {
      await ref.read(clubApiClientProvider).deleteAvatar(widget.profile.userKey);
      await ref.read(authControllerProvider.notifier).reloadMe();
      if (!mounted) return;
      setState(() {
        _avatarUrl = null;
        _avatarBusy = false;
      });
      _toast('Avatar removed.');
    } on ClubError catch (e) {
      if (!mounted) return;
      setState(() => _avatarBusy = false);
      _toast(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _avatarBusy = false);
      _toast('Could not remove the avatar.');
    }
  }

  Future<void> _save() async {
    final err = validateCodePointLength(_tagline.text, kTaglineMaxCodePoints, 'Tagline') ??
        validateCodePointLength(_bio.text, kBioMaxCodePoints, 'Bio');
    if (err != null) return _toast(err);
    final patch = _patch;
    if (patch.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(clubApiClientProvider).updateProfile(widget.profile.userKey,
          tagline: patch['tagline'], bio: patch['bio']);
      if (!mounted) return;
      setState(() {
        _baseTagline = _tagline.text.trim();
        _baseBio = _bio.text.trim();
        _saving = false;
      });
      _toast('Saved.');
    } on ClubError catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not save your profile.');
    }
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your tagline/bio edits have not been saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _avatarBusy;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Edit profile')),
        body: CenteredContent(
            child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Stack(alignment: Alignment.center, children: [
                HandleAvatar(url: _avatarUrl, handle: widget.profile.handle, radius: 48),
                if (_avatarBusy) const CircularProgressIndicator(),
              ]),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              TextButton.icon(
                onPressed: busy ? null : _pickAvatar,
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Change photo'),
              ),
              if (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                TextButton.icon(
                  onPressed: busy ? null : _removeAvatar,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Remove photo'),
                ),
            ]),
            const SizedBox(height: 16),
            TextField(
              controller: _tagline,
              maxLength: kTaglineMaxCodePoints,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Tagline',
                hintText: 'A short one-liner shown under your handle',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bio,
              maxLines: 6,
              maxLength: kBioMaxCodePoints,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Bio',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: (_dirty && !busy) ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('Save'),
            ),
          ],
        )),
      ),
    );
  }
}
