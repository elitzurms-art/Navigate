import 'package:flutter_test/flutter_test.dart';

import 'package:gps_plus_example/main.dart';

void main() {
  testWidgets('App renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const GpsPlusExampleApp());

    expect(find.text('GPS Plus Demo'), findsOneWidget);
    expect(find.text('Scan Towers'), findsOneWidget);
    expect(find.text('Get Position'), findsOneWidget);
  });
}
