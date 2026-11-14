// ignore_for_file: implementation_imports
import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/io/pdf_cross_table.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/pages/pdf_page.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/pages/pdf_page_layer.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_array.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_dictionary.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_name.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_number.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_stream.dart';
import '../annotation_persistence_codec.dart';

class PagePreDrawSnapshot {
  final Set<PdfStream> streams;
  final Map<String, Set<String>> resourceKeys;

  const PagePreDrawSnapshot({
    required this.streams,
    required this.resourceKeys,
  });
}

class PdfEditableLayerHelper {
  PdfEditableLayerHelper._();

  static const List<String> _resourceSubDictNames = [
    'Font',
    'ExtGState',
    'XObject',
    'ColorSpace',
    'Pattern',
    'Shading',
    'Properties',
  ];

  static PdfDictionary? _derefResourcesDict(PdfPageHelper pageHelper) {
    final dict = pageHelper.dictionary;
    if (dict == null || !dict.containsKey(PdfName('Resources'))) {
      return null;
    }
    final raw = PdfCrossTable.dereference(dict[PdfName('Resources')]);
    return raw is PdfDictionary ? raw : null;
  }

  /// Captures existing content stream identities and resource keys for every page
  /// before drawing annotations so Syncfusion's wrapper streams and newly created
  /// annotation resources can be tagged accurately and stripped cleanly on reopen.
  static Map<int, PagePreDrawSnapshot> capturePreDrawSnapshots(
    sf.PdfDocument doc,
  ) {
    final result = <int, PagePreDrawSnapshot>{};
    for (int p = 0; p < doc.pages.count; p++) {
      final pageHelper = PdfPageHelper.getHelper(doc.pages[p]);
      final streams = Set<PdfStream>.identity();
      if (pageHelper.dictionary?.containsKey(PdfName('Contents')) == true) {
        final contents = pageHelper.contents;
        for (int i = 0; i < contents.count; i++) {
          final deref = PdfCrossTable.dereference(contents[i]);
          if (deref is PdfStream) {
            streams.add(deref);
          }
        }
      }

      final resKeys = <String, Set<String>>{};
      final resDict = _derefResourcesDict(pageHelper);
      if (resDict != null) {
        for (final subName in _resourceSubDictNames) {
          final subRaw = PdfCrossTable.dereference(resDict[PdfName(subName)]);
          if (subRaw is PdfDictionary && subRaw.items != null) {
            final keys = <String>{};
            for (final k in subRaw.items!.keys) {
              if (k?.name != null) {
                keys.add(k!.name!);
              }
            }
            if (keys.isNotEmpty) {
              resKeys[subName] = keys;
            }
          }
        }
      }

      result[p] = PagePreDrawSnapshot(
        streams: streams,
        resourceKeys: resKeys,
      );
    }
    return result;
  }

  /// Tags all page streams created after [snapshot] (Syncfusion's inserted `q`/`Q`
  /// wrapper streams and our annotation layer stream) with `PdfreorAnnV1`, and
  /// records any newly created `/Resources` keys inside `PdfreorAnnRes` on the
  /// annotation stream so stripping leaves zero resource or wrapper bloat.
  static void tagAddedPageArtifacts(
    sf.PdfPage page,
    PagePreDrawSnapshot? snapshot,
  ) {
    final layer = page.defaultLayer;
    final element = PdfPageLayerHelper.getHelper(layer).element;
    final pageHelper = PdfPageHelper.getHelper(page);

    if (snapshot != null &&
        pageHelper.dictionary?.containsKey(PdfName('Contents')) == true) {
      final contents = pageHelper.contents;
      for (int i = 0; i < contents.count; i++) {
        final deref = PdfCrossTable.dereference(contents[i]);
        if (deref is PdfStream && !snapshot.streams.contains(deref)) {
          deref[PdfName(kPdfreorStreamMarkerKey)] = PdfNumber(1);
        }
      }
    }

    if (element is PdfStream) {
      element[PdfName(kPdfreorStreamMarkerKey)] = PdfNumber(1);

      if (snapshot != null) {
        final resDict = _derefResourcesDict(pageHelper);
        if (resDict != null) {
          final addedResDict = PdfDictionary();
          for (final subName in _resourceSubDictNames) {
            final subRaw = PdfCrossTable.dereference(resDict[PdfName(subName)]);
            if (subRaw is PdfDictionary && subRaw.items != null) {
              final priorKeys = snapshot.resourceKeys[subName] ?? const <String>{};
              final addedArr = PdfArray();
              for (final k in subRaw.items!.keys) {
                final name = k?.name;
                if (name != null && !priorKeys.contains(name)) {
                  addedArr.add(PdfName(name));
                }
              }
              if (addedArr.count > 0) {
                addedResDict[PdfName(subName)] = addedArr;
              }
            }
          }
          if (addedResDict.count > 0) {
            element[PdfName(kPdfreorStreamResourcesKey)] = addedResDict;
          }
        }
      }
    }
  }

