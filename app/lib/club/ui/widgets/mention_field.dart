import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/club_error.dart';
import '../../models/mention_candidate.dart';
import '../../models/mention_markup.dart';
import '../../state/api_providers.dart';
import 'common.dart';

/// The `@` token under the caret, as found in composer text.
///
/// Public for the unit tests: the token rules are the fiddly part, not the
/// overlay.
class MentionToken {
  /// Index of the `@`.
  final int start;

  /// Index just past the token (exclusive).
  final int end;

  /// The text between the `@` and [end] — may be empty right after typing `@`.
  final String query;

  const MentionToken({required this.start, required this.end, required this.query});

  @override
  String toString() => 'MentionToken($start..$end, "$query")';

  @override
  bool operator ==(Object other) =>
      other is MentionToken &&
      other.start == start &&
      other.end == end &&
      other.query == query;

  @override
  int get hashCode => Object.hash(start, end, query);
}

final RegExp _handleChar = RegExp(r'[\p{L}\p{Nd}\p{Mn}\p{Mc}_-]', unicode: true);

/// Finds the `@`-led token the caret sits in, or null.
///
/// The `@` must open a token — start of text, or after a character a handle
/// cannot contain — so an email address never triggers the overlay. The caret
/// must sit inside the token or at its end, which is what makes the list follow
/// backspacing. A token longer than 32 characters stops matching, since no
/// handle is that long.
MentionToken? findMentionToken(String text, int caret) {
  if (caret < 0 || caret > text.length) return null;

  var i = caret;
  // Walk back over handle characters to the `@`.
  while (i > 0 && _handleChar.hasMatch(text[i - 1])) {
    i--;
    if (caret - i > 32) return null;
  }
  if (i == 0 || text[i - 1] != '@') return null;

  final at = i - 1;
  if (at > 0 && _handleChar.hasMatch(text[at - 1])) return null; // a@b, not a token

  // The token runs to the end of the handle run, which may extend past the caret.
  var end = caret;
  while (end < text.length && _handleChar.hasMatch(text[end])) {
    end++;
  }
  return MentionToken(start: at, end: end, query: text.substring(at + 1, end));
}

/// Owns a composer's text and the mentions picked in it.
///
/// The text field shows plain `@handle` throughout — the user never sees a sqid
/// (D2) — so the pairs live here and [serialized] turns them into `<@sqid>`
/// markup at send time. A pair whose `@handle` token the user has since edited
/// away is dropped by the serializer, so this list may safely hold stale picks.
class MentionComposer extends ChangeNotifier {
  final TextEditingController text;
  final bool _ownsText;
  final List<PickedMention> _picked = [];

  MentionComposer({TextEditingController? controller, String? initialText})
      : text = controller ?? TextEditingController(text: initialText ?? ''),
        _ownsText = controller == null;

  List<PickedMention> get picked => List.unmodifiable(_picked);

  /// The markup to send. Identical to the plain text when nothing was picked.
  String serialized({int maxMentions = kMaxMentionsPerText}) =>
      serializeMentions(text.text, _picked, maxMentions: maxMentions);

  /// How many mentions the current text would actually carry.
  int liveCount({int maxMentions = kMaxMentionsPerText}) =>
      hasMentionMarkup(serialized(maxMentions: maxMentions))
          ? RegExp(r'<@[A-Za-z0-9]{1,32}>')
              .allMatches(serialized(maxMentions: maxMentions))
              .length
          : 0;

  void add(PickedMention p) {
    _picked.add(p);
    notifyListeners();
  }

  /// Seeds an **edit**: fills the field with the plain rendering of [markup] and
  /// records its mentions as picks, so re-saving without touching the handles
  /// preserves them.
  ///
  /// Without this, an edit from the app would write back plain text and strip
  /// the mentions (D18) — which is exactly the regression the dual field lets
  /// us avoid on our own side.
  void seedFromMarkup(String? markup, List<MentionRef> mentions) {
    _picked.clear();
    if (markup == null || markup.isEmpty) {
      notifyListeners();
      return;
    }
    final handles = MentionRef.handlesOf(mentions);
    for (final segment in parseMentionMarkup(markup, handles: handles)) {
      if (segment is MentionedSegment) {
        _picked.add(PickedMention(handle: segment.handle, sqid: segment.sqid));
      }
    }
    text.text = plainFromMarkup(markup, handles: handles);
    notifyListeners();
  }

  @override
  void dispose() {
    if (_ownsText) text.dispose();
    super.dispose();
  }
}

/// Wraps a text field with mention autocomplete: when the caret sits in an
/// `@`-led token, an overlay of candidates appears, and picking one writes
/// `@handle ` into the field and records the pair on [composer].
///
/// The host builds its own field (decoration, maxLines, send button) and passes
/// it as [child]; this only adds the overlay. Hosts: the comment composer, the
/// publish page description, and the edit-details description.
///
/// [enabled] is the `/config` gate (`max_mentions_per_text` present). When
/// false this is a pass-through and no request is ever made.
class MentionField extends ConsumerStatefulWidget {
  final MentionComposer composer;
  final FocusNode focusNode;
  final Widget child;

  /// Integer post id for the contextual tiers. Null on the publish page, where
  /// the post does not exist yet.
  final int? postId;

  final bool enabled;
  final int maxMentions;

  const MentionField({
    super.key,
    required this.composer,
    required this.focusNode,
    required this.child,
    this.postId,
    this.enabled = true,
    this.maxMentions = kMaxMentionsPerText,
  });

