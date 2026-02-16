import 'package:flutter/material.dart';

import '../../services/route_export_service.dart';

/// בוחר פורמט ייצוא — מוצג כ-bottom sheet
class ExportFormatPicker extends StatefulWidget {
  const ExportFormatPicker({super.key});

  @override
  State<ExportFormatPicker> createState() => _ExportFormatPickerState();
}

class _ExportFormatPickerState extends State<ExportFormatPicker> {
  ExportFormat _selected = ExportFormat.gpx;

  static const _formats = [
    _FormatOption(
      format: ExportFormat.gpx,
      icon: Icons.route,
      title: 'GPX',
      subtitle: 'פורמט סטנדרטי למכשירי GPS וניווט',
    ),
    _FormatOption(
      format: ExportFormat.kml,
      icon: Icons.public,
      title: 'KML',
      subtitle: 'פורמט Google Earth — תצוגה עם סגנונות וצבעים',
    ),
    _FormatOption(
      format: ExportFormat.geojson,
      icon: Icons.data_object,
      title: 'GeoJSON',
      subtitle: 'פורמט גאוגרפי מבוסס JSON — נפוץ במערכות GIS',
    ),
    _FormatOption(
      format: ExportFormat.csv,
      icon: Icons.table_chart,
      title: 'CSV',
      subtitle: 'טבלת נתונים — פתיחה ב-Excel, שני קבצים (מסלול + נקודות)',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Title
              Text(
                'ייצוא מסלול',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'בחר פורמט קובץ לייצוא',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 16),

              // Format options — scrollable for small screens
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _formats.map((opt) => _buildOption(opt, theme)).toList(),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Export button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(_selected),
                  icon: const Icon(Icons.file_download),
                  label: const Text('ייצוא'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOption(_FormatOption opt, ThemeData theme) {
    final isSelected = _selected == opt.format;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSelected
            ? theme.primaryColor.withOpacity(0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _selected = opt.format),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? theme.primaryColor
                    : Colors.grey[300]!,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? theme.primaryColor.withOpacity(0.12)
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    opt.icon,
                    color: isSelected
                        ? theme.primaryColor
                        : Colors.grey[600],
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),

                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        opt.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isSelected
                              ? theme.primaryColor
                              : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        opt.subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),

                // Radio indicator
                if (isSelected)
                  Icon(Icons.check_circle,
                      color: theme.primaryColor, size: 24)
                else
                  Icon(Icons.radio_button_unchecked,
                      color: Colors.grey[400], size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FormatOption {
  final ExportFormat format;
  final IconData icon;
  final String title;
  final String subtitle;

  const _FormatOption({
    required this.format,
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}
