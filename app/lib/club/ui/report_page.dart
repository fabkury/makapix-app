import 'package:flutter/material.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/club_error.dart';
import '../models/report.dart';
import '../models/safety_copy.dart';
import '../models/server_config.dart';
import '../state/api_providers.dart';
import '../state/auth_controller.dart';
import '../state/publish_providers.dart';
import '../state/safety_providers.dart';
import 'widgets/external_links.dart';

/// Full-screen report flow shared by all three entry points (post kebab,
/// comment row, profile menu). Works signed-out — no auth gate anywhere. The
/// caller only reaches here when the `moderation` config key is present, but we
/// tolerate its absence defensively.
class ReportPage extends ConsumerStatefulWidget {
  final ReportTarget target;
  const ReportPage({super.key, required this.target});

  @override
  ConsumerState<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends ConsumerState<ReportPage> {
  final _notes = TextEditingController();
  String? _reason;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  ReportTarget get _target => widget.target;

  Future<void> _submit(ModerationRules rules) async {
    if (_reason == null || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final notes = _notes.text.trim();
    try {
      await ref.read(safetyApiProvider).report(
            _target,
            reasonCode: _reason!,
            notes: notes.isEmpty ? null : notes,
          );
      if (!mounted) return;
      await _showSent(rules);
    } on ClubError catch (e) {
      if (!mounted) return;
      if (e.isRateLimited) {
        setState(() {
          _submitting = false;
          _error = reportRateLimitMessage(rules.contactEmail);
        });
      } else if (e.status == 404 || e.code == 'not_found') {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('This content is no longer available.')));
        Navigator.of(context).pop();
      } else if (e.code == 'validation_error' || e.status == 422) {
        setState(() {
          _submitting = false;
          _error = e.message;
        });
      } else {
        setState(() {
          _submitting = false;
          _error = 'Could not send the report — check your connection and try again.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Could not send the report — check your connection and try again.';
      });
    }
  }

  // The offender we could offer to block after a successful report: signed in,
  // a known non-self identity (anonymous comments have none).
  String? get _blockableSqid {
    final mySub = ref.read(authControllerProvider).me?.user.sub;
    final sqid = _target.offenderSqid;
    if (sqid == null || sqid.isEmpty) return null;
    if (!ref.read(authControllerProvider).isSignedIn) return null;
    if (mySub != null && mySub == sqid) return null;
    return sqid;
  }

  Future<void> _showSent(ModerationRules rules) async {
    final blockSqid = _blockableSqid;
    final handle = _target.offenderHandle;
    await showDialog<void>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Report sent'),
        content: const Text('Thanks — a moderator will review it.'),
        actions: [
          if (blockSqid != null && handle != null)
            TextButton(
              onPressed: () async {
                Navigator.of(dctx).pop(); // close the dialog first
                await _blockAfterReport(blockSqid, handle, rules);
              },
              child: Text('Block @$handle'),
            ),
          TextButton(
            onPressed: () {
              Navigator.of(dctx).pop(); // dialog
              Navigator.of(context).pop(); // report page
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _blockAfterReport(String sqid, String handle, ModerationRules rules) async {
    try {
      await blockUser(ref, sqid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Blocked @$handle')));
    } on ClubError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(blockErrorMessage(e, maxBlocksPerUser: rules.maxBlocksPerUser))));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not update the block — try again.')));
    }
    // The report itself succeeded; leave the page regardless of the block result.
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final rules = ref.watch(serverConfigProvider).valueOrNull?.moderation;
    return Scaffold(
      appBar: AppBar(title: const Text('Report')),
      body: rules == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Reporting is not available right now.',
                    style: TextStyle(color: Colors.white60)),
              ),
            )
          : CenteredContent(child: _form(rules)),
    );
  }

  Widget _form(ModerationRules rules) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Reporting ${_target.label}',
            style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        const Text('Why are you reporting this?', style: TextStyle(color: Colors.white60)),
        const SizedBox(height: 8),
        RadioGroup<String>(
          groupValue: _reason,
          onChanged: (v) {
            if (_submitting) return;
            setState(() => _reason = v);
          },
          child: Column(
            children: [
              for (final r in rules.reportReasons)
                RadioListTile<String>(
                  value: r.code,
                  title: Text(r.label),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          minLines: 2,
          maxLines: 5,
          maxLength: 2000,
          enabled: !_submitting,
          decoration: const InputDecoration(
            labelText: 'Anything else we should know? (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: (_reason == null || _submitting) ? null : () => _submit(rules),
          child: _submitting
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Submit report'),
        ),
        const SizedBox(height: 20),
        const Divider(height: 1),
        const SizedBox(height: 12),
        // Published moderation contact + rules — reachable here even signed-out.
        if (rules.guidelinesUrl.isNotEmpty)
          TextButton.icon(
            onPressed: () => openExternalUrl(context, rules.guidelinesUrl),
            icon: const Icon(Icons.gavel_outlined, size: 18),
            label: const Text('See the community rules'),
          ),
        TextButton.icon(
          onPressed: () => openEmail(context, rules.contactEmail),
          icon: const Icon(Icons.mail_outline, size: 18),
          label: Text('Questions? Email ${rules.contactEmail}'),
        ),
      ],
    );
  }
}