  @override
  ConsumerState<MentionField> createState() => _MentionFieldState();
}

class _MentionFieldState extends ConsumerState<MentionField> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;
  Timer? _debounce;

  /// Cancels a late response: only the newest request may paint.
  int _requestSeq = 0;

  MentionToken? _token;
  List<MentionCandidate> _candidates = const [];
  bool _loading = false;
  bool _capped = false;

  TextEditingController get _text => widget.composer.text;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onTextChanged);
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.removeListener(_onTextChanged);
    widget.focusNode.removeListener(_onFocusChanged);
    _removeOverlay();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!widget.focusNode.hasFocus) _dismiss();
  }

  void _onTextChanged() {
    if (!widget.enabled) return;
    final sel = _text.selection;
    if (!sel.isValid || !sel.isCollapsed) {
      _dismiss();
      return;
    }

    final token = findMentionToken(_text.text, sel.baseOffset);
    if (token == null) {
      _dismiss();
      return;
    }

    // At the cap, stop offering and say why rather than letting the user pick
    // something the server would flatten.
    _capped = widget.composer.liveCount(maxMentions: widget.maxMentions) >=
        widget.maxMentions;

    _token = token;
    _debounce?.cancel();
    if (_capped) {
      _showOverlay();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () => _fetch(token));
    if (_entry == null) _showOverlay();
  }

  Future<void> _fetch(MentionToken token) async {
    final seq = ++_requestSeq;
    if (mounted) setState(() => _loading = true);
    _refreshOverlay();
    try {
      final items = await ref.read(mentionsApiProvider).candidates(
            q: token.query,
            postId: widget.postId,
            limit: 8,
          );
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _candidates = items;
        _loading = false;
      });
    } on ClubError catch (_) {
      if (!mounted || seq != _requestSeq) return;
      // A failed lookup is not worth a toast mid-typing: the list just stays
      // empty and the text remains perfectly valid without a mention.
      setState(() {
        _candidates = const [];
        _loading = false;
      });
    } catch (_) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _candidates = const [];
        _loading = false;
      });
    }
    _refreshOverlay();
  }

  void _pick(MentionCandidate c) {
    final token = _token;
    if (token == null) return;
    final text = _text.text;
    if (token.start > text.length || token.end > text.length) {
      _dismiss();
      return;
    }

    final replacement = '@${c.handle} ';
    final next = text.replaceRange(token.start, token.end, replacement);
    _text.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: token.start + replacement.length),
    );
    widget.composer.add(PickedMention(handle: c.handle, sqid: c.sqid));
    _dismiss();
  }

  void _dismiss() {
    _debounce?.cancel();
    _requestSeq++; // orphan any in-flight response
    _token = null;
    _candidates = const [];
    _loading = false;
    _capped = false;
    _removeOverlay();
  }

  void _removeOverlay() {
    _entry?.remove();
    _entry = null;
  }

  void _refreshOverlay() => _entry?.markNeedsBuild();

  void _showOverlay() {
    if (_entry != null) {
      _refreshOverlay();
      return;
    }
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    _entry = OverlayEntry(builder: (context) {
      final box = this.context.findRenderObject() as RenderBox?;
      final width = box?.size.width ?? 260.0;
      final height = box?.size.height ?? 0.0;

      // Prefer above the field: these composers sit just over the keyboard, so
      // below is usually off-screen.
      final origin = box?.localToGlobal(Offset.zero);
      final media = MediaQuery.of(context);
      final spaceBelow = origin == null
          ? 0.0
          : media.size.height -
              media.viewInsets.bottom -
              (origin.dy + height);
      final showBelow = spaceBelow > 220;

      return Positioned(
        width: width,
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: showBelow ? Alignment.bottomLeft : Alignment.topLeft,
          followerAnchor: showBelow ? Alignment.topLeft : Alignment.bottomLeft,
          offset: Offset(0, showBelow ? 4 : -4),
          child: _panel(context),
        ),
      );
    });
    overlay.insert(_entry!);
  }

  Widget _panel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget wrap(Widget child) => Material(
          elevation: 8,
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 216),
            child: child,
          ),
        );

    if (_capped) {
      return wrap(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          'That is ${widget.maxMentions} mentions, the most one post or comment '
          'can carry. Remove one to add another.',
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
      ));
    }

    if (_loading && _candidates.isEmpty) {
      return wrap(const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Looking…', style: TextStyle(fontSize: 12, color: Colors.white70)),
        ]),
      ));
    }

    if (_candidates.isEmpty) {
      return wrap(const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text('No one to mention by that name.',
            style: TextStyle(fontSize: 12, color: Colors.white54)),
      ));
    }

    return wrap(ListView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      itemCount: _candidates.length,
      itemBuilder: (context, i) {
        final c = _candidates[i];
        final label = c.reason.label;
        return InkWell(
          onTap: () => _pick(c),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(children: [
              HandleAvatar(url: c.avatarUrl, handle: c.handle, radius: 13),
              const SizedBox(width: 9),
              Expanded(
                child: Text('@${c.handle}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(label,
                    style: const TextStyle(fontSize: 11, color: Colors.white54)),
              ],
            ]),
          ),
        );
      },
    ));
  }

  @override
  Widget build(BuildContext context) =>
      CompositedTransformTarget(link: _link, child: widget.child);
}
