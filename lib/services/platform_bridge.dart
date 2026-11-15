import 'dart:io';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';

/// Shared native channel bridge and desktop capability helpers.
class PlatformBridge {
  PlatformBridge._();

  static const MethodChannel stylusChannel = MethodChannel('com.yin.pdfreor/stylus');

  static Future<bool> openUrl(String url) async {
    try {
      final ok = await stylusChannel.invokeMethod<bool>('openUrl', {'url': url});
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  static Future<OpenResult> openFileExternally(String filePath) async {
    if (Platform.isMacOS) {
      try {
        final opened = await stylusChannel.invokeMethod<bool>(
          'openFile',
          {'path': filePath},
        );
        return OpenResult(
          type: opened == true ? ResultType.done : ResultType.error,
          message: opened == true ? 'done' : 'Unable to open file in external app',
        );
      } on MissingPluginException {
        // Fall through to OpenFilex if native handler is unavailable (e.g. tests).
      } catch (e) {
        return OpenResult(type: ResultType.error, message: e.toString());
      }
    }
    return OpenFilex.open(filePath);
  }

  static Future<Uint8List?> getClipboardImage() async {
    try {
      final bytes = await stylusChannel.invokeMethod<Uint8List>('getClipboardImage');
      if (bytes != null && bytes.isNotEmpty) {
        return bytes;
      }
    } catch (_) {}
    return null;
  }
}
