import 'package:flutter/material.dart';

/// עמודה בטבלה ניתנת לעריכה
class EditableColumn {
  final String header;
  final double flex;
  final bool isCheckbox;

  const EditableColumn({
    required this.header,
    this.flex = 1.0,
    this.isCheckbox = false,
  });
}

/// טבלה ניתנת לעריכה עבור דף משתנים
class EditableTable extends StatelessWidget {
  final List<EditableColumn> columns;
  final int rowCount;
  final String? Function(int row, int col) getCellValue;
  final bool? Function(int row, int col)? getCellBoolValue;
  final void Function(int row, int col, String value) onCellChanged;
  final void Function(int row, int col, bool value)? onCellBoolChanged;
  final VoidCallback? onAddRow;
  final void Function(int row)? onRemoveRow;
  final bool canAddRows;
  final bool canRemoveRows;

  const EditableTable({
    super.key,
    required this.columns,
    required this.rowCount,
    required this.getCellValue,
    this.getCellBoolValue,
    required this.onCellChanged,
    this.onCellBoolChanged,
    this.onAddRow,
    this.onRemoveRow,
    this.canAddRows = false,
    this.canRemoveRows = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header row
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6),
              topRight: Radius.circular(6),
            ),
          ),
          child: Row(
            children: [
              if (canRemoveRows) const SizedBox(width: 40),
              ...columns.map((col) => Expanded(
                flex: (col.flex * 10).toInt(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Text(
                    col.header,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              )),
            ],
          ),
        ),
        // Data rows
        ...List.generate(rowCount, (row) => Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade300),
              left: BorderSide(color: Colors.grey.shade300),
              right: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          child: Row(
            children: [
              if (canRemoveRows)
                SizedBox(
                  width: 40,
                  child: IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 18, color: Colors.red),
                    onPressed: () => onRemoveRow?.call(row),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ...List.generate(columns.length, (col) {
                final column = columns[col];
                if (column.isCheckbox) {
                  return Expanded(
                    flex: (column.flex * 10).toInt(),
                    child: Checkbox(
                      value: getCellBoolValue?.call(row, col) ?? false,
                      onChanged: (v) => onCellBoolChanged?.call(row, col, v ?? false),
                    ),
                  );
                }
                return Expanded(
                  flex: (column.flex * 10).toInt(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: TextFormField(
                      initialValue: getCellValue(row, col) ?? '',
                      onChanged: (v) => onCellChanged(row, col, v),
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        )),
        // Add row button
        if (canAddRows)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('הוסף שורה', style: TextStyle(fontSize: 12)),
              onPressed: onAddRow,
            ),
          ),
      ],
    );
  }
}
