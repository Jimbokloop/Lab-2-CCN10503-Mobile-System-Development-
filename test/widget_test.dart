import 'package:flutter_test/flutter_test.dart';
import 'package:flutterdemo/main.dart';

void main() {
  testWidgets('Smart Task Manager displays correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartTaskApp());
    expect(find.text('Smart Task Manager'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('No tasks yet'), findsOneWidget);
  });
}