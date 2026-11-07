import 'dart:io';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreor/screens/pdf_viewer_screen.dart';
import 'package:pdfreor/services/reading_progress_service.dart';

void main() {
  group('ReadingProgressService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('reading_progress_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('persists and restores last visited page across service instances', () async {
      final serviceA = ReadingProgressService.forTesting();
      await serviceA.init(storageDirOverride: tempDir);

      expect(serviceA.getLastPage('/storage/books/a.pdf'), 1);

      serviceA.saveLastPage('/storage/books/a.pdf', 14);
      serviceA.saveLastPage('/storage/books/b.pdf', 5);
      serviceA.saveLastZoom('/storage/books/a.pdf', 1.75);
      expect(serviceA.getLastPage('/storage/books/a.pdf'), 14);
      expect(serviceA.getLastPage('/storage/books/b.pdf'), 5);
      expect(serviceA.getLastZoom('/storage/books/a.pdf'), 1.75);

      await serviceA.flush();

      final serviceB = ReadingProgressService.forTesting();
      await serviceB.init(storageDirOverride: tempDir);
      expect(serviceB.getLastPage('/storage/books/a.pdf'), 14);
      expect(serviceB.getLastPage('/storage/books/b.pdf'), 5);
      expect(serviceB.getLastZoom('/storage/books/a.pdf'), 1.75);
    });

    test('resets to page 1 and cleans up on rename and delete', () async {
      final service = ReadingProgressService.forTesting();
      await service.init(storageDirOverride: tempDir);

      service.saveLastPage('/storage/doc.pdf', 9);
      expect(service.getLastPage('/storage/doc.pdf'), 9);

      // Rename / move migrates saved page
      service.renamePath('/storage/doc.pdf', '/storage/folder/doc_renamed.pdf');
      expect(service.getLastPage('/storage/doc.pdf'), 1);
      expect(service.getLastPage('/storage/folder/doc_renamed.pdf'), 9);

      // Returning to page 1 clears stored entry cleanly
      service.saveLastPage('/storage/folder/doc_renamed.pdf', 1);
      expect(service.getLastPage('/storage/folder/doc_renamed.pdf'), 1);

      // Delete removes saved page
      service.saveLastPage('/storage/temp.pdf', 7);
      service.removePath('/storage/temp.pdf');
      expect(service.getLastPage('/storage/temp.pdf'), 1);
      await service.flush();
    });

    test('computeInitialViewportTarget fits current page width on first open and restores savedZoom directly', () {
      // Narrow cover page (width 400 centered at x=200..600 inside an 800pt max-width document)
      const narrowCoverLayout = Rect.fromLTWH(200, 0, 400, 600);

      // First open (savedZoom == null): aligns to current page width (800 / 400 = 2.0)
      final firstOpen = PdfTabContentState.computeInitialViewportTarget(
        pageLayout: narrowCoverLayout,
        viewWidth: 800,
        savedZoom: null,
      );
      expect(firstOpen.zoom, closeTo(2.0, 1e-6));
      expect(firstOpen.documentOffset.dx, closeTo(200.0, 1e-6));
      expect(firstOpen.documentOffset.dy, closeTo(0.0, 1e-6));

      // Reopen with savedZoom = 1.0: immediately uses savedZoom centered horizontally
      final savedOpen = PdfTabContentState.computeInitialViewportTarget(
        pageLayout: narrowCoverLayout,
        viewWidth: 800,
        savedZoom: 1.0,
      );
      expect(savedOpen.zoom, closeTo(1.0, 1e-6));
      expect(savedOpen.documentOffset.dx, closeTo(0.0, 1e-6));
      expect(savedOpen.documentOffset.dy, closeTo(0.0, 1e-6));

      // Body page (width 600 centered at x=300..900 inside a 1200pt wide-cover document)
      const bodyPageLayout = Rect.fromLTWH(300, 808, 600, 800);
      final bodySavedOpen = PdfTabContentState.computeInitialViewportTarget(
        pageLayout: bodyPageLayout,
        viewWidth: 900,
        savedZoom: 1.5,
      );
      expect(bodySavedOpen.zoom, closeTo(1.5, 1e-6));
      expect(bodySavedOpen.documentOffset.dx, closeTo(300.0, 1e-6));
      expect(bodySavedOpen.documentOffset.dy, closeTo(808.0, 1e-6));
    });
  });
}

