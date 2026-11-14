import 'dart:typed_data';
import '../../models/editor_models.dart';
import '../editor_settings_service.dart';

class ExportTextAnnotationDto {
  final String? id;
  final TextAnnotationType type;
  final List<(double l, double t, double w, double h)> rects;
  final int colorArgb;
  final int pageNumber;

  const ExportTextAnnotationDto({
    this.id,
    required this.type,
    required this.rects,
    required this.colorArgb,
    required this.pageNumber,
  });
}

class ExportStrokeDto {
  final String? id;
  final List<(double x, double y, double pressure)> points;
  final int colorArgb;
  final double strokeWidth;

  const ExportStrokeDto({
    this.id,
    required this.points,
    required this.colorArgb,
    required this.strokeWidth,
  });
}

class ExportShapeDto {
  final String? id;
  final ShapeType type;
  final double startX;
  final double startY;
  final double endX;
  final double endY;
  final int colorArgb;
  final double strokeWidth;

  const ExportShapeDto({
    this.id,
    required this.type,
    required this.startX,
    required this.startY,
    required this.endX,
    required this.endY,
    required this.colorArgb,
    required this.strokeWidth,
  });
}

class ExportTextBoxDto {
  final String? id;
  final int index;
  final String text;
  final double posX;
  final double posY;
  final double fontSize;
  final int colorArgb;
  final double? width;
  final bool isLatex;
  final String? preRasterKey;

  const ExportTextBoxDto({
    this.id,
    required this.index,
    required this.text,
    required this.posX,
    required this.posY,
    required this.fontSize,
    required this.colorArgb,
    required this.width,
    required this.isLatex,
    this.preRasterKey,
  });
}

class ExportImageDto {
  final String? id;
  final double posX;
  final double posY;
  final double width;
  final double height;
  final String cacheKey;

  const ExportImageDto({
    this.id,
    required this.posX,
    required this.posY,
    required this.width,
    required this.height,
    required this.cacheKey,
  });
}

class RasterizedBitmapDto {
  final Uint8List bytes;
  final double offsetX;
  final double offsetY;
  final double width;
  final double height;

  const RasterizedBitmapDto({
    required this.bytes,
    required this.offsetX,
    required this.offsetY,
    required this.width,
    required this.height,
  });
}

class FallbackRequest {
  final String key;
  final String text;
  final int colorArgb;
  final double fontSize;
  final double maxWidth;

  const FallbackRequest({
    required this.key,
    required this.text,
    required this.colorArgb,
    required this.fontSize,
    required this.maxWidth,
  });
}

class ExportJobPayload {
  final Uint8List baseBytes;
  final double viewportWidth;
  final AppFontFamily textBoxFont;
  final List<int> deletedZeroIndexedPages;
  final int addedPagesCount;
  final double pageSpacing;
  final List<(double l, double t, double w, double h)>? pageDocBounds;
  final List<ExportTextAnnotationDto> textAnnotations;
  final List<ExportStrokeDto> strokes;
  final List<ExportShapeDto> shapes;
  final List<ExportTextBoxDto> textBoxes;
  final List<ExportImageDto> images;
  final Map<String, RasterizedBitmapDto?> preRasterizedLatex;
  final Map<String, RasterizedBitmapDto?> preRasterizedFallbacks;
  final Map<String, Uint8List> optimizedImages;
  final bool embedEditableData;

  const ExportJobPayload({
    required this.baseBytes,
    required this.viewportWidth,
    required this.textBoxFont,
    required this.deletedZeroIndexedPages,
    required this.addedPagesCount,
    required this.pageSpacing,
    required this.pageDocBounds,
    required this.textAnnotations,
    required this.strokes,
    required this.shapes,
    required this.textBoxes,
    required this.images,
    required this.preRasterizedLatex,
    required this.preRasterizedFallbacks,
    required this.optimizedImages,
    this.embedEditableData = false,
  });
}

class ExportWorkerResult {
  final Uint8List? pdfBytes;
  final List<FallbackRequest> missingFallbacks;

  const ExportWorkerResult({
    this.pdfBytes,
    this.missingFallbacks = const [],
  });
}
