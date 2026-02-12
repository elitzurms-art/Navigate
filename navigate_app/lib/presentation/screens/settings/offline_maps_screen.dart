import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/map_config.dart';
import '../../../core/utils/geometry_utils.dart';
import '../../../data/repositories/boundary_repository.dart';
import '../../../domain/entities/boundary.dart';
import '../../../services/tile_cache_service.dart';

/// מסך ניהול מפות אופליין — הורדת אריחים, סטטיסטיקות, ניקוי
class OfflineMapsScreen extends StatefulWidget {
  const OfflineMapsScreen({super.key});

  @override
  State<OfflineMapsScreen> createState() => _OfflineMapsScreenState();
}

class _OfflineMapsScreenState extends State<OfflineMapsScreen> {
  final _tileCacheService = TileCacheService();
  final _boundaryRepo = BoundaryRepository();
  final _mapConfig = MapConfig();

  // סטטיסטיקות cache
  int _tileCount = 0;
  double _sizeMB = 0.0;
  bool _loadingStats = true;

  // גבולות להורדה
  List<Boundary> _boundaries = [];
  Boundary? _selectedBoundary;

  // סוג מפה להורדה
  MapType _selectedMapType = MapType.standard;

  // טווח זום
  int _minZoom = 10;
  int _maxZoom = 16;

