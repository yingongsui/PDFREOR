import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/pdf_thumbnail_service.dart';

/// Unified async PDF thumbnail widget supporting both document covers
/// (`pageNumber == null`) and individual pages (`pageNumber != null`) with
/// stale-request guards and decoded memory caching.
class SharedPdfThumbnail extends StatefulWidget {
  final String filePath;
  final int lastModifiedMillis;
  final int? pageNumber;
  final double targetWidth;
  final int? cacheWidth;
  final BoxFit fit;
  final AlignmentGeometry alignment;
  final double spinnerSize;
  final Color? spinnerColor;
  final WidgetBuilder fallbackBuilder;

  const SharedPdfThumbnail.cover({
    super.key,
    required this.filePath,
    required this.lastModifiedMillis,
    this.cacheWidth,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
    this.spinnerSize = 18,
    this.spinnerColor,
    required this.fallbackBuilder,
  })  : pageNumber = null,
        targetWidth = 300.0;

  const SharedPdfThumbnail.page({
    super.key,
    required this.filePath,
    required this.lastModifiedMillis,
    required int this.pageNumber,
    this.targetWidth = 300.0,
    this.cacheWidth = 260,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.spinnerSize = 18,
    this.spinnerColor,
    required this.fallbackBuilder,
  });

  @override
  State<SharedPdfThumbnail> createState() => _SharedPdfThumbnailState();
}

class _SharedPdfThumbnailState extends State<SharedPdfThumbnail> {
  Uint8List? _bytes;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant SharedPdfThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath ||
        oldWidget.lastModifiedMillis != widget.lastModifiedMillis ||
        oldWidget.pageNumber != widget.pageNumber ||
        oldWidget.targetWidth != widget.targetWidth) {
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    final requestedPath = widget.filePath;
    final requestedModified = widget.lastModifiedMillis;
    final requestedPage = widget.pageNumber;
    final requestedWidth = widget.targetWidth;

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final Uint8List? bytes;
      if (requestedPage != null) {
        bytes = await PdfThumbnailService.instance.getPageThumbnail(
          requestedPath,
          requestedPage,
          lastModifiedMillis: requestedModified,
          targetWidth: requestedWidth,
        );
      } else {
        bytes = await PdfThumbnailService.instance.getThumbnail(
          requestedPath,
          lastModifiedMillis: requestedModified,
        );
      }

      if (mounted &&
          widget.filePath == requestedPath &&
          widget.lastModifiedMillis == requestedModified &&
          widget.pageNumber == requestedPage) {
        setState(() {
          _bytes = bytes;
          _isLoading = false;
          _hasError = bytes == null;
        });
      }
    } catch (_) {
      if (mounted &&
          widget.filePath == requestedPath &&
          widget.lastModifiedMillis == requestedModified &&
          widget.pageNumber == requestedPage) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: SizedBox(
          width: widget.spinnerSize,
          height: widget.spinnerSize,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: widget.spinnerColor,
          ),
        ),
      );
    }

    if (_hasError || _bytes == null) {
      return widget.fallbackBuilder(context);
    }

    return Image.memory(
      _bytes!,
      fit: widget.fit,
      alignment: widget.alignment,
      cacheWidth: widget.cacheWidth,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => widget.fallbackBuilder(context),
    );
  }
}
