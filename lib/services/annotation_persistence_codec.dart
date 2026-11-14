import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/editor_models.dart';
import 'export/pdf_export_geometry.dart';
import 'export/pdf_export_models.dart';

const String kPdfreorAnnotationAttachmentName = 'pdfreor_annotations_v1.json.gz';
const String kPdfreorStreamMarkerKey = 'PdfreorAnnV1';
const String kPdfreorStreamResourcesKey = 'PdfreorAnnRes';
const int kAnnotationSchemaVersion = 1;

class PersistedStrokeDto {
  final String id;
  final int pageIndex;
  final int colorArgb;
  final double strokeWidth;
  final List<double> pointsFlat;

  const PersistedStrokeDto({
    required this.id,
    required this.pageIndex,
    required this.colorArgb,
    required this.strokeWidth,
    required this.pointsFlat,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'p': pageIndex,
        'c': colorArgb,
        'w': strokeWidth,
        'pts': pointsFlat,
      };

  static PersistedStrokeDto? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final p = (raw['p'] as num?)?.toInt();
    final c = (raw['c'] as num?)?.toInt();
    final w = (raw['w'] as num?)?.toDouble();
    final ptsRaw = raw['pts'];
    if (p == null || c == null || w == null || ptsRaw is! List) return null;
    final flat = <double>[];
    for (final v in ptsRaw) {
      if (v is! num) return null;
      flat.add(v.toDouble());
    }
    if (flat.length < 3 || flat.length % 3 != 0) return null;
    return PersistedStrokeDto(
      id: (raw['id'] as String?) ?? nextAnnotationId('st'),
      pageIndex: p,
      colorArgb: c,
      strokeWidth: w.clamp(0.25, 200.0).toDouble(),
      pointsFlat: flat,
    );
  }
}

class PersistedShapeDto {
  final String id;
  final int pageIndex;
  final int typeIndex;
  final double startX;
  final double startY;
  final double endX;
  final double endY;
  final int colorArgb;
  final double strokeWidth;

  const PersistedShapeDto({
    required this.id,
    required this.pageIndex,
    required this.typeIndex,
    required this.startX,
    required this.startY,
    required this.endX,
    required this.endY,
    required this.colorArgb,
    required this.strokeWidth,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'p': pageIndex,
        't': typeIndex,
        'sx': startX,
        'sy': startY,
        'ex': endX,
        'ey': endY,
        'c': colorArgb,
        'w': strokeWidth,
      };

  static PersistedShapeDto? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final p = (raw['p'] as num?)?.toInt();
    final t = (raw['t'] as num?)?.toInt();
    final sx = (raw['sx'] as num?)?.toDouble();
    final sy = (raw['sy'] as num?)?.toDouble();
    final ex = (raw['ex'] as num?)?.toDouble();
    final ey = (raw['ey'] as num?)?.toDouble();
    final c = (raw['c'] as num?)?.toInt();
    final w = (raw['w'] as num?)?.toDouble();
    if (p == null ||
        t == null ||
        sx == null ||
        sy == null ||
        ex == null ||
        ey == null ||
        c == null ||
        w == null) {
      return null;
    }
    if (t < 0 || t >= ShapeType.values.length) return null;
    return PersistedShapeDto(
      id: (raw['id'] as String?) ?? nextAnnotationId('sh'),
      pageIndex: p,
      typeIndex: t,
      startX: sx,
      startY: sy,
      endX: ex,
      endY: ey,
      colorArgb: c,
      strokeWidth: w.clamp(0.25, 200.0).toDouble(),
    );
  }
}

class PersistedTextBoxDto {
  final String id;
  final int pageIndex;
  final String text;
  final double posX;
  final double posY;
  final int colorArgb;
  final double fontSize;
  final double? width;
  final bool isLatex;

