import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Shared crash-safe atomic file writer with per-path write serialization.
class AtomicFileStore {
  AtomicFileStore._();

  static int _tempFileSeq = 0;
  static final Map<String, Future<void>> _writeQueues = {};

  /// Serializes writes to the same [targetFile] path so rapid sequential saves
  /// never complete out of order.
  static Future<T> enqueueWrite<T>(
    File targetFile,
    Future<T> Function() action,
  ) {
    final key = targetFile.path;
    final prev = _writeQueues[key] ?? Future<void>.value();
    final completer = Completer<T>();

    late final Future<void> tail;
    tail = prev.catchError((_) {}).then((_) async {
      try {
        final result = await action();
        if (!completer.isCompleted) completer.complete(result);
      } catch (e, st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      } finally {
        if (identical(_writeQueues[key], tail)) {
          _writeQueues.remove(key);
        }
      }
    });

    _writeQueues[key] = tail;
    return completer.future;
  }

  /// Atomically writes [bytes] to [targetFile] via a flushed sibling temporary file.
  static Future<void> writeBytes(File targetFile, List<int> bytes) {
    return enqueueWrite(targetFile, () => _writeBytesInternal(targetFile, bytes));
  }

  static Future<void> _writeBytesInternal(File targetFile, List<int> bytes) async {
    final parent = targetFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    final seq = _tempFileSeq++;
    final tempPath =
        '${targetFile.path}.tmp.${DateTime.now().microsecondsSinceEpoch}_$seq';
    final tempFile = File(tempPath);
    try {
      await tempFile.writeAsBytes(bytes, flush: true);
      final writtenLen = await tempFile.length();
      if (writtenLen != bytes.length) {
        throw FileSystemException(
          'Incomplete temporary write ($writtenLen of ${bytes.length} bytes)',
          tempPath,
        );
      }
      try {
        await tempFile.rename(targetFile.path);
      } on FileSystemException {
        // Fallback for filesystems (e.g., certain Android SD card FUSE mounts)
        // that disallow rename over an existing file
        await tempFile.copy(targetFile.path);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    } finally {
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }

  /// Atomically writes UTF-8 [content] to [targetFile].
  static Future<void> writeString(File targetFile, String content) {
    return writeBytes(targetFile, utf8.encode(content));
  }
}
