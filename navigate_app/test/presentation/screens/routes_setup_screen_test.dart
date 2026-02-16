import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigate_app/presentation/screens/navigations/routes_setup_screen.dart';
import 'package:navigate_app/domain/entities/navigation.dart';
import 'package:navigate_app/domain/entities/navigation_settings.dart';
import 'package:navigate_app/domain/entities/security_violation.dart';

Navigation _createTestNavigation() {
  final now = DateTime.now();
  return Navigation(
    id: 'nav1',
    name: '\u05e0\u05d9\u05d5\u05d5\u05d8 \u05d1\u05d3\u05d9\u05e7\u05d4',
    status: 'preparation',
    createdBy: 'user1',
    treeId: 'tree1',
    areaId: 'area1',
    layerNzId: 'nz1',
    layerNbId: 'nb1',
    layerGgId: 'gg1',
    distributionMethod: 'automatic',
    learningSettings: const LearningSettings(),
    verificationSettings: const VerificationSettings(autoVerification: false),
    alerts: const NavigationAlerts(enabled: false),
    displaySettings: const DisplaySettings(),
    routes: const {},
    gpsUpdateIntervalSeconds: 30,
    permissions: const NavigationPermissions(managers: [], viewers: []),
    createdAt: now,
    updatedAt: now,
  );
}

Widget _buildTestWidget(Widget child) {
  return MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: child,
    ),
  );
}

void main() {
  group('RoutesSetupScreen', () {
    late Navigation testNavigation;

    setUp(() {
      testNavigation = _createTestNavigation();
    });

    testWidgets('displays 3 option cards', (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildTestWidget(RoutesSetupScreen(navigation: testNavigation)),
      );

      // Verify the 3 option card titles are present
      expect(
        find.text('\u05d8\u05e2\u05d9\u05e0\u05d4 \u05d9\u05d3\u05e0\u05d9\u05ea \u05de\u05e7\u05d5\u05d1\u05e5 Excel'),
        findsOneWidget,
      );
      expect(
        find.text('\u05d7\u05dc\u05d5\u05e7\u05d4 \u05d0\u05d5\u05d8\u05d5\u05de\u05d8\u05d9\u05ea'),
        findsOneWidget,
      );
      expect(
        find.text('\u05d7\u05dc\u05d5\u05e7\u05d4 \u05d9\u05d3\u05e0\u05d9\u05ea \u05d1\u05d0\u05e4\u05dc\u05d9\u05e7\u05e6\u05d9\u05d4'),
        findsOneWidget,
      );

      // Verify there are exactly 3 InkWell widgets (one per option card)
      expect(find.byType(InkWell), findsNWidgets(3));
    });

    testWidgets('displays screen title', (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildTestWidget(RoutesSetupScreen(navigation: testNavigation)),
      );

      expect(
        find.text('\u05d1\u05d7\u05e8 \u05e9\u05d9\u05d8\u05ea \u05d9\u05e6\u05d9\u05e8\u05ea \u05e6\u05d9\u05e8\u05d9\u05dd'),
        findsOneWidget,
      );
    });

    testWidgets('displays navigation name', (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildTestWidget(RoutesSetupScreen(navigation: testNavigation)),
      );

      expect(
        find.text('\u05e0\u05d9\u05d5\u05d5\u05d8: \u05e0\u05d9\u05d5\u05d5\u05d8 \u05d1\u05d3\u05d9\u05e7\u05d4'),
        findsOneWidget,
      );
    });

    testWidgets('displays AppBar title', (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildTestWidget(RoutesSetupScreen(navigation: testNavigation)),
      );

      expect(
        find.text('\u05d9\u05e6\u05d9\u05e8\u05ea \u05d8\u05d1\u05dc\u05ea \u05e6\u05d9\u05e8\u05d9\u05dd'),
        findsOneWidget,
      );
    });

    testWidgets('displays step indicator', (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildTestWidget(RoutesSetupScreen(navigation: testNavigation)),
      );

      // Verify all 4 step texts
      expect(
        find.text('\u05d9\u05e6\u05d9\u05e8\u05ea/\u05d8\u05e2\u05d9\u05e0\u05ea \u05d8\u05d1\u05dc\u05ea \u05e6\u05d9\u05e8\u05d9\u05dd'),
        findsOneWidget,
      );
      expect(
        find.text('\u05d5\u05d9\u05d3\u05d5\u05d0 \u05e6\u05d9\u05e8\u05d9\u05dd'),
        findsOneWidget,
      );
      expect(
        find.text('\u05e9\u05d9\u05e0\u05d5\u05d9\u05d9\u05dd (\u05d0\u05d5\u05e4\u05e6\u05d9\u05d5\u05e0\u05dc\u05d9)'),
        findsOneWidget,
      );
      expect(
        find.text('\u05e1\u05d9\u05d5\u05dd \u05d4\u05db\u05e0\u05d5\u05ea \u05d5\u05e9\u05de\u05d9\u05e8\u05d4'),
        findsOneWidget,
      );

      // Verify the step numbers are displayed
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);

      // Verify the step indicator header
      expect(
        find.text('\u05d4\u05e9\u05dc\u05d1\u05d9\u05dd \u05d4\u05d1\u05d0\u05d9\u05dd:'),
        findsOneWidget,
      );
    });

    testWidgets('Excel option has upload_file icon',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildTestWidget(RoutesSetupScreen(navigation: testNavigation)),
      );

      expect(find.byIcon(Icons.upload_file), findsOneWidget);
    });

    testWidgets('Automatic option has auto_fix_high icon',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildTestWidget(RoutesSetupScreen(navigation: testNavigation)),
      );

      expect(find.byIcon(Icons.auto_fix_high), findsOneWidget);
    });

    testWidgets('Manual option has touch_app icon',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildTestWidget(RoutesSetupScreen(navigation: testNavigation)),
      );

      expect(find.byIcon(Icons.touch_app), findsOneWidget);
    });

    testWidgets('all 3 option cards have InkWell with onTap callback',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildTestWidget(RoutesSetupScreen(navigation: testNavigation)),
      );

      // Find all InkWell widgets (the tappable option cards)
      final inkWells = find.byType(InkWell);
      expect(inkWells, findsNWidgets(3));

      // Verify each InkWell has an onTap callback (is tappable)
      for (int i = 0; i < 3; i++) {
        final inkWell = tester.widget<InkWell>(inkWells.at(i));
        expect(inkWell.onTap, isNotNull,
            reason: 'Option card $i should have an onTap callback');
      }
    });
  });
}