  const PersistedTextBoxDto({
    required this.id,
    required this.pageIndex,
    required this.text,
    required this.posX,
    required this.posY,
    required this.colorArgb,
    required this.fontSize,
    required this.width,
    required this.isLatex,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'p': pageIndex,
        'txt': text,
        'x': posX,
        'y': posY,
        'c': colorArgb,
        'fs': fontSize,
        if (width != null) 'w': width,
        if (isLatex) 'lx': true,
      };

  static PersistedTextBoxDto? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final p = (raw['p'] as num?)?.toInt();
    final txt = raw['txt'];
    final x = (raw['x'] as num?)?.toDouble();
    final y = (raw['y'] as num?)?.toDouble();
    final c = (raw['c'] as num?)?.toInt();
    final fs = (raw['fs'] as num?)?.toDouble();
    final w = (raw['w'] as num?)?.toDouble();
    if (p == null || txt is! String || x == null || y == null || c == null || fs == null) {
      return null;
    }
    return PersistedTextBoxDto(
      id: (raw['id'] as String?) ?? nextAnnotationId('tb'),
      pageIndex: p,
      text: txt,
      posX: x,
      posY: y,
      colorArgb: c,
      fontSize: fs.clamp(4.0, 200.0).toDouble(),
      width: w != null && w > 0 ? w : null,
      isLatex: raw['lx'] == true,
    );
  }
}

class PersistedImageDto {
  final String id;
  final int pageIndex;
  final double posX;
  final double posY;
  final double width;
  final double height;
  final String imageKey;

  const PersistedImageDto({
    required this.id,
    required this.pageIndex,
    required this.posX,
    required this.posY,
    required this.width,
    required this.height,
    required this.imageKey,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'p': pageIndex,
        'x': posX,
        'y': posY,
        'w': width,
        'h': height,
        'k': imageKey,
      };

  static PersistedImageDto? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final p = (raw['p'] as num?)?.toInt();
    final x = (raw['x'] as num?)?.toDouble();
    final y = (raw['y'] as num?)?.toDouble();
    final w = (raw['w'] as num?)?.toDouble();
    final h = (raw['h'] as num?)?.toDouble();
    final k = raw['k'];
    if (p == null || x == null || y == null || w == null || h == null || k is! String) {
      return null;
    }
    if (w <= 0 || h <= 0 || k.isEmpty) return null;
    return PersistedImageDto(
      id: (raw['id'] as String?) ?? nextAnnotationId('im'),
      pageIndex: p,
      posX: x,
      posY: y,
      width: w,
      height: h,
      imageKey: k,
    );
  }
}

class PersistedTextAnnotationDto {
  final String id;
  final int pageIndex;
  final int typeIndex;
  final int colorArgb;
  final List<double> rectsFlat;

  const PersistedTextAnnotationDto({
    required this.id,
    required this.pageIndex,
    required this.typeIndex,
    required this.colorArgb,
    required this.rectsFlat,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'p': pageIndex,
        't': typeIndex,
        'c': colorArgb,
        'r': rectsFlat,
      };

  static PersistedTextAnnotationDto? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final p = (raw['p'] as num?)?.toInt();
    final t = (raw['t'] as num?)?.toInt();
    final c = (raw['c'] as num?)?.toInt();
    final rRaw = raw['r'];
    if (p == null || t == null || c == null || rRaw is! List) return null;
    if (t < 0 || t >= TextAnnotationType.values.length) return null;
    final flat = <double>[];
    for (final v in rRaw) {
      if (v is! num) return null;
      flat.add(v.toDouble());
    }
    if (flat.isEmpty || flat.length % 4 != 0) return null;
    return PersistedTextAnnotationDto(
      id: (raw['id'] as String?) ?? nextAnnotationId('ta'),
      pageIndex: p,
      typeIndex: t,
      colorArgb: c,
      rectsFlat: flat,
    );
  }
}

class RestoredAnnotationModels {
  final List<DrawingStroke> strokes;
  final List<DrawnShape> shapes;
  final List<DrawnTextBox> textBoxes;
  final List<DrawnImage> images;
  final List<DrawnTextAnnotation> textAnnotations;

