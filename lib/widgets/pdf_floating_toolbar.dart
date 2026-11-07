import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/editor_models.dart';

class PdfFloatingToolbar extends StatefulWidget {
  final EditorTool activeTool;
  final ShapeType activeShape;
  final Color activeColor;
  final double activeStrokeWidth;
  final double activeFontSize;
  final bool isStylusDetected;
  final bool isEraserActive;
  final bool stylusOnlyMode;
  final bool canUndo;
  final Offset? initialPosition;
  final ValueChanged<Offset>? onPositionChanged;
  final bool initialIsCollapsed;
  final ValueChanged<bool>? onCollapsedChanged;
  final ValueChanged<EditorTool> onToolSelected;
  final ValueChanged<ShapeType> onShapeSelected;
  final ValueChanged<Color> onColorSelected;
  final ValueChanged<double> onStrokeWidthSelected;
  final ValueChanged<double>? onFontSizeSelected;
  final ValueChanged<bool> onStylusOnlyModeToggled;
  final VoidCallback onUndo;
  final VoidCallback onManagePages;
  final VoidCallback onSave;

  const PdfFloatingToolbar({
    super.key,
    required this.activeTool,
    required this.activeShape,
    required this.activeColor,
    required this.activeStrokeWidth,
    this.activeFontSize = 16.0,
    required this.isStylusDetected,
    this.isEraserActive = false,
    required this.stylusOnlyMode,
    required this.canUndo,
    this.initialPosition,
    this.onPositionChanged,
    this.initialIsCollapsed = false,
    this.onCollapsedChanged,
    required this.onToolSelected,
    required this.onShapeSelected,
    required this.onColorSelected,
    required this.onStrokeWidthSelected,
    this.onFontSizeSelected,
    required this.onStylusOnlyModeToggled,
    required this.onUndo,
    required this.onManagePages,
    required this.onSave,
  });

  @override
  State<PdfFloatingToolbar> createState() => _PdfFloatingToolbarState();
}

class _PdfFloatingToolbarState extends State<PdfFloatingToolbar> {
  late Offset _position;
  late bool _isCollapsed;
  bool _isSavingToolbar = false;
  bool _showSaveSuccess = false;

  void _handlePanUpdate(DragUpdateDetails details) {
    setState(() {
      _position += details.delta;
    });
  }

