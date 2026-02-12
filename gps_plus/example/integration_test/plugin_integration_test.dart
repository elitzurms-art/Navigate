import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:gps_plus/gps_plus.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('getCellTowers integration test', (WidgetTester tester) async {
    final service = CellLocationService();
    await service.initialize();

    final towers = await service.getVisibleTowers();
    // On test devices, towers may be empty - just verify it doesn't throw
    expect(towers, isA<List<CellTowerInfo>>());

    await service.dispose();
  });
}