  const RestoredAnnotationModels({
    required this.strokes,
    required this.shapes,
    required this.textBoxes,
    required this.images,
    required this.textAnnotations,
  });
}

class PersistedAnnotationsBundle {
  final int schemaVersion;
  final int pageCount;
  final List<PersistedStrokeDto> strokes;
  final List<PersistedShapeDto> shapes;
  final List<PersistedTextBoxDto> textBoxes;
  final List<PersistedImageDto> images;
  final List<PersistedTextAnnotationDto> textAnnotations;
  final Map<String, Uint8List> imagePool;

  const PersistedAnnotationsBundle({
    this.schemaVersion = kAnnotationSchemaVersion,
    required this.pageCount,
    this.strokes = const [],
    this.shapes = const [],
    this.textBoxes = const [],
    this.images = const [],
    this.textAnnotations = const [],
    this.imagePool = const {},
  });

  bool get isEmpty =>
      strokes.isEmpty &&
      shapes.isEmpty &&
      textBoxes.isEmpty &&
      images.isEmpty &&
      textAnnotations.isEmpty;

  Map<String, dynamic> toJson() => {
        'v': schemaVersion,
        'pc': pageCount,
        if (strokes.isNotEmpty) 'st': [for (final s in strokes) s.toJson()],
        if (shapes.isNotEmpty) 'sh': [for (final s in shapes) s.toJson()],
        if (textBoxes.isNotEmpty) 'tb': [for (final t in textBoxes) t.toJson()],
        if (images.isNotEmpty) 'im': [for (final im in images) im.toJson()],
        if (textAnnotations.isNotEmpty)
          'ta': [for (final ta in textAnnotations) ta.toJson()],
        if (imagePool.isNotEmpty)
          'imgPool': {
            for (final entry in imagePool.entries)
              entry.key: base64Encode(entry.value),
          },
      };

  static PersistedAnnotationsBundle? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final v = (raw['v'] as num?)?.toInt();
    if (v == null || v < 1 || v > kAnnotationSchemaVersion) return null;
    final pc = (raw['pc'] as num?)?.toInt() ?? 0;

    final strokes = <PersistedStrokeDto>[];
    final stList = raw['st'];
    if (stList is List) {
      for (final item in stList) {
        final dto = PersistedStrokeDto.fromJson(item);
        if (dto != null) strokes.add(dto);
      }
    }

    final shapes = <PersistedShapeDto>[];
    final shList = raw['sh'];
    if (shList is List) {
      for (final item in shList) {
        final dto = PersistedShapeDto.fromJson(item);
        if (dto != null) shapes.add(dto);
      }
    }

    final textBoxes = <PersistedTextBoxDto>[];
    final tbList = raw['tb'];
    if (tbList is List) {
      for (final item in tbList) {
        final dto = PersistedTextBoxDto.fromJson(item);
        if (dto != null) textBoxes.add(dto);
      }
    }

    final imagePool = <String, Uint8List>{};
    final poolRaw = raw['imgPool'];
    if (poolRaw is Map) {
      for (final entry in poolRaw.entries) {
        final k = entry.key;
        final val = entry.value;
        if (k is String && val is String && val.isNotEmpty) {
          try {
            imagePool[k] = Uint8List.fromList(base64Decode(val));
          } catch (_) {}
        }
      }
    }

    final images = <PersistedImageDto>[];
    final imList = raw['im'];
    if (imList is List) {
      for (final item in imList) {
        final dto = PersistedImageDto.fromJson(item);
        if (dto != null && imagePool.containsKey(dto.imageKey)) {
          images.add(dto);
        }
      }
    }

    final textAnnotations = <PersistedTextAnnotationDto>[];
    final taList = raw['ta'];
    if (taList is List) {
      for (final item in taList) {
        final dto = PersistedTextAnnotationDto.fromJson(item);
        if (dto != null) textAnnotations.add(dto);
      }
    }

