import 'package:flutter/material.dart';
import 'package:gps_plus/gps_plus.dart';

void main() {
  runApp(const GpsPlusExampleApp());
}

class GpsPlusExampleApp extends StatelessWidget {
  const GpsPlusExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GPS Plus Demo',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final CellLocationService _service = CellLocationService();

  List<CellTowerInfo> _towers = [];
  CellPositionResult? _position;
  int _towerDbCount = 0;
  String _status = 'Not initialized';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() {
      _loading = true;
      _status = 'Initializing...';
    });

    try {
      await _service.initialize();
      _towerDbCount = await _service.towerCount();
      setState(() {
        _status = 'Ready ($_towerDbCount towers in DB)';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Init error: $e';
        _loading = false;
      });
    }
  }

  Future<void> _scanTowers() async {
    setState(() => _loading = true);

    try {
      final towers = await _service.getVisibleTowers();
      setState(() {
        _towers = towers;
        _status = 'Found ${towers.length} visible towers';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Scan error: $e';
        _loading = false;
      });
    }
  }

  Future<void> _calculatePosition() async {
    setState(() => _loading = true);

    try {
      final position = await _service.calculatePosition();
      setState(() {
        _position = position;
        _status = position != null
            ? 'Position: ${position.lat.toStringAsFixed(5)}, '
                '${position.lon.toStringAsFixed(5)} '
                '± ${position.accuracyMeters.toStringAsFixed(0)}m '
                '(${position.algorithm.name})'
            : 'No position available (no towers in DB?)';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Position error: $e';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GPS Plus Demo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Status', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (_loading)
                      const LinearProgressIndicator()
                    else
                      Text(_status),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _scanTowers,
                    icon: const Icon(Icons.cell_tower),
                    label: const Text('Scan Towers'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _calculatePosition,
                    icon: const Icon(Icons.location_on),
                    label: const Text('Get Position'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Position result
            if (_position != null)
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Calculated Position',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text('Lat: ${_position!.lat.toStringAsFixed(6)}'),
                      Text('Lon: ${_position!.lon.toStringAsFixed(6)}'),
                      Text(
                          'Accuracy: ${_position!.accuracyMeters.toStringAsFixed(0)}m'),
                      Text('Algorithm: ${_position!.algorithm.name}'),
                      Text('Towers used: ${_position!.towerCount}'),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Tower list
            Text('Visible Towers (${_towers.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Expanded(
              child: _towers.isEmpty
                  ? const Center(child: Text('No towers scanned yet'))
                  : ListView.builder(
                      itemCount: _towers.length,
                      itemBuilder: (context, index) {
                        final tower = _towers[index];
                        return Card(
                          child: ListTile(
                            leading: Icon(
                              Icons.cell_tower,
                              color: _rssiColor(tower.rssi),
                            ),
                            title: Text(
                                'CID: ${tower.cid} | LAC: ${tower.lac}'),
                            subtitle: Text(
                              'MCC: ${tower.mcc} MNC: ${tower.mnc} | '
                              '${tower.type.name.toUpperCase()} | '
                              'RSSI: ${tower.rssi} dBm',
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Color _rssiColor(int rssi) {
    if (rssi > -70) return Colors.green;
    if (rssi > -90) return Colors.orange;
    return Colors.red;
  }
}
