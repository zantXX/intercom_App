import 'package:flutter_test/flutter_test.dart';
import 'package:intercom_app/main.dart';

void main() {
  testWidgets('Intercom app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const IntercomApp());
    expect(find.textContaining('Intercom'), findsWidgets);
  });
}
