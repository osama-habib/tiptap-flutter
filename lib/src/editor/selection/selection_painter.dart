// Paints the cursor (blinking caret) and selection highlights over the
// rendered document.
//
// The painter reads the current selection state from the editor controller
// and uses the position registry to convert ProseMirror positions to pixel
// coordinates. It supports both collapsed selections (cursor) and range
// selections (highlighted rectangles).
//
// Repaint isolation contract:
// The editor wraps this overlay in its own RepaintBoundary so the cursor
// blink re-rasterizes only this near-empty layer instead of the layer
// containing all document text. That isolation removes two implicit repaint
// triggers this painter used to depend on without knowing it:
//
//   - Scrolling: the painter resolves pixel positions through the registry
//     at paint time, so it stayed visually in sync during scroll only
//     because scrolling dirtied the shared layer and forced a repaint every
//     tick. In its own layer, the overlay must be told about scrolls
//     explicitly — the [repaint] listenable (the editor's scroll controller)
//     carries that signal straight to the render object, repainting the
//     small overlay layer without a widget rebuild.
//
//   - Layout changes without selection changes: an edit that reflows text
//     while the selection state stays value-equal (e.g., toggling a heading
//     at a collapsed cursor) moves the caret's pixel position without
//     changing anything shouldRepaint used to compare. The shared layer
//     masked this too. shouldRepaint is therefore unconditional now — see
//     the override for why that is the cheapest correct answer.

import 'package:flutter/material.dart';

import '../../engine/protocol_types.dart';
import 'position_registry.dart';

/// A widget that overlays cursor and selection painting on top of the
/// rendered document.
///
/// This widget must be the same size as and perfectly aligned with the
/// document renderer so that the pixel coordinates from the position
/// registry map correctly.
class EditorSelectionOverlay extends StatefulWidget {
  /// The current selection state from the engine.
  final SelectionState? selection;

  /// The position registry populated by the document renderer.
  final PositionRegistry registry;

  /// Whether the editor currently has focus. The cursor only blinks
  /// when focused.
  final bool hasFocus;

  /// External repaint trigger forwarded to the painter's repaint listenable.
  ///
  /// The editor passes its scroll controller here: with this overlay in its
  /// own RepaintBoundary, scrolling the document no longer implicitly
  /// repaints it, so the caret and highlights would freeze while text
  /// scrolls underneath. Wiring the scroll controller through
  /// CustomPainter's repaint mechanism repaints exactly this layer on every
  /// scroll tick — no setState, no widget rebuild, no document raster work.
  final Listenable? repaint;

  /// The color used for the cursor caret.
  final Color cursorColor;

  /// The color used for selection highlight rectangles.
  final Color selectionColor;

  const EditorSelectionOverlay({
    super.key,
    required this.selection,
    required this.registry,
    this.hasFocus = true,
    this.repaint,
    this.cursorColor = const Color(0xFF1A73E8),
    this.selectionColor = const Color(0x401A73E8),
  });

  @override
  State<EditorSelectionOverlay> createState() => _EditorSelectionOverlayState();
}

class _EditorSelectionOverlayState extends State<EditorSelectionOverlay>
    with SingleTickerProviderStateMixin {
  /// Animation controller for the cursor blink effect.
  late AnimationController _blinkController;

  /// Whether the cursor is currently visible in the blink cycle.
  bool _cursorVisible = true;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _blinkController.addStatusListener(_onBlinkStatus);
    _startBlinking();
  }

  @override
  void didUpdateWidget(EditorSelectionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    /// Reset the blink cycle when the selection changes so the cursor
    /// is immediately visible at its new position.
    if (oldWidget.selection != widget.selection) {
      _resetBlink();
    }
    if (oldWidget.hasFocus != widget.hasFocus) {
      if (widget.hasFocus) {
        _startBlinking();
      } else {
        _stopBlinking();
      }
    }
  }

  void _onBlinkStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      setState(() {
        _cursorVisible = !_cursorVisible;
      });
      _blinkController.forward(from: 0);
    }
  }

  void _startBlinking() {
    _cursorVisible = true;
    _blinkController.forward(from: 0);
  }

  void _stopBlinking() {
    _blinkController.stop();
    _cursorVisible = false;
  }

  void _resetBlink() {
    _blinkController.stop();
    setState(() {
      _cursorVisible = true;
    });
    _blinkController.forward(from: 0);
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SelectionPainter(
        selection: widget.selection,
        registry: widget.registry,
        showCursor: widget.hasFocus && _cursorVisible,
        cursorColor: widget.cursorColor,
        selectionColor: widget.selectionColor,
        parentContext: context,
        repaint: widget.repaint,
      ),
    );
  }
}

