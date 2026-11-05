import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  test('PdfDocument shape and arrow drawing', () {
    final doc = PdfDocument();
    final page = doc.pages.add();

    // Draw arrow
    final start = const Offset(50, 50);
    final end = const Offset(150, 150);
    final pen = PdfPen(PdfColor(255, 0, 0), width: 3);

    page.graphics.drawLine(pen, start, end);

    // Arrow head
    final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    final arrowLength = 15.0;
    final arrowAngle = math.pi / 6;

    final p1 = Offset(
      end.dx - arrowLength * math.cos(angle - arrowAngle),
      end.dy - arrowLength * math.sin(angle - arrowAngle),
    );
    final p2 = Offset(
      end.dx - arrowLength * math.cos(angle + arrowAngle),
      end.dy - arrowLength * math.sin(angle + arrowAngle),
    );

    page.graphics.drawLine(pen, end, p1);
    page.graphics.drawLine(pen, end, p2);

    final bytes = doc.saveSync();
    doc.dispose();
    expect(bytes.isNotEmpty, true);
  });

  test('PdfDocument text box drawing with unicode', () {
    final doc = PdfDocument();
    final page = doc.pages.add();
    final font = PdfStandardFont(PdfFontFamily.helvetica, 16);
    page.graphics.drawString('Hello World 测试', font);
    final bytes = doc.saveSync();
    doc.dispose();
    expect(bytes.isNotEmpty, true);
  });
}
