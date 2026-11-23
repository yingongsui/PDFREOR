import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreor/services/pdf_scanner_service.dart';

void main() {
  test('PdfScannerService.directoryUriToPath normalizes directory URIs cleanly', () {
    expect(PdfScannerService.directoryUriToPath(null), isNull);
    expect(
      PdfScannerService.directoryUriToPath(Uri.parse('content://tree/primary:Docs')),
      isNull,
    );
    expect(
      PdfScannerService.directoryUriToPath(
        Uri.directory('/Users/yin/Desktop/My Papers/', windows: false),
        isWindows: false,
      ),
      '/Users/yin/Desktop/My Papers',
    );
    expect(
      PdfScannerService.directoryUriToPath(
        Uri.directory('/', windows: false),
        isWindows: false,
      ),
      '/',
    );
    expect(
      PdfScannerService.directoryUriToPath(
        Uri.directory(r'C:\Users\yin\Docs\', windows: true),
        isWindows: true,
      ),
      r'C:\Users\yin\Docs',
    );
    expect(
      PdfScannerService.directoryUriToPath(
        Uri.directory(r'C:\', windows: true),
        isWindows: true,
      ),
      r'C:\',
    );
  });
}