    return PersistedAnnotationsBundle(
      schemaVersion: v,
      pageCount: pc,
      strokes: strokes,
      shapes: shapes,
      textBoxes: textBoxes,
      images: images,
      textAnnotations: textAnnotations,
      imagePool: imagePool,
    );
  }

  /// Converts persisted PDF-point coordinates into the active viewer's document coordinates.
  RestoredAnnotationModels toModelLists(
    List<Rect> currentPageDocBounds,
    List<Size> currentPdfPageSizes,
  ) {
    final validCount = currentPageDocBounds.length < currentPdfPageSizes.length
        ? currentPageDocBounds.length
        : currentPdfPageSizes.length;

    bool validPage(int pageIndex) {
      if (pageIndex < 0 || pageIndex >= validCount) return false;
      final b = currentPageDocBounds[pageIndex];
      final s = currentPdfPageSizes[pageIndex];
      return b.width > 0 && b.height > 0 && s.width > 0 && s.height > 0;
    }

    void withPageTransform(
      int pageIndex,
      void Function(Rect b, double invX, double invY) fn,
    ) {
      if (!validPage(pageIndex)) return;
      final b = currentPageDocBounds[pageIndex];
      final s = currentPdfPageSizes[pageIndex];
      fn(b, b.width / s.width, b.height / s.height);
    }

    final outStrokes = <DrawingStroke>[];
    for (final dto in strokes) {
      withPageTransform(dto.pageIndex, (b, invX, invY) {
        final pts = <StrokePoint>[];
        for (int i = 0; i + 2 < dto.pointsFlat.length; i += 3) {
          pts.add(StrokePoint(
            offset: Offset(
              b.left + dto.pointsFlat[i] * invX,
              b.top + dto.pointsFlat[i + 1] * invY,
            ),
            pressure: dto.pointsFlat[i + 2].clamp(0.05, 2.0).toDouble(),
          ));
        }
        if (pts.isEmpty) return;
        outStrokes.add(DrawingStroke(
          id: dto.id,
          points: pts,
          color: Color(dto.colorArgb),
          strokeWidth: (dto.strokeWidth * invX).clamp(0.5, 120.0).toDouble(),
          pageNumber: dto.pageIndex + 1,
        ));
      });
    }

    final outShapes = <DrawnShape>[];
    for (final dto in shapes) {
      if (dto.typeIndex < 0 || dto.typeIndex >= ShapeType.values.length) continue;
      withPageTransform(dto.pageIndex, (b, invX, invY) {
        outShapes.add(DrawnShape(
          id: dto.id,
          type: ShapeType.values[dto.typeIndex],
          start: Offset(b.left + dto.startX * invX, b.top + dto.startY * invY),
          end: Offset(b.left + dto.endX * invX, b.top + dto.endY * invY),
          color: Color(dto.colorArgb),
          strokeWidth: (dto.strokeWidth * invX).clamp(0.5, 120.0).toDouble(),
          pageNumber: dto.pageIndex + 1,
        ));
      });
    }

    final outTextBoxes = <DrawnTextBox>[];
    for (final dto in textBoxes) {
      withPageTransform(dto.pageIndex, (b, invX, invY) {
        outTextBoxes.add(DrawnTextBox(
          id: dto.id,
          text: dto.text,
          position: Offset(b.left + dto.posX * invX, b.top + dto.posY * invY),
          color: Color(dto.colorArgb),
          fontSize: (dto.fontSize * invX).clamp(6.0, 120.0).toDouble(),
          pageNumber: dto.pageIndex + 1,
          width: dto.width != null ? dto.width! * invX : null,
          isLatex: dto.isLatex,
        ));
      });
    }

    final outImages = <DrawnImage>[];
    for (final dto in images) {
      final bytes = imagePool[dto.imageKey];
      if (bytes == null || bytes.isEmpty) continue;
      withPageTransform(dto.pageIndex, (b, invX, invY) {
        outImages.add(DrawnImage(
          id: dto.id,
          imageBytes: bytes,
          position: Offset(b.left + dto.posX * invX, b.top + dto.posY * invY),
          width: dto.width * invX,
          height: dto.height * invY,
          pageNumber: dto.pageIndex + 1,
        ));
      });
    }

    final outTextAnnotations = <DrawnTextAnnotation>[];
    for (final dto in textAnnotations) {
      if (dto.typeIndex < 0 || dto.typeIndex >= TextAnnotationType.values.length) {
        continue;
      }
      withPageTransform(dto.pageIndex, (b, invX, invY) {
        final rects = <Rect>[];
        for (int i = 0; i + 3 < dto.rectsFlat.length; i += 4) {
          rects.add(Rect.fromLTWH(
            b.left + dto.rectsFlat[i] * invX,
            b.top + dto.rectsFlat[i + 1] * invY,
            dto.rectsFlat[i + 2] * invX,
            dto.rectsFlat[i + 3] * invY,
          ));
        }
        if (rects.isEmpty) return;
        outTextAnnotations.add(DrawnTextAnnotation(
          id: dto.id,
          type: TextAnnotationType.values[dto.typeIndex],
          rects: rects,
          color: Color(dto.colorArgb),
          pageNumber: dto.pageIndex + 1,
        ));
      });
    }

    return RestoredAnnotationModels(
      strokes: outStrokes,
      shapes: outShapes,
      textBoxes: outTextBoxes,
      images: outImages,
      textAnnotations: outTextAnnotations,
    );
  }
}

