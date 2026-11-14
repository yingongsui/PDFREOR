import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/editor_models.dart';
import 'toolbars/floating_toolbar_popups.dart';

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
  Timer? _saveFeedbackTimer;

  void _handlePanUpdate(DragUpdateDetails details) {
    setState(() {
      _position += details.delta;
    });
  }

  void _handlePanEnd(DragEndDetails details, double toolbarWidth, Size screenSize) {
    final topMin = math.max(50.0, MediaQuery.paddingOf(context).top + 8.0);
    final bottomMax = math.max(topMin, screenSize.height - 120.0 - MediaQuery.paddingOf(context).bottom);
    final clampedPos = Offset(
      _position.dx.clamp(4.0, math.max(4.0, screenSize.width - toolbarWidth - 4.0)),
      _position.dy.clamp(topMin, bottomMax),
    );
    setState(() {
      _position = clampedPos;
    });
    widget.onPositionChanged?.call(clampedPos);
  }

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition ?? const Offset(12, 100);
    _isCollapsed = widget.initialIsCollapsed;
  }

  @override
  void dispose() {
    _saveFeedbackTimer?.cancel();
    super.dispose();
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
                                  onPressed: () => FloatingToolbarPopups.showShapePicker(
                                    hostContext: context,
                                    buttonContext: btnContext,
                                    activeTool: widget.activeTool,
                                    activeShape: widget.activeShape,
                                    onToolSelected: widget.onToolSelected,
                                    onShapeSelected: widget.onShapeSelected,
                                  ),
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
                                  onPressed: () => FloatingToolbarPopups.showStrokeWidthPicker(
                                    hostContext: context,
                                    buttonContext: btnContext,
                                    activeStrokeWidth: widget.activeStrokeWidth,
                                    onStrokeWidthSelected: widget.onStrokeWidthSelected,
                                  ),
                                ),
                              ),

                              // Style Setting: Font Size
                              Builder(
                                builder: (btnContext) => IconButton(
                                  icon: const Icon(Icons.format_size_rounded, size: 20),
                                  tooltip: 'Font Size (${widget.activeFontSize.toInt()} pt)',
                                  onPressed: () => FloatingToolbarPopups.showFontSizePicker(
                                    hostContext: context,
                                    buttonContext: btnContext,
                                    activeFontSize: widget.activeFontSize,
                                    onFontSizeSelected: widget.onFontSizeSelected,
                                  ),
                                ),
                              ),

                              // Style Setting: Color Swatch
                              Builder(
                                builder: (btnContext) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: GestureDetector(
                                    onTap: () => FloatingToolbarPopups.showColorPicker(
                                      hostContext: context,
                                      buttonContext: btnContext,
                                      activeColor: widget.activeColor,
                                      onColorSelected: widget.onColorSelected,
                                    ),
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
                                            _saveFeedbackTimer?.cancel();
                                            _saveFeedbackTimer = Timer(
                                              const Duration(milliseconds: 1800),
                                              () {
                                                if (mounted) {
                                                  setState(() => _showSaveSuccess = false);
                                                }
                                              },
                                            );
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
