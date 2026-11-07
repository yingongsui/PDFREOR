import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
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
  });
}

