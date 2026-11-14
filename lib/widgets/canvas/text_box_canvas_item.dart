import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import '../../models/editor_models.dart';
import '../../services/editor_settings_service.dart';
import 'canvas_item_shared.dart';

class _LatexQuickOperatorsStrip extends StatelessWidget {
  final Color accentColor;
  final ValueChanged<String> onInsert;

  const _LatexQuickOperatorsStrip({
    required this.accentColor,
    required this.onInsert,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<EditorSettings>(
        valueListenable: EditorSettingsService.settingsNotifier,
        builder: (context, settings, _) {
          final ops = settings.latexQuickOperators;
          if (ops.isEmpty) return const SizedBox.shrink();
          return Container(
            height: 58,
            margin: const EdgeInsets.only(bottom: 4),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: ops.length,
              separatorBuilder: (_, _) => const SizedBox(width: 5),
              itemBuilder: (context, idx) {
                final op = ops[idx];
                return InkWell(
                  borderRadius: BorderRadius.circular(5),
                  onTap: () => onInsert(op),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.22),
                        width: 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Math.tex(
                      op,
                      textStyle: TextStyle(fontSize: 13, color: accentColor),
                      mathStyle: MathStyle.display,
                      onErrorFallback: (_) => Text(
                        op,
                        style: TextStyle(fontSize: 11, color: accentColor),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class TextBoxCanvasItem extends StatefulWidget {
  final DrawnTextBox textBox;
  final AppFontFamily textBoxFont;
  final TransformationController? transformationController;
  final bool isEditing;
  final VoidCallback onStartEditing;
  final VoidCallback onFinishEditing;
  final void Function(
    String newText,
    Offset newPosition,
    double newFontSize,
    double newWidth,
  ) onUpdate;
  final void Function(Offset oldPosition, double? oldWidth)
      onLayoutModificationCommitted;
  final VoidCallback onDelete;

  const TextBoxCanvasItem({
    super.key,
    required this.textBox,
    this.textBoxFont = AppFontFamily.sansSerif,
    this.transformationController,
    required this.isEditing,
    required this.onStartEditing,
    required this.onFinishEditing,
    required this.onUpdate,
    required this.onLayoutModificationCommitted,
    required this.onDelete,
  });

  @override
  State<TextBoxCanvasItem> createState() => _TextBoxCanvasItemState();
}

class _TextBoxCanvasItemState extends State<TextBoxCanvasItem> {
  late Offset _position;
  late TextEditingController _textController;
  late FocusNode _focusNode;
  late double _fontSize;
  late double _width;
  bool _isDeleting = false;

  Offset? _dragOrigPosition;
  double? _dragOrigWidth;

  double get _currentScale =>
      (widget.transformationController?.value.getMaxScaleOnAxis() ?? 1.0)
          .clamp(0.2, 5.0);

  @override
  void initState() {
    super.initState();
    _position = widget.textBox.position;
    _fontSize = widget.textBox.fontSize;
    _width = widget.textBox.width ?? (widget.textBox.isLatex ? 250.0 : 220.0);
    _textController = TextEditingController(text: widget.textBox.text);
    _focusNode = FocusNode();
  }

  void _insertOperator(String op) {
    final text = _textController.text;
    final selection = _textController.selection;
    final int start = selection.isValid ? selection.start : text.length;
    final int end = selection.isValid ? selection.end : text.length;

    final newText = text.replaceRange(start, end, op);
    final newCursorPos = start + op.length;

    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursorPos),
    );

    widget.onUpdate(newText, _position, _fontSize, _width);
  }

  void _startLayoutDrag() {
    _dragOrigPosition = _position;
    _dragOrigWidth = widget.textBox.width ?? _width;
  }

  void _commitLayoutDrag() {
    if (_dragOrigPosition != null) {
      widget.onLayoutModificationCommitted(_dragOrigPosition!, _dragOrigWidth);
    }
    _dragOrigPosition = null;
    _dragOrigWidth = null;
  }

  void _commitAndFinish() {
    if (_isDeleting || !widget.isEditing) return;
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _isDeleting = true;
      _focusNode.unfocus();
      widget.onDelete();
    } else {
      widget.onUpdate(text, _position, _fontSize, _width);
      _focusNode.unfocus();
      widget.onFinishEditing();
    }
  }

  @override
  void didUpdateWidget(covariant TextBoxCanvasItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.textBox.id != widget.textBox.id) {
      _isDeleting = false;
    }
    _position = widget.textBox.position;
    _fontSize = widget.textBox.fontSize;
    if (widget.textBox.width != null) {
      _width = widget.textBox.width!;
    }
    if ((!widget.isEditing || oldWidget.textBox.id != widget.textBox.id) &&
        _textController.text != widget.textBox.text) {
      _textController.text = widget.textBox.text;
    }
    if (oldWidget.isEditing && !widget.isEditing && !_isDeleting) {
      final text = _textController.text.trim();
      if (text.isEmpty) {
        _isDeleting = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onDelete();
        });
      } else {
        widget.textBox.text = text;
        widget.textBox.fontSize = _fontSize;
        widget.textBox.position = _position;
        widget.textBox.width = _width;
      }
    }
    if (!oldWidget.isEditing && widget.isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _textController.dispose();
    super.dispose();
  }

  Widget _buildResizeHandle() {
    final tc = widget.transformationController;
    Widget buildPill(double scale) {
      final touchW = 48.0 / scale;
      final touchH = 56.0 / scale;
      return Positioned(
        right: -touchW * 0.5,
        top: 0,
        bottom: 0,
        child: Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => _startLayoutDrag(),
            onPanUpdate: (details) {
              _width = math.max(80.0, _width + details.delta.dx / _currentScale);
              widget.onUpdate(
                widget.isEditing ? _textController.text : widget.textBox.text,
                _position,
                _fontSize,
                _width,
              );
            },
            onPanEnd: (_) => _commitLayoutDrag(),
            onPanCancel: _commitLayoutDrag,
            child: Container(
              width: touchW,
              height: touchH,
              alignment: Alignment.center,
              color: Colors.transparent,
              child: Container(
                width: 7.0 / scale,
                height: 28.0 / scale,
                decoration: BoxDecoration(
                  color: widget.isEditing
                      ? widget.textBox.color
                      : widget.textBox.color.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(4.0 / scale),
                  border: Border.all(
                    color: Colors.white,
                    width: math.max(1.0, 1.5 / scale),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (tc != null) {
      return ValueListenableBuilder<Matrix4>(
        valueListenable: tc,
        builder: (_, _, _) => buildPill(_currentScale),
      );
    }
    return buildPill(1.0);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isEditing) {
      final textInput = Container(
        width: _width,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          border: Border.all(color: widget.textBox.color, width: 2.0),
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => _startLayoutDrag(),
                  onPanUpdate: (details) {
                    _position += details.delta / _currentScale;
                    widget.onUpdate(
                      _textController.text,
                      _position,
                      _fontSize,
                      _width,
                    );
                  },
                  onPanEnd: (_) => _commitLayoutDrag(),
                  onPanCancel: _commitLayoutDrag,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: widget.textBox.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.drag_indicator_rounded,
                          size: 14,
                          color: widget.textBox.color,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'Drag',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: widget.textBox.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.textBox.isLatex) ...[
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: widget.textBox.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.functions_rounded,
                          size: 12,
                          color: widget.textBox.color,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'LaTeX',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: widget.textBox.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            if (widget.textBox.isLatex) ...[
              const SizedBox(height: 6),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _textController,
                builder: (context, value, _) {
                  final raw = value.text.trim();
                  return Container(
                    constraints: const BoxConstraints(minHeight: 38),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: widget.textBox.color.withValues(alpha: 0.25),
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Math.tex(
                          raw.isEmpty ? r'\dots' : value.text,
                          textStyle: TextStyle(
                            color: widget.textBox.color,
                            fontSize: _fontSize,
                          ),
                          mathStyle: MathStyle.display,
                          onErrorFallback: (err) => Text(
                            err.message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: math.max(10.0, _fontSize * 0.65),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 6),
              _LatexQuickOperatorsStrip(
                accentColor: widget.textBox.color,
                onInsert: _insertOperator,
              ),
            ],
            const SizedBox(height: 4),
            TextField(
              controller: _textController,
              focusNode: _focusNode,
              autofocus: true,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              cursorColor: widget.textBox.color,
              style: TextStyle(
                color: widget.textBox.color,
                fontSize: widget.textBox.isLatex
                    ? math.max(13.0, _fontSize * 0.85)
                    : _fontSize,
                fontWeight: FontWeight.w600,
                height: 1.3,
                fontFamily: widget.textBox.isLatex
                    ? 'monospace'
                    : widget.textBoxFont.cssFontFamily,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                border: InputBorder.none,
                hintText: widget.textBox.isLatex
                    ? r'Type LaTeX (e.g. \frac{a}{b})'
                    : 'Type text...',
                hintStyle: TextStyle(color: Colors.black38, fontSize: _fontSize),
              ),
              onChanged: (val) {
                widget.onUpdate(val, _position, _fontSize, _width);
              },
            ),
          ],
        ),
      );

      return TapRegion(
        groupId: kEditableElementRegionGroup,
        onTapOutside: (_) => _commitAndFinish(),
        child: Material(
          color: Colors.transparent,
          elevation: 0,
          child: DocumentStack(
            clipBehavior: Clip.none,
            children: [textInput, _buildResizeHandle()],
          ),
        ),
      );
    }

    if (widget.textBox.text.isEmpty) {
      return const SizedBox.shrink();
    }

    final Widget displayedWidget;
    if (widget.textBox.isLatex) {
      displayedWidget = Container(
        width: _width,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: widget.textBox.color.withValues(alpha: 0.3),
            width: 1.0,
          ),
        ),
        child: ClipRect(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Math.tex(
              widget.textBox.text,
              textStyle: TextStyle(
                color: widget.textBox.color,
                fontSize: widget.textBox.fontSize,
              ),
              mathStyle: MathStyle.display,
              onErrorFallback: (err) => Text(
                widget.textBox.text,
                style: TextStyle(
                  color: widget.textBox.color,
                  fontSize: widget.textBox.fontSize,
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      displayedWidget = Container(
        width: _width,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: widget.textBox.color.withValues(alpha: 0.3),
            width: 1.0,
          ),
        ),
        child: Text(
          widget.textBox.text,
          softWrap: true,
          style: TextStyle(
            color: widget.textBox.color,
            fontSize: widget.textBox.fontSize,
            fontWeight: FontWeight.w500,
            height: 1.3,
            fontFamily: widget.textBoxFont.cssFontFamily,
          ),
        ),
      );
    }

    final textContent = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onStartEditing,
      onPanStart: (_) => _startLayoutDrag(),
      onPanUpdate: (details) {
        _position += details.delta / _currentScale;
        widget.onUpdate(widget.textBox.text, _position, _fontSize, _width);
      },
      onPanEnd: (_) => _commitLayoutDrag(),
      onPanCancel: _commitLayoutDrag,
      child: displayedWidget,
    );

    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: DocumentStack(
        clipBehavior: Clip.none,
        children: [textContent, _buildResizeHandle()],
      ),
    );
  }
}