class AnnotationPersistenceCodec {
  AnnotationPersistenceCodec._();

  static PersistedAnnotationsBundle buildBundleFromExportPayload({
    required ExportJobPayload payload,
    required List<Rect> origPageBounds,
    required List<int> oldToNewPageIdx,
    required List<(double w, double h)> postEditPageSizes,
  }) {
    final origCount = origPageBounds.length;
    final newCount = postEditPageSizes.length;

    bool mapPage(int origIdx, void Function(int newIdx, Rect bounds, double sx, double sy) fn) {
      if (origIdx < 0 || origIdx >= origCount) return false;
      final newIdx = oldToNewPageIdx[origIdx];
      if (newIdx < 0 || newIdx >= newCount) return false;
      final b = origPageBounds[origIdx];
      if (b.width <= 0 || b.height <= 0) return false;
      final (pw, ph) = postEditPageSizes[newIdx];
      final sx = pw / b.width;
      final sy = ph / b.height;
      fn(newIdx, b, sx, sy);
      return true;
    }

    final persistedStrokes = <PersistedStrokeDto>[];
    for (int i = 0; i < payload.strokes.length; i++) {
      final st = payload.strokes[i];
      if (st.points.isEmpty) continue;
      final origIdx = findOrigPageIndex(origPageBounds, st.points.first.$2);
      mapPage(origIdx, (newIdx, b, sx, sy) {
        final flat = <double>[];
        for (final (px, py, pr) in st.points) {
          flat.add(roundPdfCoord((px - b.left) * sx));
          flat.add(roundPdfCoord((py - b.top) * sy));
          flat.add((pr * 100.0).round() / 100.0);
        }
        persistedStrokes.add(PersistedStrokeDto(
          id: st.id ?? 'st_$i',
          pageIndex: newIdx,
          colorArgb: st.colorArgb,
          strokeWidth: roundPdfCoord(st.strokeWidth * sx),
          pointsFlat: flat,
        ));
      });
    }

    final persistedShapes = <PersistedShapeDto>[];
    for (int i = 0; i < payload.shapes.length; i++) {
      final sh = payload.shapes[i];
      final origIdx = findOrigPageIndex(origPageBounds, (sh.startY + sh.endY) * 0.5);
      mapPage(origIdx, (newIdx, b, sx, sy) {
        persistedShapes.add(PersistedShapeDto(
          id: sh.id ?? 'sh_$i',
          pageIndex: newIdx,
          typeIndex: sh.type.index,
          startX: roundPdfCoord((sh.startX - b.left) * sx),
          startY: roundPdfCoord((sh.startY - b.top) * sy),
          endX: roundPdfCoord((sh.endX - b.left) * sx),
          endY: roundPdfCoord((sh.endY - b.top) * sy),
          colorArgb: sh.colorArgb,
          strokeWidth: roundPdfCoord(sh.strokeWidth * sx),
        ));
      });
    }

    final persistedTextBoxes = <PersistedTextBoxDto>[];
    for (final tb in payload.textBoxes) {
      if (tb.text.trim().isEmpty) continue;
      final origIdx = findOrigPageIndex(origPageBounds, tb.posY);
      mapPage(origIdx, (newIdx, b, sx, sy) {
        persistedTextBoxes.add(PersistedTextBoxDto(
          id: tb.id ?? 'tb_${tb.index}',
          pageIndex: newIdx,
          text: tb.text,
          posX: roundPdfCoord((tb.posX - b.left) * sx),
          posY: roundPdfCoord((tb.posY - b.top) * sy),
          colorArgb: tb.colorArgb,
          fontSize: (tb.fontSize * sx * 100.0).round() / 100.0,
          width: tb.width != null ? roundPdfCoord(tb.width! * sx) : null,
          isLatex: tb.isLatex,
        ));
      });
    }

    final persistedImages = <PersistedImageDto>[];
    final imagePool = <String, Uint8List>{};
    for (int i = 0; i < payload.images.length; i++) {
      final im = payload.images[i];
      final optBytes = payload.optimizedImages[im.cacheKey];
      if (optBytes == null || optBytes.isEmpty) continue;
      final origIdx = findOrigPageIndex(origPageBounds, im.posY);
      mapPage(origIdx, (newIdx, b, sx, sy) {
        imagePool.putIfAbsent(im.cacheKey, () => optBytes);
        persistedImages.add(PersistedImageDto(
          id: im.id ?? 'im_$i',
          pageIndex: newIdx,
          posX: roundPdfCoord((im.posX - b.left) * sx),
          posY: roundPdfCoord((im.posY - b.top) * sy),
          width: roundPdfCoord(im.width * sx),
          height: roundPdfCoord(im.height * sy),
          imageKey: im.cacheKey,
        ));
      });
    }

    final persistedTextAnns = <PersistedTextAnnotationDto>[];
    for (int i = 0; i < payload.textAnnotations.length; i++) {
      final ta = payload.textAnnotations[i];
      if (ta.rects.isEmpty) continue;
      final origIdx = ta.pageNumber - 1;
      mapPage(origIdx, (newIdx, b, sx, sy) {
        final flat = <double>[];
        for (final (l, t, w, h) in ta.rects) {
          flat.add(roundPdfCoord((l - b.left) * sx));
          flat.add(roundPdfCoord((t - b.top) * sy));
          flat.add(roundPdfCoord(w * sx));
          flat.add(roundPdfCoord(h * sy));
        }
        persistedTextAnns.add(PersistedTextAnnotationDto(
          id: ta.id ?? 'ta_$i',
          pageIndex: newIdx,
          typeIndex: ta.type.index,
          colorArgb: ta.colorArgb,
          rectsFlat: flat,
        ));
      });
    }

    return PersistedAnnotationsBundle(
      schemaVersion: kAnnotationSchemaVersion,
      pageCount: newCount,
      strokes: persistedStrokes,
      shapes: persistedShapes,
      textBoxes: persistedTextBoxes,
      images: persistedImages,
      textAnnotations: persistedTextAnns,
      imagePool: imagePool,
    );
  }

  static Uint8List encodeGzip(PersistedAnnotationsBundle bundle) {
    final jsonStr = jsonEncode(bundle.toJson());
    return Uint8List.fromList(gzip.encode(utf8.encode(jsonStr)));
  }

  static PersistedAnnotationsBundle? decodeGzip(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    try {
      final decompressed = gzip.decode(bytes);
      final jsonStr = utf8.decode(decompressed);
      final decoded = jsonDecode(jsonStr);
      return PersistedAnnotationsBundle.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }
}