/// Custom painter that draws the cursor and selection highlights.
///
/// For collapsed selections (cursor), it draws a thin vertical line at
/// the caret position. For range selections, it draws filled rectangles
/// behind the selected text.
class _SelectionPainter extends CustomPainter {
  final SelectionState? selection;
  final PositionRegistry registry;
  final bool showCursor;
  final Color cursorColor;
  final Color selectionColor;
  final BuildContext parentContext;

  /// Width of the cursor caret in logical pixels.
  static const double _cursorWidth = 2.0;

  /// The repaint listenable (the editor's scroll controller) is forwarded
  /// to CustomPainter so scroll notifications mark this painter's render
  /// object dirty directly, keeping the overlay in sync with the document
  /// scrolling beneath its RepaintBoundary.
  _SelectionPainter({
    required this.selection,
    required this.registry,
    required this.showCursor,
    required this.cursorColor,
    required this.selectionColor,
    required this.parentContext,
    Listenable? repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    if (selection == null) return;

    if (selection!.empty) {
      /// Collapsed selection — draw a cursor caret.
      if (showCursor) {
        _paintCursor(canvas, selection!.from);
      }
    } else {
      /// Range selection — draw highlight rectangles, then a cursor at head.
      _paintSelectionHighlight(canvas, selection!.from, selection!.to);
      if (showCursor) {
        _paintCursor(canvas, selection!.head);
      }
    }
  }

  /// Paint a blinking cursor caret at the given ProseMirror position.
  void _paintCursor(Canvas canvas, int docPos) {
    /// Find the RenderObject that contains this overlay so we can convert
    /// from global coordinates to our local coordinate space.
    final overlayRenderObject = parentContext.findRenderObject();
    if (overlayRenderObject == null) return;

    final globalOffset = registry.globalOffsetFromPosition(docPos);
    if (globalOffset == null) return;

    final caretHeight = registry.caretHeightAtPosition(docPos) ?? 20.0;

    /// Convert global offset to this overlay's local coordinate space.
    final RenderBox overlayBox = overlayRenderObject as RenderBox;
    final localOffset = overlayBox.globalToLocal(globalOffset);

    final paint = Paint()
      ..color = cursorColor
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          localOffset.dx - _cursorWidth / 2,
          localOffset.dy,
          _cursorWidth,
          caretHeight,
        ),
        const Radius.circular(1),
      ),
      paint,
    );
  }

  /// Paint selection highlight rectangles between two ProseMirror positions.
  ///
  /// Coordinate-space note: [from] and [to] are actual ProseMirror positions
  /// (from the engine's selection), while each registered block's pos/end
  /// are serializer-space token positions (1 higher than actual positions,
  /// and spanning the block's opening/closing tokens rather than its text).
  /// The original implementation clamped the selection against that token
  /// range; for every block except the one containing the selection's end,
  /// the clamp produced the block's end-token position, which
  /// posToLocalOffset cannot map (it lies outside the block's text spans) —
  /// so those blocks were silently skipped and multi-block selections
  /// painted only their last block.
  ///
  /// The overlap is therefore computed against the block's TEXT content
  /// range ([RegisteredBlock.textContentStart] / [textContentEnd], which
  /// the registry exposes already compensated to actual positions). That is
  /// exactly the domain posToLocalOffset can always map, so every block the
  /// selection touches produces highlight boxes.
  void _paintSelectionHighlight(Canvas canvas, int from, int to) {
    final overlayRenderObject = parentContext.findRenderObject();
    if (overlayRenderObject == null) return;
    final RenderBox overlayBox = overlayRenderObject as RenderBox;

    final paint = Paint()
      ..color = selectionColor
      ..style = PaintingStyle.fill;

    /// Walk through all registered blocks and paint highlights for the
    /// portions that fall within the selection range.
    for (final block in registry.blocks) {
      final rp = block.renderParagraph;
      if (rp == null || !rp.attached) continue;

      /// The block's mappable text range in actual ProseMirror positions.
      /// Null only if the block registered no span mappings (which the
      /// renderer never produces — even empty blocks register one).
      final contentStart = block.textContentStart;
      final contentEnd = block.textContentEnd;
      if (contentStart == null || contentEnd == null) continue;

      /// Compute the overlap between the selection and this block's text
      /// range. Both sides are now actual ProseMirror positions, and the
      /// clamped result is always mappable by posToLocalOffset. Blocks
      /// entirely outside the selection collapse to a zero-width overlap
      /// and are skipped.
      final blockSelStart = from.clamp(contentStart, contentEnd);
      final blockSelEnd = to.clamp(contentStart, contentEnd);
      if (blockSelStart >= blockSelEnd) continue;

      /// Convert ProseMirror positions to local text offsets within the block.
      final localStartRaw = block.posToLocalOffset(blockSelStart);
      final localEndRaw = block.posToLocalOffset(blockSelEnd);
      if (localStartRaw == null || localEndRaw == null) continue;

      /// Clamp the local offsets to the block's flattened text length so
      /// getBoxesForSelection never receives an out-of-range extent. This
      /// matters for empty blocks: they render a single zero-width space,
      /// but their zero-length span mapping covers the block's full
      /// position range, so an unclamped offset can exceed the text length.
      final lastMapping = block.spanMappings.last;
      final textLength = lastMapping.localStart + lastMapping.length;
      final localStart = localStartRaw.clamp(0, textLength);
      final localEnd = localEndRaw.clamp(0, textLength);
      if (localStart >= localEnd) continue;

      /// Get the selection rectangles from the RenderParagraph.
      final boxes = rp.getBoxesForSelection(
        TextSelection(baseOffset: localStart, extentOffset: localEnd),
      );

      for (final box in boxes) {
        /// Convert from the RenderParagraph's local coordinates to global,
        /// then to this overlay's local coordinates.
        final topLeft = rp.localToGlobal(Offset(box.left, box.top));
        final bottomRight = rp.localToGlobal(Offset(box.right, box.bottom));

        final localTopLeft = overlayBox.globalToLocal(topLeft);
        final localBottomRight = overlayBox.globalToLocal(bottomRight);

        canvas.drawRect(Rect.fromPoints(localTopLeft, localBottomRight), paint);
      }
    }
  }

  /// Unconditionally repaint whenever the overlay rebuilds.
  ///
  /// The painter resolves every pixel position at paint time through the
  /// registry, so its output depends on document layout — which the
  /// delegate's own fields say nothing about. An edit can reflow text while
  /// selection, focus, and colors all stay value-equal (toggling a heading
  /// at a collapsed cursor moves the caret without changing the selection),
  /// and comparing those fields would skip the repaint and leave the caret
  /// at its stale pixel position. The shared layer used to mask this class
  /// of miss; the RepaintBoundary makes it visible.
  ///
  /// Returning true costs one repaint of a near-empty layer per overlay
  /// rebuild (stateChanged, blink tick, chrome setState) — negligible, and
  /// strictly cheaper than introducing a document-revision identity on the
  /// protocol types just to compare here.
  @override
  bool shouldRepaint(_SelectionPainter oldDelegate) => true;
}
