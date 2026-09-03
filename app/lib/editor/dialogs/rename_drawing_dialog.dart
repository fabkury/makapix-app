import 'package:flutter/material.dart';

/// The longest drawing title the shell accepts, enforced at input time here and in the
/// New-document dialog's optional title field (2026-09-03). Titles are trimmed on save.
const int kDrawingTitleMaxLength = 128;

/// The one rename-drawing dialog, shared by the gallery grid and the editor's ☰ header.
/// Returns the trimmed new title, or null on cancel; callers treat null / empty / unchanged
/// as a no-op.
Future<String?> showRenameDrawingDialog(BuildContext context, {required String initialTitle}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _RenameDrawingDialog(initialTitle: initialTitle),
  );
}

class _RenameDrawingDialog extends StatefulWidget {
  final String initialTitle;

  const _RenameDrawingDialog({required this.initialTitle});

  @override
  State<_RenameDrawingDialog> createState() => _RenameDrawingDialogState();
}

class _RenameDrawingDialogState extends State<_RenameDrawingDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename drawing'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLength: kDrawingTitleMaxLength,
        decoration: const InputDecoration(hintText: 'Title', counterText: ''),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _ctrl.text.trim()), child: const Text('Save')),
      ],
    );
  }
}