  static bool stripAnnotationStreams(sf.PdfDocument doc) {
    bool strippedAny = false;
    for (int p = 0; p < doc.pages.count; p++) {
      final page = doc.pages[p];
      final pageHelper = PdfPageHelper.getHelper(page);
      if (pageHelper.dictionary?.containsKey(PdfName('Contents')) != true) {
        continue;
      }
      final PdfArray contents = pageHelper.contents;
      final resDict = _derefResourcesDict(pageHelper);
      bool pageModified = false;
      for (int i = contents.count - 1; i >= 0; i--) {
        final raw = contents[i];
        final deref = raw is PdfStream ? raw : PdfCrossTable.dereference(raw);
        if (deref is PdfStream && deref.containsKey(PdfName(kPdfreorStreamMarkerKey))) {
          if (resDict != null && deref.containsKey(PdfName(kPdfreorStreamResourcesKey))) {
            final annResRaw =
                PdfCrossTable.dereference(deref[PdfName(kPdfreorStreamResourcesKey)]);
            if (annResRaw is PdfDictionary && annResRaw.items != null) {
              for (final entry in annResRaw.items!.entries) {
                final subKey = entry.key;
                if (subKey == null) continue;
                final subResRaw = PdfCrossTable.dereference(resDict[subKey]);
                final addedArr = PdfCrossTable.dereference(entry.value);
                if (subResRaw is PdfDictionary && addedArr is PdfArray) {
                  for (int j = 0; j < addedArr.count; j++) {
                    final resName = PdfCrossTable.dereference(addedArr[j]);
                    if (resName is PdfName && subResRaw.containsKey(resName)) {
                      subResRaw.remove(resName);
                    }
                  }
                  if (subResRaw.count == 0) {
                    resDict.remove(subKey);
                  }
                }
              }
            }
          }
          contents.removeAt(i);
          pageModified = true;
          strippedAny = true;
        }
      }
      if (pageModified) {
        contents.changed = true;
        resDict?.changed = true;
        pageHelper.dictionary?.changed = true;
      }
    }
    return strippedAny;
  }

  static Uint8List? extractAnnotationAttachmentBytes(sf.PdfDocument doc) {
    try {
      final attachments = doc.attachments;
      for (int i = 0; i < attachments.count; i++) {
        final att = attachments[i];
        if (att.fileName == kPdfreorAnnotationAttachmentName) {
          return Uint8List.fromList(att.data);
        }
      }
    } catch (_) {}
    return null;
  }

  static bool removeAnnotationAttachments(sf.PdfDocument doc) {
    bool removedAny = false;
    try {
      final attachments = doc.attachments;
      for (int i = attachments.count - 1; i >= 0; i--) {
        final att = attachments[i];
        if (att.fileName == kPdfreorAnnotationAttachmentName) {
          attachments.removeAt(i);
          removedAny = true;
        }
      }
    } catch (_) {}
    return removedAny;
  }

  static void writeAnnotationAttachment(sf.PdfDocument doc, Uint8List gzBytes) {
    removeAnnotationAttachments(doc);
    doc.attachments.add(
      sf.PdfAttachment(
        kPdfreorAnnotationAttachmentName,
        gzBytes,
        description: 'PDFREOR editable annotations payload',
        mimeType: 'application/gzip',
      ),
    );
  }
}
