part of 'editor_page.dart';
// ignore_for_file: invalid_use_of_protected_member
// (These extensions are part of _EditorPageState — a State subclass — so calling the
// @protected setState here is safe; the analyzer's check is a false positive for the
// part/extension split that keeps each editor file focused.)

// The Text tool (ADR 0039, ADR 0040; docs/text-tool/DESIGN.md; CONTEXT.md "Text vocabulary").
//
// The shell owns everything that makes a mask "text": the Fonts, the layout, the words, and
// the Text Draft's box. The engine only ever receives a 1-bit mask —
//   * `MaskDraft` / `MaskDraftMove` / `MaskDraftCancel` while the Draft is open: a display-only
//     preview the Journal drops (JournalRecorder), so typing costs the Journal nothing;
//   * one self-contained `MaskStamp` at commit: the single journal line a text leaves behind.
//
// 'Text' is a shell-only tool id (like 'Ruler'): the engine has no such ToolKind and is never
// sent `SelectTool(Text)`.

/// The open Text Draft: where its layout box sits on the canvas, its optional Wrap width, and
/// the last layout of the words.
class _TextDraft {
  _TextDraft(this.x, this.y, this.wrap, this.layout);

  /// The layout box's top-left in canvas pixels.
  int x, y;

  /// The Wrap width, or null when the box follows the text.
  int? wrap;
  TextLayout layout;

  /// Whether the engine currently holds a mask draft for this Draft (it holds none while the
  /// words have no ink).
  bool engineHas = false;
}

/// The words the Text tool remembers (user decision 2026-11-19): after a killed Draft and after
/// a commit alike, the next Text Draft starts with them. Deliberately top-level, not State:
/// a pillar switch remounts the editor, and the words must outlive that. Never persisted.
String _textWordsMemory = '';

const _kTextFontPref = 'editor.textFont_v1';
const _kTextAlignPref = 'editor.textAlign_v1';
const _kTextLetterPref = 'editor.textLetterSpacing_v1';
const _kTextLinePref = 'editor.textLineSpacing_v1';
const _kTextRecentsPref = 'editor.textRecentFonts_v1';
const int _kTextLetterMin = -4, _kTextLetterMax = 24;
const int _kTextLineMin = -48, _kTextLineMax = 48;

extension _EditorText on _EditorPageState {
  // ---- boot: fonts + remembered settings -------------------------------------------------

  /// Load the font manifest, the remembered Font and typography settings, and the Font's glyph
  /// data. Fail-soft: without fonts the tool shows no Font and opens no Draft.
  Future<void> _initTextTool() async {
    try {
      final lib = await PixelFontLibrary.shared();
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final saved = prefs.getString(_kTextFontPref);
      final lang = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en'; // l10n-ignore: language code
      final id = (saved != null && lib.entry(saved) != null) ? saved : lib.defaultFontId(lang);
      final font = await lib.load(id);
      if (!mounted) return;
      setState(() {
        _fontLib = lib;
        _textFontId = id;
        _textFont = font;
        _textAlign = TextAlignX.values[(prefs.getInt(_kTextAlignPref) ?? 0).clamp(0, 2)];
        _textLetterSp = (prefs.getInt(_kTextLetterPref) ?? 0).clamp(_kTextLetterMin, _kTextLetterMax);
        _textLineSp = (prefs.getInt(_kTextLinePref) ?? 0).clamp(_kTextLineMin, _kTextLineMax);
        _textRecents = [
          for (final r in prefs.getStringList(_kTextRecentsPref) ?? const <String>[])
            if (lib.entry(r) != null) r,
        ];
      });
    } catch (e) {
      debugPrint('Text tool: fonts unavailable: $e');
    }
  }