  void _handlePanEnd(DragEndDetails details, double toolbarWidth, Size screenSize) {
    final clampedPos = Offset(
      _position.dx.clamp(4.0, math.max(4.0, screenSize.width - toolbarWidth - 4.0)),
      _position.dy.clamp(50.0, math.max(50.0, screenSize.height - 120.0)),
    );
    _position = clampedPos;
    widget.onPositionChanged?.call(clampedPos);
  }

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition ?? const Offset(12, 100);
    _isCollapsed = widget.initialIsCollapsed;
  }

  @override
  void didUpdateWidget(covariant PdfFloatingToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPosition != null &&
        oldWidget.initialPosition != widget.initialPosition) {
      _position = widget.initialPosition!;
    }
    if (oldWidget.initialIsCollapsed != widget.initialIsCollapsed) {
      _isCollapsed = widget.initialIsCollapsed;
    }
  }

  final List<Color> _palette = const [
    Color(0xFFFFEB3B), // Yellow (Highlighter)
    Color(0xFFFF9800), // Orange
    Color(0xFFF44336), // Red
    Color(0xFFE91E63), // Pink
    Color(0xFF9C27B0), // Purple
    Color(0xFF2196F3), // Blue
    Color(0xFF009688), // Teal
    Color(0xFF4CAF50), // Green
    Color(0xFF212121), // Black
  ];

  void _showAnchoredPopup(BuildContext buttonContext, Widget Function(BuildContext) builder) {
    final renderBox = buttonContext.findRenderObject() as RenderBox?;
    final offset = renderBox?.localToGlobal(Offset.zero) ?? const Offset(100, 100);
    final size = renderBox?.size ?? const Size(48, 48);
    final screenSize = MediaQuery.of(context).size;

    final isLeftHalf = offset.dx < screenSize.width / 2;
    final left = isLeftHalf ? offset.dx + size.width + 10 : null;
    final right = !isLeftHalf ? (screenSize.width - offset.dx) + 10 : null;
    final top = (offset.dy - 60).clamp(40.0, math.max(40.0, screenSize.height - 380.0)).toDouble();

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.12),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, anim1, anim2) {
        return Stack(
          children: [
            Positioned(
              left: left,
              right: right,
              top: top,
              child: Material(
                color: Colors.transparent,
                child: builder(dialogContext),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.88, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
            ),
            alignment: isLeftHalf ? Alignment.centerLeft : Alignment.centerRight,
            child: child,
          ),
        );
      },
    );
  }

  void _showColorPicker(BuildContext buttonContext) {
    _showAnchoredPopup(buttonContext, (dialogContext) {
      final theme = Theme.of(context);
      return Card(
        elevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: theme.colorScheme.surface,
        child: Container(
          width: 220,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.palette_outlined, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text(
                    'Color Palette',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _palette.map((color) {
                  final isSelected = widget.activeColor.toARGB32() == color.toARGB32();
                  return GestureDetector(
                    onTap: () {
                      widget.onColorSelected(color);
                      Navigator.pop(dialogContext);
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.black26,
                          width: isSelected ? 3 : 1,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.6),
                                  blurRadius: 6,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? Icon(
                              Icons.check,
                              size: 18,
                              color: color.computeLuminance() > 0.5
                                  ? Colors.black
                                  : Colors.white,
                            )
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      );
    });
  }

  void _showStrokeWidthPicker(BuildContext buttonContext) {
    _showAnchoredPopup(buttonContext, (dialogContext) {
      final theme = Theme.of(context);
      const widths = [1.0, 1.5, 2.0, 3.0, 5.0, 8.0, 12.0];
      return Card(
        elevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: theme.colorScheme.surface,
        child: Container(
          width: 210,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.line_weight_rounded, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text(
                    'Stroke Width',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Column(
                children: widths.map((width) {
                  final isSelected = (widget.activeStrokeWidth - width).abs() < 0.1;
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      widget.onStrokeWidthSelected(width);
                      Navigator.pop(dialogContext);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                            : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 52,
                            child: Text(
                              '${width.toStringAsFixed(1)} pt',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? theme.colorScheme.primary : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              height: width,
                              decoration: BoxDecoration(
                                color: isSelected ? theme.colorScheme.primary : Colors.grey.shade600,
                                borderRadius: BorderRadius.circular(width / 2),
                              ),
                            ),
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.check_rounded, size: 16, color: theme.colorScheme.primary),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      );
    });
  }

  void _showFontSizePicker(BuildContext buttonContext) {
    _showAnchoredPopup(buttonContext, (dialogContext) {
      final theme = Theme.of(context);
      const fontSizes = [10.0, 12.0, 14.0, 16.0, 18.0, 20.0, 24.0, 28.0, 32.0];
      return Card(
        elevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: theme.colorScheme.surface,
        child: Container(
          width: 200,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.format_size_rounded, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text(
                    'Font Size',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: fontSizes.map((size) {
                  final isSelected = (widget.activeFontSize - size).abs() < 0.1;
                  return ChoiceChip(
                    label: Text('${size.toInt()} pt'),
                    selected: isSelected,
                    visualDensity: VisualDensity.compact,
                    onSelected: (selected) {
                      if (selected) {
                        widget.onFontSizeSelected?.call(size);
                        Navigator.pop(dialogContext);
                      }
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      );
    });
  }

  void _showShapePicker(BuildContext buttonContext) {
    _showAnchoredPopup(buttonContext, (dialogContext) {
      final theme = Theme.of(context);
      return Card(
        elevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: theme.colorScheme.surface,
        child: Container(
          width: 200,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.category_outlined, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text(
                      'Select Shape',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              _buildShapeOption(
                dialogContext,
                type: ShapeType.rectangle,
                icon: Icons.rectangle_outlined,
                title: 'Rectangle',
              ),
              _buildShapeOption(
                dialogContext,
                type: ShapeType.circle,
                icon: Icons.circle_outlined,
                title: 'Circle / Ellipse',
              ),
              _buildShapeOption(
                dialogContext,
                type: ShapeType.line,
                icon: Icons.horizontal_rule_rounded,
                title: 'Straight Line',
              ),
              _buildShapeOption(
                dialogContext,
                type: ShapeType.arrow,
                icon: Icons.arrow_forward_rounded,
                title: 'Arrow',
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildShapeOption(
    BuildContext dialogContext, {
    required ShapeType type,
    required IconData icon,
    required String title,
  }) {
    final isSelected = widget.activeTool == EditorTool.shape && widget.activeShape == type;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Icon(icon, size: 20),
      title: Text(title, style: const TextStyle(fontSize: 13)),
      trailing: isSelected ? const Icon(Icons.check, size: 18, color: Colors.blue) : null,
      onTap: () {
        widget.onToolSelected(EditorTool.shape);
        widget.onShapeSelected(type);
        Navigator.pop(dialogContext);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.of(context).size;
    final toolbarWidth = _isCollapsed ? 48.0 : 54.0;

    return Positioned(
      left: _position.dx.clamp(4.0, math.max(4.0, screenSize.width - toolbarWidth - 4.0)),
      top: _position.dy.clamp(50.0, math.max(50.0, screenSize.height - 120.0)),
      child: Material(
        elevation: 6,
        shadowColor: Colors.black38,
        borderRadius: BorderRadius.circular(28),
        color: theme.colorScheme.surface.withValues(alpha: 0.95),
        child: Container(
          width: toolbarWidth,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: _isCollapsed
              ? GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: _handlePanUpdate,
                  onPanEnd: (d) => _handlePanEnd(d, toolbarWidth, screenSize),
                  child: IconButton(
                    icon: const Icon(Icons.edit_note_rounded),
                    tooltip: 'Expand Tools',
                    onPressed: () {
                      setState(() => _isCollapsed = false);
                      widget.onCollapsedChanged?.call(false);
                    },
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top Drag Handle (isolated gesture recognizer)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: _handlePanUpdate,
                      onPanEnd: (d) => _handlePanEnd(d, toolbarWidth, screenSize),
                      child: Container(
                        width: toolbarWidth,
                        height: 28,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        color: Colors.transparent,
                        child: const Icon(Icons.drag_handle_rounded, size: 20, color: Colors.grey),
                      ),
                    ),

                    // Scrollable Tool Body (free from parent pan interception)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: screenSize.height * 0.70,
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Tool: Select / Navigation
                              Builder(
                                builder: (btnContext) {
                                  final isDualInput = widget.isStylusDetected &&
                                      (widget.activeTool == EditorTool.pen ||
                                       widget.activeTool == EditorTool.select ||
                                       widget.isEraserActive);
                                  return _buildToolButton(
                                    icon: Icons.pan_tool_alt_rounded,
                                    tooltip: widget.isStylusDetected
                                        ? 'Touch (Finger Touch, Move & Resize)'
                                        : 'Select & Move (Text Selection)',
                                    isSelected: isDualInput || widget.activeTool == EditorTool.select,
                                    onPressed: () => widget.onToolSelected(EditorTool.select),
                                  );
                                },
                              ),

                              // Tool: Pen / Stylus / Eraser
                              // In dual input mode (stylus connected), both Touch and Pen are active.
                              // In eraser mode: icon changes to eraser, dot turns bright RED.
                              // In pen mode: icon is pen, dot turns bright GREEN if stylus connected.
                              Builder(
                                builder: (btnContext) {
                                  final isDualInput = widget.isStylusDetected &&
                                      (widget.activeTool == EditorTool.pen ||
                                       widget.activeTool == EditorTool.select ||
                                       widget.isEraserActive);
                                  return _buildToolButton(
                                    icon: widget.isEraserActive
                                        ? Icons.cleaning_services_rounded
                                        : Icons.edit_rounded,
                                    tooltip: widget.isEraserActive
                                        ? 'Eraser Active 🔴 (Click to switch to Pen)'
                                        : widget.isStylusDetected
                                            ? 'Pen (Stylus Handwriting 🖊️ 🟢, click to switch to Eraser)'
                                            : 'Pen / Stylus Drawing',
                                    isSelected: isDualInput || widget.activeTool == EditorTool.pen || widget.isEraserActive,
                                    indicatorDotColor: widget.isEraserActive
                                        ? const Color(0xFFFF1744) // Bright Red when eraser active
                                        : widget.isStylusDetected
                                            ? const Color(0xFF00E676) // Bright Green when stylus connected
                                            : null,
                                    onPressed: () {
                                      if (widget.isEraserActive) {
                                        widget.onToolSelected(EditorTool.pen);
                                      } else if (widget.activeTool == EditorTool.pen) {
                                        widget.onToolSelected(EditorTool.eraser);
                                      } else {
                                        widget.onToolSelected(EditorTool.pen);
                                      }
                                    },
                                  );
                                },
                              ),

                              // Tool: Shapes (Pops up adjacent to button)
                              Builder(
                                builder: (btnContext) => _buildToolButton(
                                  icon: widget.activeShape.icon,
                                  tooltip: 'Shapes',
                                  isSelected: widget.activeTool == EditorTool.shape,
                                  onPressed: () => _showShapePicker(btnContext),
                                ),
                              ),

                              // Tool: Text Box
                              Builder(
                                builder: (btnContext) => _buildToolButton(
                                  icon: Icons.title_rounded,
                                  tooltip: 'Text Box (Add Text)',
                                  isSelected: widget.activeTool == EditorTool.textBox,
                                  onPressed: () => widget.onToolSelected(EditorTool.textBox),
                                ),
                              ),

                              // Tool: LaTeX Box (Math Formula)
                              Builder(
                                builder: (btnContext) => _buildToolButton(
                                  icon: Icons.functions_rounded,
                                  tooltip: 'LaTeX Box (Math Formula)',
                                  isSelected: widget.activeTool == EditorTool.latexBox,
                                  onPressed: () => widget.onToolSelected(EditorTool.latexBox),
                                ),
                              ),

                              // --- Divider separating shapes/tools from settings ---
                              const Divider(height: 14, indent: 8, endIndent: 8),

                              // Style Setting: Stroke Width
                              Builder(
                                builder: (btnContext) => IconButton(
                                  icon: const Icon(Icons.line_weight_rounded, size: 20),
                                  tooltip: 'Stroke Width (${widget.activeStrokeWidth.toStringAsFixed(1)} pt)',
                                  onPressed: () => _showStrokeWidthPicker(btnContext),
                                ),
                              ),

                              // Style Setting: Font Size
                              Builder(
                                builder: (btnContext) => IconButton(
                                  icon: const Icon(Icons.format_size_rounded, size: 20),
                                  tooltip: 'Font Size (${widget.activeFontSize.toInt()} pt)',
                                  onPressed: () => _showFontSizePicker(btnContext),
                                ),
                              ),

                              // Style Setting: Color Swatch
                              Builder(
                                builder: (btnContext) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: GestureDetector(
                                    onTap: () => _showColorPicker(btnContext),
                                    child: Container(
                                      width: 26,
                                      height: 26,
                                      decoration: BoxDecoration(
                                        color: widget.activeColor,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 2),
                                        boxShadow: const [
                                          BoxShadow(color: Colors.black26, blurRadius: 3),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // --- Divider separating style settings from actions ---
                              const Divider(height: 14, indent: 8, endIndent: 8),

                              // Stylus Only Mode Toggle (Palm Rejection)
                              IconButton(
                                icon: Icon(
                                  widget.stylusOnlyMode
                                      ? Icons.do_not_touch_rounded
                                      : Icons.touch_app_rounded,
                                  size: 20,
                                  color: widget.stylusOnlyMode ? Colors.purple : Colors.grey,
                                ),
                                tooltip: widget.stylusOnlyMode
                                    ? 'Palm Rejection ON (Stylus Only)'
                                    : 'Palm Rejection OFF (Touch + Stylus)',
                                onPressed: () =>
                                    widget.onStylusOnlyModeToggled(!widget.stylusOnlyMode),
                              ),

                              // Undo Button
                              IconButton(
                                icon: const Icon(Icons.undo_rounded, size: 20),
                                tooltip: 'Undo',
                                onPressed: widget.canUndo ? widget.onUndo : null,
                              ),

                              // Page Management Button
                              IconButton(
                                icon: const Icon(Icons.note_add_outlined, size: 20),
                                tooltip: 'Manage Pages (Add/Delete)',
                                onPressed: widget.onManagePages,
                              ),

                              // Save Button
                              IconButton(
                                icon: _isSavingToolbar
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : Icon(
                                        _showSaveSuccess
                                            ? Icons.check_circle_rounded
                                            : Icons.save_rounded,
                                        size: 20,
                                        color: _showSaveSuccess
                                            ? Colors.green
                                            : theme.colorScheme.primary,
                                      ),
                                tooltip: _showSaveSuccess
                                    ? 'Saved!'
                                    : 'Save to Original File',
                                onPressed: _isSavingToolbar
                                    ? null
                                    : () async {
                                        setState(() {
                                          _isSavingToolbar = true;
                                        });
                                        try {
                                          await Future.sync(() => widget.onSave());
                                          if (mounted) {
                                            setState(() {
                                              _isSavingToolbar = false;
                                              _showSaveSuccess = true;
                                            });
                                            Future.delayed(
                                                const Duration(milliseconds: 1800), () {
                                              if (mounted) {
                                                setState(() => _showSaveSuccess = false);
                                              }
                                            });
                                          }
                                        } catch (_) {
                                          if (mounted) {
                                            setState(() => _isSavingToolbar = false);
                                          }
                                        }
                                      },
                              ),

                              const Divider(height: 12, indent: 8, endIndent: 8),

                              // Collapse Button
                              IconButton(
                                icon: const Icon(Icons.close_fullscreen_rounded, size: 16),
                                tooltip: 'Minimize',
                                onPressed: () {
                                  setState(() => _isCollapsed = true);
                                  widget.onCollapsedChanged?.call(true);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Bottom Drag Handle (isolated gesture recognizer)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: _handlePanUpdate,
                      onPanEnd: (d) => _handlePanEnd(d, toolbarWidth, screenSize),
                      child: Container(
                        width: toolbarWidth,
                        height: 18,
                        alignment: Alignment.center,
                        color: Colors.transparent,
                        child: Container(
                          width: 20,
                          height: 3,
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String tooltip,
    required bool isSelected,
    required VoidCallback onPressed,
    Color? indicatorDotColor,
  }) {
    final theme = Theme.of(context);
    return Stack(
      alignment: Alignment.topRight,
      children: [
        IconButton(
          icon: Icon(icon, size: 20),
          tooltip: tooltip,
          style: isSelected
              ? IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                )
              : null,
          onPressed: onPressed,
        ),
        if (indicatorDotColor != null)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: indicatorDotColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: indicatorDotColor.withValues(alpha: 0.45),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
