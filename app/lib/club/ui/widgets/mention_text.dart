import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/mention_markup.dart';
import '../profile_page.dart';

/// Renders text that may carry `<@sqid>` mention markup, with each mention a
/// tappable `@handle` that opens that member's profile.
///
/// Design: `docs/mentions/README.md` §5.4 V1/V2. The two hosts are the comment
/// tile (`comments_section.dart`) and the description block
/// (`artwork_detail_page.dart`), so the style decision lives here, once.
///
/// Give it [markup] plus the server's [mentions] array. When [markup] is null —
/// a server that predates the feature, or an optimistic local comment — it
/// falls back to [plain] and renders one ordinary [Text], so nothing about the
/// old path changes.
///
/// The link color follows `markdown_bio.dart`: `colorScheme.primary`, weight
/// 600, no underline. Mentions read as links without shouting.
class MentionText extends StatefulWidget {
  /// The source with `<@sqid>` markup (`body_markup` / `description_markup`).
  final String? markup;

  /// The plain rendering (`body` / `description`), shown whenever [markup] is
  /// null or carries no mention.
  final String plain;

  /// The sqids in [markup], resolved to current handles by the server.
  final List<MentionRef> mentions;

  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  /// Cap on how many mentions are linked, matching what the server enforces on
  /// write. Pass the value from `GET /config` where it is at hand.
  final int maxMentions;

  /// Overrides the default tap action (open the profile). Handy in tests and
  /// wherever a host wants to intercept navigation.
  final void Function(MentionedSegment mention)? onTapMention;

  const MentionText({
    super.key,
    required this.markup,
    required this.plain,
    this.mentions = const [],
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.maxMentions = kMaxMentionsPerText,
    this.onTapMention,
  });

  @override
  State<MentionText> createState() => _MentionTextState();
}

class _MentionTextState extends State<MentionText> {
  /// One recognizer per linked mention, rebuilt whenever the text changes and
  /// disposed with the widget — a leaked `TapGestureRecognizer` keeps its
  /// closure (and this element) alive.
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  void _open(MentionedSegment m) {
    final override = widget.onTapMention;
    if (override != null) {
      override(m);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProfilePage(sqid: m.sqid)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final markup = widget.markup;

    // No markup to speak of: the ordinary path, unchanged. [plain] wins here —
    // it is the field every other client renders, so a server that ever sent
    // the two out of step would still show what everyone else shows.
    if (markup == null || !hasMentionMarkup(markup)) {
      _disposeRecognizers();
      return Text(
        widget.plain,
        style: widget.style,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
        textAlign: widget.textAlign,
      );
    }

    final segments = parseMentionMarkup(
      markup,
      handles: MentionRef.handlesOf(widget.mentions),
      maxMentions: widget.maxMentions,
    );

    // Recognizers are per-build: the previous set belongs to text that is gone.
    _disposeRecognizers();

    final base = widget.style;
    final linkStyle = (base ?? const TextStyle()).copyWith(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w600,
    );

    final spans = <InlineSpan>[];
    for (final s in segments) {
      switch (s) {
        case PlainSegment(:final text):
          spans.add(TextSpan(text: text));
        case MentionedSegment():
          final recognizer = TapGestureRecognizer()..onTap = () => _open(s);
          _recognizers.add(recognizer);
          // No `semanticsLabel`: it would replace the handle in
          // `toPlainText()`, which copy and text extraction rely on. The span
          // reads as its handle and is tappable, which is the behavior wanted.
          spans.add(TextSpan(
            text: s.display,
            style: linkStyle,
            recognizer: recognizer,
          ));
      }
    }

    return Text.rich(
      TextSpan(style: base, children: spans),
      maxLines: widget.maxLines,
      overflow: widget.overflow ?? TextOverflow.clip,
      textAlign: widget.textAlign,
    );
  }
}
