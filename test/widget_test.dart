import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreor/main.dart';

void main() {
  testWidgets('PDFREORApp basic smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PDFREORApp());
    expect(find.text('PDFREOR'), findsOneWidget);
  });
}