  Future<void> _persistTextSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = _textFontId;
      if (id != null) await prefs.setString(_kTextFontPref, id);
      await prefs.setInt(_kTextAlignPref, _textAlign.index);
      await prefs.setInt(_kTextLetterPref, _textLetterSp);
      await prefs.setInt(_kTextLinePref, _textLineSp);
      await prefs.setStringList(_kTextRecentsPref, _textRecents);
    } catch (_) {}
  }

  PixelFontEntry? get _textFontEntry {
    final id = _textFontId;
    return id == null ? null : _fontLib?.entry(id);
  }

  TextLayoutOptions _textOptions(int? wrap) => TextLayoutOptions(
      align: _textAlign, letterSpacing: _textLetterSp, lineSpacing: _textLineSp, wrapWidth: wrap);

  // ---- the Draft's lifecycle ----------------------------------------------------------------

  /// The controller's listener: keep the Draft in step with the field and remember the words.
  void _onTextChanged() {
    final words = _textCtrl.text;
    _textWordsMemory = words;
    // The listener also fires for caret and selection moves; only new words need a new layout.
    if (_text != null && words != _textLaidOut) _syncTextDraft();
  }

  /// Open a Text Draft whose layout box starts at canvas ([x], [y]), with the remembered words
  /// pre-selected so typing replaces them and committing again stamps them again.
  void _openTextDraft(int x, int y, int? wrap) {
    final font = _textFont;
    if (font == null) return;
    if (_playing) _pause();
    if (_textCtrl.text != _textWordsMemory) _textCtrl.text = _textWordsMemory;
    final d = _TextDraft(x, y, wrap, layoutText(_textCtrl.text, font, _textOptions(wrap)));
    if (wrap != null) _textLastWrap = wrap;
    setState(() => _text = d);
    _syncTextDraft();
    void selectAll() =>
        _textCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _textCtrl.text.length);
    selectAll();
    // The field mounts with this frame; focus it (the keyboard opens) once it exists, and
    // re-assert the selection a focus gain may have collapsed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _text == null) return;
      _textFocus.requestFocus();
      selectAll();
    });
  }

  /// Lay the words out again and hand the engine the new mask for its preview. Every call is a
  /// preview verb: nothing here reaches the Journal or re-arms the autosave.
  void _syncTextDraft() {
    final d = _text, font = _textFont;
    if (d == null || font == null) return;
    _textLaidOut = _textCtrl.text;
    d.layout = layoutText(_textLaidOut, font, _textOptions(d.wrap));
    final m = d.layout.mask;
    if (m == null) {
      if (d.engineHas) {
        _send('MaskDraftCancel()', activity: false);
        d.engineHas = false;
      }
    } else {
      _send('MaskDraft(${d.x + d.layout.maskX},${d.y + d.layout.maskY},${m.dslArgs})', activity: false);
      d.engineHas = true;
    }
    // A full rebuild: the commit controls' amber dot and the Wrap chip read the new layout.
    _redraw(refetchSelection: false);
  }

  bool get _activeLayerEditable {
    final layers = _layerList();
    final i = _activeLayerIndex();
    if (i < 0 || i >= layers.length) return true;
    final l = layers[i];
    return l['visible'] != false && l['locked'] != true;
  }

  /// Commit the Text Draft: one `MaskStamp` (one undo step, one journal line). Missing-glyph
  /// markers are dropped — the mask never held them. An empty text has nothing to stamp and
  /// simply closes. On a hidden or locked layer the Draft stays open and the editor says why.
  void _commitText() {
    final d = _text;
    if (d == null) return;
    final m = d.layout.mask;
    if (m == null) {
      _cancelText();
      return;
    }
    if (!_activeLayerEditable) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.l10n.textLayerLocked)));
      return;
    }
    final stamp = 'MaskStamp(${d.x + d.layout.maskX},${d.y + d.layout.maskY},${m.dslArgs})';
    _textFocus.unfocus();
    setState(() {
      _text = null;
      _textDrag = 0;
    });
    _rememberTextFont();
    _act(stamp); // the stamp drops the engine's draft itself
  }

  /// Discard the Text Draft. The words stay in the tool's memory (see [_textWordsMemory]).
  void _cancelText() {
    final d = _text;
    if (d == null) return;
    if (d.engineHas) _send('MaskDraftCancel()', activity: false);
    _textFocus.unfocus();
    setState(() {
      _text = null;
      _textDrag = 0;
      _textDownPos = _textDragNow = null;
    });
    _redraw();
  }

  void _rememberTextFont() {
    final id = _textFontId;
    if (id == null) return;
    _textRecents = [id, ..._textRecents.where((r) => r != id)].take(8).toList();
    _persistTextSettings();
  }

  // ---- options -------------------------------------------------------------------------------

  void _setTextAlign(TextAlignX a) {
    setState(() => _textAlign = a);
    _persistTextSettings();
    _syncTextDraft();
  }

  void _setTextLetterSpacing(int v) {
    setState(() => _textLetterSp = v.clamp(_kTextLetterMin, _kTextLetterMax));
    _persistTextSettings();
    _syncTextDraft();
  }

  void _setTextLineSpacing(int v) {
    setState(() => _textLineSp = v.clamp(_kTextLineMin, _kTextLineMax));
    _persistTextSettings();
    _syncTextDraft();
  }

  /// The Wrap chip: remove the Draft's Wrap width, or restore the last one (the box's current
  /// width when there never was one).
  void _toggleTextWrap() {
    final d = _text;
    if (d == null) return;
    setState(() {
      if (d.wrap != null) {
        _textLastWrap = d.wrap;
        d.wrap = null;
      } else {
        final w = _textLastWrap ?? d.layout.boxWidth;
        d.wrap = w < 1 ? 1 : w;
      }
    });
    _syncTextDraft();
  }

  Future<void> _openFontPicker() async {
    final lib = _fontLib;
    if (lib == null) return;
    if (_playing) _pause();
    final lang = switch (Localizations.maybeLocaleOf(context)?.languageCode) {
      'ja' => 'ja',
      'zh' => 'zh-Hans', // l10n-ignore: language tag
      'ko' => 'ko',
      _ => null,
    };
    final picked = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => FontPickerPage(
        library: lib,
        currentId: _textFontId,
        text: _textCtrl.text,
        recents: _textRecents,
        preferredLang: lang,
      ),
    ));
    if (picked == null || !mounted) return;
    final font = await lib.load(picked);
    if (font == null || !mounted) return;
    setState(() {
      _textFontId = picked;
      _textFont = font;
    });
    _persistTextSettings();
    _syncTextDraft();
    // Back from the page the field has lost its focus; give it back to an open Draft.
    if (_text != null) _textFocus.requestFocus();
  }

  // ---- geometry ------------------------------------------------------------------------------

  /// The Draft's layout box in canvas pixels. An empty or very short text still shows a box
  /// wide enough to see and to grab.
  Rect _textBoxRect(_TextDraft d) {
    final font = _textFont;
    final minW = font == null ? 4 : font.nativePx * 2;
    final w = d.wrap ?? (d.layout.boxWidth < minW ? minW : d.layout.boxWidth);
    return Rect.fromLTWH(d.x.toDouble(), d.y.toDouble(), w.toDouble(), d.layout.boxHeight.toDouble());
  }

  /// The Wrap-width handle rides the middle of the first line (canvas pixels below the box top).
  double get _textHandleDy {
    final font = _textFont;
    return font == null ? 4 : (font.ascent + font.descent) / 2;
  }

  List<Rect> _textMarkerRects(_TextDraft d) => [
        for (final m in d.layout.missing)
          Rect.fromLTWH((d.x + m.x).toDouble(), (d.y + m.y).toDouble(), m.w.toDouble(), m.h.toDouble()),
      ];

  /// The overlay layers for the canvas stack: the open Draft's box, handle, and markers, or the
  /// rectangle a drag is sweeping out to start one.
  List<Widget> _textOverlays(double vScale, Offset vOff) {
    final d = _text;
    return [
      if (d != null)
        CustomPaint(
          painter: TextDraftPainter(
            box: _textBoxRect(d),
            markers: _textMarkerRects(d),
            wrapped: d.wrap != null,
            handleDy: _textHandleDy,
            scale: vScale,
            off: vOff,
          ),
          size: Size.infinite,
        ),
      if (d == null && _textDrag == 1 && _textMoved && _textDownPos != null && _textDragNow != null)
        CustomPaint(painter: TextBoxDragPainter(_textDownPos!, _textDragNow!), size: Size.infinite),
    ];
  }

  // ---- canvas gestures (routed from _beginDraw / _continueDraw / _endDraw / _cancelDraw) -----
  // No Draft: a tap starts one at that point, a drag starts one with a Wrap width.
  // Draft open: a drag moves it (geared by Slow, ADR 0020), a drag on the handle sets the
  // Wrap width, and a tap does nothing (user decision 2026-11-19).

  void _beginText(Offset pos, Size box) {
    _textDownPos = pos;
    _textDragNow = pos;
    _textMoved = false;
    final d = _text;
    if (d == null) {
      _textDrag = 1;
      return;
    }
    final (scale, off) = _view(box);
    final handle = TextDraftPainter.handleCenter(_textBoxRect(d), _textHandleDy, scale, off);
    if ((pos - handle).distance <= TextDraftPainter.handleSlop) {
      _textDrag = 3;
      return;
    }
    _textDrag = 2;
    _beginTotalDrag(pos, box);
  }

  void _continueText(Offset pos, Size box) {
    final d = _text;
    switch (_textDrag) {
      case 1:
        _textDragNow = pos;
        if (!_textMoved && (pos - _textDownPos!).distance > 10) _textMoved = true;
        if (_textMoved) _overlayVN.value++;
      case 2:
        if (d == null) return;
        final (dx, dy) = _totalDragDelta(pos, box);
        if (dx == 0 && dy == 0) return;
        d.x += dx;
        d.y += dy;
        if (d.engineHas) _send('MaskDraftMove($dx,$dy)', activity: false);
        _redraw(full: false, refetchSelection: false);
      case 3:
        if (d == null) return;
        final w = (_toCanvasRaw(pos, box).dx - d.x).round();
        final wrap = w < 1 ? 1 : (w > kMaskMaxSide ? kMaskMaxSide : w);
        if (wrap == d.wrap) return;
        d.wrap = wrap;
        _textLastWrap = wrap;
        _syncTextDraft();
    }
  }

  void _endText(Size? box) {
    final mode = _textDrag;
    final down = _textDownPos, now = _textDragNow;
    _textDrag = 0;
    _textDownPos = _textDragNow = null;
    if (mode != 1 || down == null || now == null || box == null) {
      if (mode == 3) setState(() {}); // the Wrap chip follows the handle
      return;
    }
    final font = _textFont;
    if (font == null) return;
    if (!_textMoved) {
      // A tap: the text starts here. The point is the left edge of the first line, level with
      // the middle of its capitals, so the words appear beside the finger and not under it.
      final p = _toCanvas(down, box);
      _openTextDraft(p.dx.toInt(), p.dy.toInt() - (font.ascent - font.nativePx ~/ 2), null);
      return;
    }
    final a = _toCanvasRaw(down, box), b = _toCanvasRaw(now, box);
    final left = (a.dx < b.dx ? a.dx : b.dx).round(), top = (a.dy < b.dy ? a.dy : b.dy).round();
    final w = (a.dx - b.dx).abs().round();
    _openTextDraft(left, top, w < 1 ? 1 : w);
  }

  /// A second finger took over (pan/zoom): keep an open Draft where it is; forget a box that
  /// was only being swept out.
  void _cancelTextGesture() {
    _textDrag = 0;
    _textDownPos = _textDragNow = null;
    _textMoved = false;
    _overlayVN.value++;
  }

  // ---- row-1 options ---------------------------------------------------------------------------

  void _buildTextOptions(List<Widget> children) {
    final l10n = context.l10n;
    final entry = _textFontEntry;
    children.add(Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: l10n.optTextFont,
        child: ElevatedButton.icon(
          key: const ValueKey('text-font-button'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(0, 30),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            backgroundColor: const Color(0xFF2E3237),
          ),
          onPressed: _fontLib == null ? null : _openFontPicker,
          icon: const Icon(Icons.font_download_outlined, size: 15),
          // The Font's name is a proper noun, shown as it is in every language.
          label: Text(entry == null ? l10n.optTextFont : '${entry.name} · ${entry.px} px', // l10n-ignore: unit
              style: const TextStyle(fontSize: 11)),
        ),
      ),
    ));
    children.add(_iconToggle(
      const [Icons.format_align_left, Icons.format_align_center, Icons.format_align_right],
      [l10n.optTextAlignLeft, l10n.optTextAlignCenter, l10n.optTextAlignRight],
      _textAlign.index,
      (i) => _setTextAlign(TextAlignX.values[i]),
    ));
    _textStepper(children, l10n.optTextLetter, _textLetterSp, _kTextLetterMin, _kTextLetterMax, _setTextLetterSpacing,
        keyPrefix: 'text-letter');
    _textStepper(children, l10n.optTextLine, _textLineSp, _kTextLineMin, _kTextLineMax, _setTextLineSpacing,
        keyPrefix: 'text-line');
    final d = _text;
    children.add(Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: FilterChip(
        key: const ValueKey('text-wrap-chip'),
        selected: d?.wrap != null,
        label: Text(l10n.optTextWrap),
        tooltip: l10n.optTextWrapTip,
        selectedColor: const Color(0xFF30A050),
        onSelected: d == null ? null : (_) => _toggleTextWrap(),
      ),
    ));
    children.add(_slowChip()); // gears the Draft drag (ADR 0020)
  }

  // A labeled − value + stepper in whole pixels (the Outline width's look).
  void _textStepper(List<Widget> children, String name, int value, int min, int max, ValueChanged<int> onChanged,
      {required String keyPrefix}) {
    Widget step(String s, VoidCallback? onTap, String key) => SizedBox(
          width: 30,
          child: TextButton(
            key: ValueKey(key),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(30, 30)),
            onPressed: onTap,
            child: Text(s, style: const TextStyle(fontSize: 14)),
          ),
        );
    children.add(Padding(
        padding: const EdgeInsets.only(left: 8, right: 2),
        child: Text(name, style: const TextStyle(fontSize: 11, color: Colors.white60))));
    children.add(step('−', value > min ? () => onChanged(value - 1) : null, '$keyPrefix-minus')); // l10n-ignore: sign
    children.add(SizedBox(
      width: 30,
      child: Text('$value', // l10n-ignore: a number
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ));
    children.add(step('+', value < max ? () => onChanged(value + 1) : null, '$keyPrefix-plus')); // l10n-ignore: sign
  }

  // ---- the docked text field -------------------------------------------------------------------

  /// The row a Text Draft types into: a real text field (the system owns the caret, selection,
  /// paste, and IME composition), a clear button, and the commit check. Shown only while a
  /// Draft is open. Enter is a new line on every platform; with a hardware keyboard
  /// Ctrl/Cmd+Enter commits and Esc cancels.
  Widget _buildTextBar() {
    final l10n = context.l10n;
    final d = _text;
    final missing = d != null && d.layout.missing.isNotEmpty;
    return Container(
      key: const ValueKey('editor-text-bar'),
      color: const Color(0xFF181B1F),
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter, control: true): _commitText,
              const SingleActivator(LogicalKeyboardKey.enter, meta: true): _commitText,
              const SingleActivator(LogicalKeyboardKey.numpadEnter, control: true): _commitText,
              const SingleActivator(LogicalKeyboardKey.escape): _cancelText,
            },
            child: TextField(
              key: const ValueKey('editor-text-field'),
              controller: _textCtrl,
              focusNode: _textFocus,
              minLines: 1,
              maxLines: 3,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              autocorrect: false,
              maxLength: kTextMaxChars,
              // The canvas is the Draft's own surface: a touch there moves the text and must not
              // take the keyboard away from it.
              onTapOutside: (_) {},
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                hintText: l10n.textFieldHint,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                filled: true,
                fillColor: const Color(0xFF24282D),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('editor-text-clear'),
          tooltip: l10n.textClear,
          iconSize: 20,
          visualDensity: VisualDensity.compact,
          onPressed: _textCtrl.text.isEmpty ? null : () => _textCtrl.clear(),
          icon: const Icon(Icons.backspace_outlined),
        ),
        Stack(clipBehavior: Clip.none, children: [
          IconButton(
            key: const ValueKey('editor-text-commit'),
            tooltip: missing ? l10n.textCommitMissing : l10n.draftCommit,
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(backgroundColor: const Color(0xFF30A050), foregroundColor: Colors.white),
            onPressed: _commitText,
            icon: const Icon(Icons.check),
          ),
          if (missing) const Positioned(right: 2, top: 2, child: _AmberDot()),
        ]),
      ]),
    );
  }
}

/// The mark on a commit control while the Text Draft holds Missing-glyph markers: committing
/// is allowed, and leaves those characters blank.
class _AmberDot extends StatelessWidget {
  const _AmberDot();
  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('text-missing-dot'),
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: const Color(0xFFFFB300),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black, width: 1.5),
        ),
      );
}
