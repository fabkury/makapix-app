part of 'editor_page.dart';
// ignore_for_file: invalid_use_of_protected_member
// (These extensions are part of _EditorPageState — a State subclass — so calling the
// @protected setState here is safe; the analyzer's check is a false positive for the
// part/extension split that keeps each editor file focused and under ~400 lines.)

// Row-1 tool options (per-tool sliders/toggles) and the row-2 palette manager.
extension _EditorControls on _EditorPageState {
  Widget _buildToolOptions() {
    final children = <Widget>[];
    void label(String s) => children.add(Padding(
        padding: const EdgeInsets.only(left: 8, right: 4),
        child: Text(s, style: const TextStyle(fontSize: 11, color: Colors.white60))));

    // NOTE: no per-tool Commit/Cancel buttons here — a pending draft (shape/gradient figure,
    // selection-shape draft, floating paste, move draft, free-angle rotate) is resolved via the
    // floating commit-menu pill over the canvas's bottom-left corner (see _commitMenu).

    if (_precisionCapable) {
      // The Precision toggle: turns the active paint tool into its off-finger reticle mode.
      // Remembered per tool (see _precisionOn).
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: FilterChip(
          selected: _isPrecision,
          avatar: Icon(Icons.gps_fixed, size: 16, color: _isPrecision ? Colors.white : Colors.white60),
          label: Text(_isPrecision ? 'Precision ✔' : 'Precision'),
          selectedColor: const Color(0xFF30A050),
          onSelected: _setPrecision,
        ),
      ));
    }
    if (_isPrecision) {
      // off-finger reticle nudge pad (1px steps), shared by every precision tool
      children.add(IconButton(iconSize: 20, tooltip: 'Nudge left', onPressed: () => _nudgeCursor(-1, 0), icon: const Icon(Icons.chevron_left)));
      children.add(Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        InkWell(onTap: () => _nudgeCursor(0, -1), child: const Icon(Icons.keyboard_arrow_up, size: 18)),
        InkWell(onTap: () => _nudgeCursor(0, 1), child: const Icon(Icons.keyboard_arrow_down, size: 18)),
      ]));
      children.add(IconButton(iconSize: 20, tooltip: 'Nudge right', onPressed: () => _nudgeCursor(1, 0), icon: const Icon(Icons.chevron_right)));
      children.add(const SizedBox(width: 4));
      if (_tool == 'Eyedropper') {
        // PICK (one-time colour pick at the reticle, off-finger). The eyedropper has no continuous
        // "Hold" mode — picking is a single operation.
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 34), backgroundColor: const Color(0xFF4080C0)),
            onPressed: () { _send('EyedropCursor()'); _refreshState(); _redraw(); setState(() {}); },
            icon: const Icon(Icons.colorize, size: 16),
            label: const Text('Pick'),
          ),
        ));
      } else {
        if (_tool == 'Airbrush') {
          // SPRAY (one airbrush dab at the reticle, off-finger)
          children.add(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(minimumSize: const Size(0, 34), backgroundColor: const Color(0xFF4080C0)),
              onPressed: () { _send('AirbrushCursor()'); _refreshState(); _redraw(); setState(() {}); },
              icon: const Icon(Icons.blur_on, size: 16),
              label: const Text('Spray'),
            ),
          ));
        } else {
          // DRAW (single stamp at the reticle)
          children.add(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(minimumSize: const Size(0, 34), backgroundColor: const Color(0xFF4080C0)),
              onPressed: () { _send('PlotCursor()'); _refreshState(); _redraw(); setState(() {}); },
              icon: const Icon(Icons.brush, size: 16),
              label: const Text('Draw'),
            ),
          ));
        }
        // HOLD toggle (pen held down: continuous stroke/spray while dragging the reticle)
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: FilterChip(
            selected: _penDown,
            label: Text(_penDown ? 'Hold ✔' : 'Hold'),
            selectedColor: const Color(0xFF30A050),
            onSelected: (v) {
              setState(() => _penDown = v);
              _send(v ? 'CursorPenDown()' : 'CursorPenUp()');
              _refreshState();
              _redraw();
            },
          ),
        ));
      }
    }
    if (_tool == 'Move') {
      // Mode: move the layer/pixels (default) or ONLY the selection mask (the marquee, not the
      // pixels). In "layer/pixels", a selection moves the selected pixels and none moves the
      // layer/move-group. Edge mode: Protect (clamp on-canvas) / Wrap (re-enter the opposite edge) /
      // both off = Regular — applies to layer, pixel AND selection-mask moves (Protect/Wrap exclusive).
      final hasSel = _outlineEdges.isNotEmpty;
      children.add(_toggle(['Move layer/pixels', 'Move selection'], _moveSelectionMode ? 1 : 0, (i) {
        // Switching the move mode mid-draft discards the pending draft first.
        if (_hasMoveDraft) _cancelMoveDraft();
        setState(() => _moveSelectionMode = i == 1);
      }));
      label(_moveSelectionMode ? 'Move selection' : (hasSel ? 'Move pixels' : 'Move layer'));
      children.add(IconButton(iconSize: 20, tooltip: 'Nudge left', onPressed: () => _nudgeMove(-1, 0), icon: const Icon(Icons.chevron_left)));
      children.add(Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        InkWell(onTap: () => _nudgeMove(0, -1), child: const Icon(Icons.keyboard_arrow_up, size: 18)),
        InkWell(onTap: () => _nudgeMove(0, 1), child: const Icon(Icons.keyboard_arrow_down, size: 18)),
      ]));
      children.add(IconButton(iconSize: 20, tooltip: 'Nudge right', onPressed: () => _nudgeMove(1, 0), icon: const Icon(Icons.chevron_right)));
      children.add(const SizedBox(width: 6));
      if (_moveSelectionMode || !hasSel) {
        // Protect applies to layer moves and selection-mask moves (not pixel moves), so it's hidden
        // only when moving the selected pixels.
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: FilterChip(
            selected: _protectPixels,
            label: Text(_protectPixels ? 'Protect ✔' : 'Protect pixels'),
            selectedColor: const Color(0xFF30A050),
            onSelected: (v) {
              setState(() {
                _protectPixels = v;
                if (v) _wrap = false;
              });
              _send('SetProtectPixels($_protectPixels); SetWrap($_wrap)');
            },
          ),
        ));
      }
      // Wrap applies to both layer and pixel moves.
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: FilterChip(
          selected: _wrap,
          label: Text(_wrap ? 'Wrap ✔' : 'Wrap'),
          selectedColor: const Color(0xFF30A050),
          onSelected: (v) {
            setState(() {
              _wrap = v;
              if (v) _protectPixels = false;
            });
            _send('SetProtectPixels($_protectPixels); SetWrap($_wrap)');
          },
        ),
      ));
    }
    if (_tool == 'Ruler') {
      label('Ruler');
      children.add(_miniBtn('Clear', () {
        setState(() {
          _rulerA = null;
          _rulerB = null;
          _rulerDrag = 0;
        });
      }));
    }
    // Brush footprint SIZE: every tool whose mark is a stamp/spray of `brush_size` — i.e. the
    // pixel/paint tools, the airbrush spray radius, and dodge/burn. The figure tools (Line/Rect/
    // Ellipse) ignore brush_size (they use line_width + fill), so they're deliberately excluded.
    const sizeTools = {'Pencil', 'Brush', 'Airbrush', 'Eraser', 'Dodge', 'Burn'};
    // Stamp SHAPE (Round/Square): only tools that stamp a footprint of `brush_shape`. The airbrush
    // always sprays a disc (no shape), and figures don't stamp — both are excluded.
    const shapeTools = {'Pencil', 'Brush', 'Eraser', 'Dodge', 'Burn'};
    if (sizeTools.contains(_tool)) {
      _labeledSlider(children, 'Size', _brushSize.toDouble(), 1, 32, (v) {
        setState(() => _brushSize = v.round());
        _send('SetBrushSize($_brushSize)');
      });
    }
    if (shapeTools.contains(_tool)) {
      label('Shape');
      children.add(_toggle(['Round', 'Square'], _round ? 0 : 1, (i) {
        setState(() => _round = i == 0);
        _send('SetBrushShape(${_round ? 'Round' : 'Square'})');
      }));
    }
    if (_tool == 'Pencil') {
      // Pixel-perfect: drop the redundant "corner double" pixels as a 1px stroke turns, keeping the
      // line a clean 1px. Only meaningful at Size 1 (the engine no-ops it above), so grey it out
      // there while keeping it visible/discoverable.
      final perfectEnabled = _brushSize == 1;
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: FilterChip(
          selected: _perfect,
          label: Text(_perfect ? 'Perfect ✔' : 'Perfect'),
          selectedColor: const Color(0xFF30A050),
          onSelected: perfectEnabled
              ? (v) {
                  setState(() => _perfect = v);
                  _send('SetPixelPerfect($_perfect)');
                }
              : null,
        ),
      ));
    }
    if (_tool == 'Airbrush' || _tool == 'Dodge' || _tool == 'Burn') {
      _labeledSlider(children, 'Intensity', _intensity.toDouble(), 1, 255, (v) {
        setState(() => _intensity = v.round());
        _send('SetIntensity($_intensity)');
      });
    }
    // Stamp spacing (% of brush size) for the stamp-trail tools. Tap the label to type a value.
    if (_tool == 'Brush' || _tool == 'Airbrush' || _tool == 'Dodge' || _tool == 'Burn') {
      _labeledSlider(children, 'Spacing', _spacing.toDouble(), 1, 1000, (v) {
        setState(() => _spacing = v.round());
        _send('SetSpacing($_spacing)');
      });
    }
    if (_tool == 'Bucket' || _tool == 'SelectByColor') {
      _labeledSlider(children, 'Threshold', _threshold.toDouble(), 0, 255, (v) {
        setState(() => _threshold = v.round());
        _send('SetThreshold($_threshold)');
      });
      children.add(_toggle(['Contiguous', 'Global'], _contiguous ? 0 : 1, (i) {
        setState(() => _contiguous = i == 0);
        _send('SetContiguous($_contiguous)');
      }));
      if (_tool == 'Bucket') {
        // Decide which pixels to fill from the whole composited image (all visible layers), while
        // still writing the fill into the active layer only.
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: FilterChip(
            selected: _fillAllLayers,
            label: Text(_fillAllLayers ? 'All layers ✔' : 'All layers'),
            selectedColor: const Color(0xFF30A050),
            onSelected: (v) {
              setState(() => _fillAllLayers = v);
              _send('SetFillAllLayers($_fillAllLayers)');
            },
          ),
        ));
      }
    }
    // Stroke width for figures that have one: Line always, Rect/Ellipse only in Outline mode.
    void addWidth() {
      _labeledSlider(children, 'Width', _lineWidth.toDouble(), 1, 16, (v) {
        setState(() => _lineWidth = v.round());
        _send('SetLineWidth($_lineWidth)');
        if (_hasShapeDraft) _redraw(); // the pending preview reflects the new width live
      });
    }

    if (_tool == 'Line') {
      addWidth();
    }
    if (_tool == 'Shape') {
      // Which shape to draw. Switching the kind keeps any pending draft (re-previews it live).
      const kinds = ['Ellipse', 'Triangle', 'Rectangle'];
      children.add(_toggle(['Ellipse', 'Triangle', 'Rect'], kinds.indexOf(_shapeKind), (i) {
        setState(() => _shapeKind = kinds[i]);
        _send('SelectTool($_shapeKind)'); // the engine draws by ToolKind; the shell groups them
        if (_hasShapeDraft) _redraw();
      }));
      children.add(_toggle(['Fill', 'Outline'], _shapeFill ? 0 : 1, (i) {
        setState(() => _shapeFill = i == 0);
        _send('SetShapeFill($_shapeFill)');
        if (_hasShapeDraft) _redraw(); // the pending preview reflects fill/outline live
      }));
      if (!_shapeFill) addWidth(); // outline thickness (filled shapes ignore line_width)
      // Lock the shape's aspect ratio (width:height) to the slider value — e.g. ratio 1 makes the
      // Rectangle draw squares and the Ellipse draw circles.
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: FilterChip(
          selected: _lockRatio,
          label: Text(_lockRatio ? 'Ratio ✔' : 'Lock Ratio'),
          selectedColor: const Color(0xFF30A050),
          onSelected: (v) {
            setState(() => _lockRatio = v);
            if (v) _reapplyRatio(); // snap the pending draft to the ratio immediately
          },
        ),
      ));
      if (_lockRatio) {
        // Logarithmic 0.2..5 with 1.0 at the centre (each half spans an equal ratio range).
        _labeledLogSlider(children, 'Ratio', _ratio, 0.2, 5.0, (v) {
          setState(() => _ratio = v);
          _reapplyRatio();
        });
      }
    }
    if (_tool == 'Gradient') {
      // Changing the gradient (type, colour count or any colour) updates a pending draft instantly.
      children.add(_toggle(['Linear', 'Radial'], _radial ? 1 : 0, (i) {
        setState(() => _radial = i == 1);
        _send('SetGradientType(${_radial ? 'Radial' : 'Linear'})');
        if (_hasShapeDraft) _redraw();
      }));
      // Smoothstep: ease each colour transition (S-curve) instead of a straight linear ramp.
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: FilterChip(
          selected: _gradSmooth,
          label: Text(_gradSmooth ? 'Smoothstep ✔' : 'Smoothstep'),
          selectedColor: const Color(0xFF30A050),
          onSelected: (v) {
            setState(() => _gradSmooth = v);
            _send('SetGradientSmoothstep($_gradSmooth)');
            if (_hasShapeDraft) _redraw(); // the pending gradient preview reflects it live
          },
        ),
      ));
      // Number of evenly-spaced colours in the gradient (2 / 3 / 4); the swatch count follows.
      children.add(_toggle(['2', '3', '4'], _gradCount - 2, (i) {
        setState(() => _gradCount = i + 2);
        _sendGradientStops();
      }));
      // First colour = the primary (same as the row-2 primary swatch); tapping it changes the
      // primary colour. The rest are independent gradient colours.
      children.add(_swatchButton(_primary, () => _pickColor(initial: _primary, onPick: _setPrimary)));
      for (var i = 0; i < _gradCount - 1; i++) {
        final idx = i;
        children.add(_swatchButton(_gradExtra[idx], () => _pickColor(initial: _gradExtra[idx], onPick: (c) {
              setState(() => _gradExtra[idx] = c);
              _sendGradientStops();
            })));
      }
    }
    if (_tool == 'SelectLayer') {
      // Alpha cutoff: pixels with alpha > threshold (the opaque pixels) are "selected"
      // (0 = all non-transparent; raise to keep only more-opaque pixels).
      _labeledSlider(children, 'Threshold', _alphaCutoff.toDouble(), 0, 254, (v) {
        setState(() => _alphaCutoff = v.round());
        _send('SetAlphaCutoff($_alphaCutoff)');
        _redraw(); // refresh the live preview overlay
      });
      // Replace/Add/Subtract/Intersect are one-off triggers (each applies the alpha→selection op
      // against the current selection right now) — NOT a remembered/toggled mode.
      for (final m in const ['Replace', 'Add', 'Subtract', 'Intersect']) {
        children.add(_miniBtn(m, () => _act('SelectByAlpha($m)')));
      }
      children.add(const SizedBox(width: 6));
      children.add(_miniBtn('All', () => _act('SelectAll()')));
      // Select None (and Invert) live on the floating selection-menu over the canvas.
    }
    if (_tool == 'SelectShape') {
      // Which selection shape to draft. Switching the kind keeps any pending draft (re-previews it
      // live) and re-points the engine tool so Commit combines the right shape.
      const kinds = ['Rectangle', 'Ellipse'];
      children.add(_toggle(['Rect', 'Oval'], kinds.indexOf(_selShapeKind), (i) {
        setState(() => _selShapeKind = kinds[i]);
        _send('SelectTool(${_selShapeKind == 'Ellipse' ? 'SelectEllipse' : 'SelectRect'})');
        if (_hasSelDraft) {
          _rebuildSelDraftEdges();
          setState(() {});
        }
      }));
    }
    if (_tool.startsWith('Select') && _tool != 'SelectLayer') {
      children.add(_toggle(['Replace', 'Add', 'Subtract', 'Intersect'],
          ['Replace', 'Add', 'Subtract', 'Intersect'].indexOf(_selMode), (i) {
        setState(() => _selMode = ['Replace', 'Add', 'Subtract', 'Intersect'][i]);
        _send('SetSelectionMode($_selMode)');
      }));
      children.add(_miniBtn('All', () => _act('SelectAll()')));
      // Select None / Invert live on the floating selection-menu over the canvas (they act on an
      // existing selection, which is exactly when that menu shows). Clipboard ops (Copy/Cut/Paste)
      // and Clear live in the dedicated Copy & Paste tool.
    }
    if (_tool == 'SelectShape') {
      // Lock the selection's aspect ratio (width:height) to the slider value — e.g. ratio 1 makes the
      // Rectangle draft a square and the Ellipse a circle. Independent of the Shape tool's ratio.
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: FilterChip(
          selected: _selLockRatio,
          label: Text(_selLockRatio ? 'Ratio ✔' : 'Lock Ratio'),
          selectedColor: const Color(0xFF30A050),
          onSelected: (v) {
            setState(() => _selLockRatio = v);
            if (v) _reapplySelRatio(); // snap the pending draft to the ratio immediately
          },
        ),
      ));
      if (_selLockRatio) {
        // Logarithmic 0.2..5 with 1.0 at the centre (each half spans an equal ratio range).
        _labeledLogSlider(children, 'Ratio', _selRatio, 0.2, 5.0, (v) {
          setState(() => _selRatio = v);
          _reapplySelRatio();
        });
      }
    }
    if (_tool == 'CopyPaste') {
      children.add(_miniBtn('Copy', () => _act('Copy()')));
      children.add(_miniBtn('Cut', () => _act('Cut()')));
      children.add(_miniBtn('Paste', () => _act('PasteDraft()')));
      children.add(_miniBtn('Clear', () => _act('ClearSelection()')));
    }
    if (_tool == 'HsvShift') {
      // Every slider change syncs the pending shift into the engine, whose display then
      // composites a live preview of the active layer (selection-clipped, or the whole layer
      // with no selection); the document is untouched until Apply (see hsv_preview_frame).
      void syncHsv(void Function() set) {
        setState(set);
        _send('SetHsvShift($_hsvH, $_hsvS, $_hsvV)');
        _redraw();
      }

      // The scope lives in the engine too (SetHsvScope) so the live preview honours it.
      children.add(_toggle(const ['Layer', 'Frame'], _hsvFrame ? 1 : 0, (i) {
        setState(() => _hsvFrame = i == 1);
        _send('SetHsvScope(${_hsvFrame ? 'Frame' : 'Layer'})');
        _redraw();
      }));
      _labeledSlider(children, 'H', _hsvH, -180, 180, (v) => syncHsv(() => _hsvH = v));
      _labeledSlider(children, 'S', _hsvS, -1, 1, (v) => syncHsv(() => _hsvS = v), integer: false);
      _labeledSlider(children, 'V', _hsvV, -1, 1, (v) => syncHsv(() => _hsvV = v), integer: false);
      children.add(_miniBtn('Apply', () {
        _send('SetHsvShift($_hsvH, $_hsvS, $_hsvV)');
        _act('ApplyHsvShift()');
        // The shift is baked in now; zero the sliders so the preview matches the document.
        syncHsv(() {
          _hsvH = 0;
          _hsvS = 0;
          _hsvV = 0;
        });
      }));
    }
    if (_tool == 'BrightnessContrast') {
      // The HSV block's twin: slider changes sync the pending adjustment into the engine, whose
      // display composites a live preview per the scope; the document is untouched until Apply
      // (see bc_preview_frame). Contrast is a ±100% slider around the engine's 1.0× factor.
      void syncBc(void Function() set) {
        setState(set);
        _send('SetBrightnessContrast(${_bcBright.round()}, ${1.0 + _bcContrast / 100})');
        _redraw();
      }

      children.add(_toggle(const ['Layer', 'Frame'], _bcFrame ? 1 : 0, (i) {
        setState(() => _bcFrame = i == 1);
        _send('SetBcScope(${_bcFrame ? 'Frame' : 'Layer'})');
        _redraw();
      }));
      _labeledSlider(children, 'B', _bcBright, -255, 255, (v) => syncBc(() => _bcBright = v));
      _labeledSlider(children, 'C', _bcContrast, -100, 100, (v) => syncBc(() => _bcContrast = v));
      children.add(_miniBtn('Apply', () {
        _send('SetBrightnessContrast(${_bcBright.round()}, ${1.0 + _bcContrast / 100})');
        _act('ApplyBrightnessContrast()');
        // The adjustment is baked in now; zero the sliders so the preview matches the document.
        syncBc(() {
          _bcBright = 0;
          _bcContrast = 0;
        });
      }));
    }
    if (_tool == 'Flip') {
      label(_flipFrame ? 'Flip frame' : (_outlineEdges.isNotEmpty ? 'Flip selection' : 'Flip layer'));
      children.add(_toggle(const ['Layer', 'Frame'], _flipFrame ? 1 : 0, (i) => setState(() => _flipFrame = i == 1)));
      children.add(_miniBtn('Flip H', () => _act(_flipFrame ? 'FlipFrameH()' : 'FlipH()')));
      children.add(_miniBtn('Flip V', () => _act(_flipFrame ? 'FlipFrameV()' : 'FlipV()')));
    }
    if (_tool == 'Rotate') {
      if (_hasRotateDraft) {
        // Free-angle "Angle" mode in progress: the floating commit-menu bakes/discards the draft;
        // the 90°/180° controls hide until it resolves. Row-1 just teaches the gesture.
        label('Drag the on-canvas handle to set the angle');
      } else {
        // 90°/180° and the free-angle draft act on the active layer (or the selected pixels), or
        // on every layer of the active frame in Frame scope.
        label(_rotateFrame ? 'Rotate frame' : (_outlineEdges.isNotEmpty ? 'Rotate selection' : 'Rotate layer'));
        children.add(_toggle(const ['Layer', 'Frame'], _rotateFrame ? 1 : 0, (i) => setState(() => _rotateFrame = i == 1)));
        final verb = _rotateFrame ? 'RotateFrame' : 'RotateLayer';
        children.add(IconButton(iconSize: 18, tooltip: 'Rotate 90° CW', onPressed: () => _act('$verb(1)'), icon: const Icon(Icons.rotate_right)));
        children.add(IconButton(iconSize: 18, tooltip: 'Rotate 90° CCW', onPressed: () => _act('$verb(3)'), icon: const Icon(Icons.rotate_left)));
        children.add(_miniBtn('180°', () => _act('$verb(2)')));
        children.add(const SizedBox(width: 6));
        children.add(_miniBtn('Angle', _beginRotateDraft));
      }
    }
    if (_tool == 'Invert') {
      label(_invertFrame ? 'Invert frame' : (_outlineEdges.isNotEmpty ? 'Invert selection' : 'Invert layer'));
      children.add(_toggle(const ['Layer', 'Frame'], _invertFrame ? 1 : 0, (i) => setState(() => _invertFrame = i == 1)));
      children.add(_miniBtn('Invert colours', () => _act(_invertFrame ? 'InvertFrame()' : 'Invert()')));
    }
    if (_tool == 'PlayPause') {
      final n = engine.frameCount;
      final active = engine.activeFrame;
      // Play / pause toggle — the playback control formerly on the row-3 tile. A single-frame
      // document can't animate, so the button is disabled then.
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(0, 34),
            backgroundColor: _playing ? const Color(0xFFB0703A) : const Color(0xFF4080C0),
          ),
          onPressed: n > 1 ? () => _playing ? _pause() : _play() : null,
          icon: Icon(_playing ? Icons.pause : Icons.play_arrow, size: 16),
          label: Text(_playing ? 'Pause' : 'Play'),
        ),
      ));
      children.add(const SizedBox(width: 6));
      // Prev / Next frame — pressing either auto-pauses playback first (see _stepFrame), with the
      // current "Frame X / N" between them.
      children.add(IconButton(iconSize: 22, tooltip: 'Previous frame', onPressed: () => _stepFrame(-1), icon: const Icon(Icons.skip_previous)));
      label('Frame ${active + 1} / $n');
      children.add(IconButton(iconSize: 22, tooltip: 'Next frame', onPressed: () => _stepFrame(1), icon: const Icon(Icons.skip_next)));
      children.add(const SizedBox(width: 6));
      // Go to… — type a frame number and jump to it (also auto-pauses playback first).
      children.add(_miniBtn('Go to…', _gotoFrameDialog));
    }

    return Container(
      height: 48,
      width: double.infinity, // span full width so narrow content doesn't expose the black background on each side
      color: const Color(0xFF202327),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [const SizedBox(width: 4), ...children, const SizedBox(width: 8)]),
      ),
    );
  }

  Widget _buildPalette() {
    // Swatches are laid out in two rows that scroll horizontally together: each column holds the
    // top swatch (even index) and the bottom swatch (odd index), filled column by column.
    final cols = (_palette.length + 1) ~/ 2;
    return Container(
      color: const Color(0xFF1C1F22),
      child: SizedBox(
        // Taller row-2 so the 20%-larger swatches have room — bigger, easier-to-tap colour targets.
        height: 72,
        child: Row(children: [
          GestureDetector(
            onTap: () => _pickColor(initial: _primary, onPick: _setPrimary),
            child: Container(
              width: 38, height: 38, margin: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: _primary, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white70, width: 2)),
              child: const Icon(Icons.edit, size: 13, color: Colors.white70),
            ),
          ),
          Expanded(
            // Long-press the empty area near the swatches → "Add current colour" (swatches keep
            // their own long-press menu, which wins as the deeper gesture).
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPress: _addColorMenu,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: cols,
                itemBuilder: (_, col) => Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [_paletteSwatch(col * 2), _paletteSwatch(col * 2 + 1)],
                ),
              ),
            ),
          ),
          // palette controls: tucked into a button after the last swatch
          IconButton(iconSize: 18, tooltip: 'Palette controls', onPressed: _paletteControlsMenu, icon: const Icon(Icons.palette, color: Colors.white70)),
        ]),
      ),
    );
  }

  Widget _paletteSwatch(int i) {
    if (i >= _palette.length) return const SizedBox(width: 35); // keep the column width for an odd last swatch
    final c = _palette[i];
    return GestureDetector(
      onTap: () => _setPrimary(c),
      onLongPress: () => _paletteSwatchMenu(i, c),
      child: Container(
        width: 31,
        height: 29,
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3), border: Border.all(color: Colors.black26)),
      ),
    );
  }

  // Long-pressing the empty swatch area surfaces the single "Add current colour" option (same action
  // as the palette controls menu).
  void _addColorMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.add_circle_outline),
            title: const Text('Add current colour'),
            onTap: () {
              Navigator.pop(ctx);
              _act('AddPaletteColor(${_hex(_primary)})');
            },
          ),
        ]),
      ),
    );
  }

  void _paletteControlsMenu() {
    final names = (_state['palette_names'] as List?)?.cast<String>() ?? ['Default'];
    final active = (_state['active_palette'] as int?) ?? 0;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < names.length; i++)
            ListTile(
              leading: Icon(i == active ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18),
              title: Text(names[i]),
              onTap: () { Navigator.pop(ctx); _act('SetActivePalette($i)'); },
            ),
          const Divider(height: 1),
          ListTile(leading: const Icon(Icons.add_circle_outline), title: const Text('Add current colour'), onTap: () { Navigator.pop(ctx); _act('AddPaletteColor(${_hex(_primary)})'); }),
          ListTile(leading: const Icon(Icons.add_box_outlined), title: const Text('New palette'), onTap: () { Navigator.pop(ctx); _newPalette(); }),
          ListTile(leading: const Icon(Icons.save_alt), title: const Text('Save palette'), onTap: () { Navigator.pop(ctx); _savePalette(); }),
          ListTile(leading: const Icon(Icons.file_download_outlined), title: const Text('Load palette (.json/.gpl)'), onTap: () { Navigator.pop(ctx); _loadPalette(); }),
        ]),
      ),
    );
  }

  void _paletteSwatchMenu(int i, Color c) {
    // The palette is a 2-row column-major grid (even index = top of its column, odd = bottom), so
    // left/right move a whole column (±2) and up/down swap the two rows of the column (±1). The
    // sheet follows the swatch as it moves so you can nudge it several steps without reopening.
    int cur = i;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final n = _palette.length;
        final color = (cur >= 0 && cur < n) ? _palette[cur] : c;
        final row = cur % 2;
        final left = cur - 2 >= 0 ? cur - 2 : null;
        final right = cur + 2 < n ? cur + 2 : null;
        final up = row == 1 ? cur - 1 : null;
        final down = (row == 0 && cur + 1 < n) ? cur + 1 : null;
        void move(int? partner) {
          if (partner == null) return;
          _act('SwapPaletteColors($cur, $partner)');
          setS(() => cur = partner); // follow the swatch to its new slot
        }

        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white24)),
              ),
              title: Text('Color ${cur + 1} of $n'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(tooltip: 'Move left', onPressed: left == null ? null : () => move(left), icon: const Icon(Icons.arrow_back)),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(iconSize: 20, tooltip: 'Move up', onPressed: up == null ? null : () => move(up), icon: const Icon(Icons.arrow_upward)),
                  IconButton(iconSize: 20, tooltip: 'Move down', onPressed: down == null ? null : () => move(down), icon: const Icon(Icons.arrow_downward)),
                ]),
                IconButton(tooltip: 'Move right', onPressed: right == null ? null : () => move(right), icon: const Icon(Icons.arrow_forward)),
              ]),
            ),
            const Divider(height: 1),
            ListTile(leading: const Icon(Icons.edit), title: const Text('Edit color'), onTap: () {
              Navigator.pop(ctx);
              _pickColor(initial: color, onPick: (nc) => _act('EditPaletteColor($cur, ${_hex(nc)})'));
            }),
            ListTile(leading: const Icon(Icons.copy), title: const Text('Duplicate'), onTap: () { Navigator.pop(ctx); _act('DuplicatePaletteColor($cur)'); }),
            ListTile(leading: const Icon(Icons.delete), title: const Text('Remove'), onTap: () { Navigator.pop(ctx); _act('RemovePaletteColor($cur)'); }),
          ]),
        );
      }),
    );
  }

  Future<void> _newPalette() async {
    final ctrl = TextEditingController(text: 'Palette');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New palette'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Create')),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) _act('NewPalette(${name.trim()})');
  }

  Future<void> _savePalette() async {
    final path = await FilePicker.saveFile(fileName: 'palette.gpl', type: FileType.custom, allowedExtensions: ['gpl', 'json']);
    if (path == null) return;
    final names = (_state['palette_names'] as List?)?.cast<String>() ?? ['Palette'];
    final active = (_state['active_palette'] as int?) ?? 0;
    final pname = active < names.length ? names[active] : 'Palette';
    final sb = StringBuffer('GIMP Palette\nName: $pname\nColumns: 0\n#\n');
    for (final c in _palette) {
      sb.writeln('${(c.r * 255).round()}\t${(c.g * 255).round()}\t${(c.b * 255).round()}\t${_hex(c)}');
    }
    await File(path).writeAsString(sb.toString());
    _toast('Saved palette (${_palette.length} colors)');
  }

  Future<void> _loadPalette() async {
    final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['gpl', 'json', 'txt']);
    if (res == null || res.files.single.path == null) return;
    final text = await File(res.files.single.path!).readAsString();
    final colors = _parsePalette(text);
    if (colors.isEmpty) {
      _toast('No colors found');
      return;
    }
    _send('NewPalette(${res.files.single.name.split('.').first})');
    for (final c in colors) {
      _send('AddPaletteColor(${_hex(c)})');
    }
    _refreshState();
    setState(() {});
    _toast('Loaded ${colors.length} colors');
  }

  List<Color> _parsePalette(String text) {
    final out = <Color>[];
    // try JSON array of hex strings
    final t = text.trim();
    if (t.startsWith('[')) {
      try {
        for (final h in (json.decode(t) as List)) {
          out.add(_parseHex(h.toString()));
        }
        return out;
      } catch (_) {}
    }
    // GIMP .gpl: lines of "R G B  name"
    for (final line in text.split('\n')) {
      final l = line.trim();
      if (l.isEmpty || l.startsWith('#') || l.startsWith('GIMP') || l.startsWith('Name:') || l.startsWith('Columns:')) continue;
      final parts = l.split(RegExp(r'\s+'));
      if (parts.length >= 3) {
        final r = int.tryParse(parts[0]), g = int.tryParse(parts[1]), b = int.tryParse(parts[2]);
        if (r != null && g != null && b != null) out.add(Color.fromARGB(255, r, g, b));
      }
    }
    return out;
  }

  // The static visual of a tool tile (icon + label, highlighted when selected/hovered).
}