  // הורדה
  bool _isDownloading = false;
  int _downloadedTiles = 0;
  int _totalTiles = 0;
  int _failedTiles = 0;
  StreamSubscription<DownloadProgress>? _downloadSubscription;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadBoundaries();
  }

  @override
  void dispose() {
    _downloadSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadStats() async {
    final stats = await _tileCacheService.getStoreStats();
    if (!mounted) return;
    setState(() {
      _tileCount = stats.tileCount;
      _sizeMB = stats.sizeMB;
      _loadingStats = false;
    });
  }

  Future<void> _loadBoundaries() async {
    try {
      final boundaries = await _boundaryRepo.getAll();
      if (!mounted) return;
      setState(() {
        _boundaries = boundaries;
      });
    } catch (e) {
      print('DEBUG OfflineMaps: error loading boundaries: $e');
    }
  }

  int get _estimatedTiles {
    if (_selectedBoundary == null) return 0;
    final bbox = GeometryUtils.getBoundingBox(_selectedBoundary!.coordinates);
    final bounds = LatLngBounds(
      LatLng(bbox.minLat - 0.01, bbox.minLng - 0.01),
      LatLng(bbox.maxLat + 0.01, bbox.maxLng + 0.01),
    );
    return _tileCacheService.countTiles(
      bounds: bounds,
      minZoom: _minZoom,
      maxZoom: _maxZoom,
    );
  }

  double get _estimatedSizeMB {
    return _estimatedTiles * _mapConfig.estimatedTileSizeKB(_selectedMapType) / 1024;
  }

  Future<void> _startDownload() async {
    if (_selectedBoundary == null) return;

    final bbox = GeometryUtils.getBoundingBox(_selectedBoundary!.coordinates);
    // הוספת padding של ~1 ק"מ
    final bounds = LatLngBounds(
      LatLng(bbox.minLat - 0.01, bbox.minLng - 0.01),
      LatLng(bbox.maxLat + 0.01, bbox.maxLng + 0.01),
    );

    setState(() {
      _isDownloading = true;
      _downloadedTiles = 0;
      _totalTiles = _estimatedTiles;
      _failedTiles = 0;
    });

    final stream = _tileCacheService.downloadRegion(
      bounds: bounds,
      mapType: _selectedMapType,
      minZoom: _minZoom,
      maxZoom: _maxZoom,
    );

    _downloadSubscription = stream.listen(
      (progress) {
        if (!mounted) return;
        setState(() {
          _downloadedTiles = progress.cachedTiles + progress.skippedTiles;
          _totalTiles = progress.maxTiles;
          _failedTiles = progress.failedTiles;
          if (progress.isComplete) {
            _isDownloading = false;
            _loadStats();
          }
        });
      },
      onError: (error) {
        if (!mounted) return;
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בהורדה: $error')),
        );
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _isDownloading = false);
        _loadStats();
      },
    );
  }

  void _cancelDownload() {
    _downloadSubscription?.cancel();
    _downloadSubscription = null;
    setState(() => _isDownloading = false);
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ניקוי מפות שמורות'),
        content: const Text('כל אריחי המפה השמורים יימחקו. להמשיך?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('מחיקה', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _tileCacheService.clearCache();
    await _loadStats();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('המפות השמורות נמחקו')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('מפות אופליין'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStatsSection(),
          const SizedBox(height: 24),
          if (_isDownloading)
            _buildProgressSection()
          else
            _buildDownloadSection(),
        ],
      ),
    );
  }

  Widget _buildStatsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              const Icon(Icons.storage, color: Colors.blue),
              const SizedBox(width: 8),
              Text(
                'מפות שמורות',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loadingStats)
            const Center(child: CircularProgressIndicator())
          else ...[
            _buildStatRow('אריחים שמורים', '$_tileCount'),
            _buildStatRow(
              'גודל',
              _sizeMB < 1
                  ? '${(_sizeMB * 1024).toStringAsFixed(0)} KB'
                  : '${_sizeMB.toStringAsFixed(1)} MB',
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _tileCount > 0 ? _clearCache : null,
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text('ניקוי מפות שמורות',
                    style: TextStyle(color: Colors.red)),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildDownloadSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              const Icon(Icons.download, color: Colors.green),
              const SizedBox(width: 8),
              Text(
                'הורדת מפה',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // בחירת גבול
          DropdownButtonFormField<Boundary>(
            value: _selectedBoundary,
            decoration: const InputDecoration(
              labelText: 'גבול גזרה',
              border: OutlineInputBorder(),
            ),
            items: _boundaries.map((b) {
              return DropdownMenuItem(value: b, child: Text(b.name));
            }).toList(),
            onChanged: (b) => setState(() => _selectedBoundary = b),
          ),
          const SizedBox(height: 12),

          // בחירת סוג מפה
          DropdownButtonFormField<MapType>(
            value: _selectedMapType,
            decoration: const InputDecoration(
              labelText: 'סוג מפה',
              border: OutlineInputBorder(),
            ),
            items: MapType.values.map((type) {
              return DropdownMenuItem(
                value: type,
                child: Text(_mapConfig.label(type)),
              );
            }).toList(),
            onChanged: (t) {
              if (t != null) setState(() => _selectedMapType = t);
            },
          ),
          const SizedBox(height: 16),

          // טווח זום
          Text('טווח זום: $_minZoom – $_maxZoom'),
          RangeSlider(
            values: RangeValues(_minZoom.toDouble(), _maxZoom.toDouble()),
            min: 5,
            max: 18,
            divisions: 13,
            labels: RangeLabels('$_minZoom', '$_maxZoom'),
            onChanged: (values) {
              setState(() {
                _minZoom = values.start.round();
                _maxZoom = values.end.round();
              });
            },
          ),

          // הערכת גודל
          if (_selectedBoundary != null) ...[
            const Divider(),
            _buildStatRow('אריחים משוערים', '~${_estimatedTiles}'),
            _buildStatRow(
              'גודל משוער',
              '~${_estimatedSizeMB.toStringAsFixed(1)} MB',
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _startDownload,
                icon: const Icon(Icons.download),
                label: const Text('התחל הורדה'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _buildProgressSection() {
    final progress = _totalTiles > 0 ? _downloadedTiles / _totalTiles : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              const Icon(Icons.downloading, color: Colors.orange),
              const SizedBox(width: 8),
              Text(
                'מוריד מפה...',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 8),
          _buildStatRow('הורדו', '$_downloadedTiles / $_totalTiles'),
          if (_failedTiles > 0)
            _buildStatRow('נכשלו', '$_failedTiles'),
          _buildStatRow(
            'אחוז',
            '${(progress * 100).toStringAsFixed(1)}%',
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _cancelDownload,
              icon: const Icon(Icons.cancel, color: Colors.red),
              label: const Text('ביטול', style: TextStyle(color: Colors.red)),
            ),
          ),
        ]),
      ),
    );
  }
}
