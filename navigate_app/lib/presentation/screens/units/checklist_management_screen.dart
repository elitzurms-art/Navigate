import 'package:flutter/material.dart';
import '../../../core/constants/default_checklists.dart';
import '../../../domain/entities/unit_checklist.dart';
import '../../../data/repositories/unit_repository.dart';

/// מסך ניהול צ'קליסטים ברמת היחידה
class ChecklistManagementScreen extends StatefulWidget {
  final String unitId;

  const ChecklistManagementScreen({super.key, required this.unitId});

  @override
  State<ChecklistManagementScreen> createState() =>
      _ChecklistManagementScreenState();
}

class _ChecklistManagementScreenState
    extends State<ChecklistManagementScreen> {
  final UnitRepository _unitRepo = UnitRepository();
  List<UnitChecklist> _checklists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadChecklists();
  }

  Future<void> _loadChecklists() async {
    setState(() => _isLoading = true);
    try {
      final unit = await _unitRepo.getById(widget.unitId);
      if (unit != null && mounted) {
        setState(() {
          _checklists = List.from(unit.checklists);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    await _unitRepo.updateChecklists(widget.unitId, _checklists);
  }

  Future<void> _resetToDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('איפוס לברירת מחדל'),
        content: const Text(
            'כל הצ\'קליסטים הנוכחיים יימחקו ויוחלפו ב-4 צ\'קליסטים ברירת מחדל. להמשיך?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('איפוס', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() => _checklists = kDefaultUnitChecklists.toList());
      await _save();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('הצ\'קליסטים אופסו לברירת מחדל')),
        );
      }
    }
  }

  void _addChecklist() {
    _openEditor(null);
  }

  void _editChecklist(int index) {
    _openEditor(index);
  }

  Future<void> _deleteChecklist(int index) async {
    final name = _checklists[index].title;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('מחיקת צ\'קליסט'),
        content: Text('למחוק את "$name"?'),
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
    if (confirmed == true) {
      setState(() => _checklists.removeAt(index));
      await _save();
    }
  }

  void _openEditor(int? index) async {
    final existing = index != null ? _checklists[index] : null;
    final result = await Navigator.push<UnitChecklist>(
      context,
      MaterialPageRoute(
        builder: (_) => _ChecklistEditorScreen(checklist: existing),
      ),
    );
    if (result != null) {
      setState(() {
        if (index != null) {
          _checklists[index] = result;
        } else {
          _checklists.add(result);
        }
      });
      await _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ניהול צ\'קליסטים'),
          actions: [
            IconButton(
              icon: const Icon(Icons.restore),
              tooltip: 'איפוס לברירת מחדל',
              onPressed: _resetToDefaults,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _addChecklist,
          child: const Icon(Icons.add),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _checklists.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.checklist, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text('אין צ\'קליסטים',
                            style: TextStyle(
                                fontSize: 18, color: Colors.grey[600])),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _resetToDefaults,
                          icon: const Icon(Icons.restore),
                          label: const Text('טען ברירת מחדל'),
                        ),
                      ],
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.only(
                        bottom: 80, top: 8, left: 8, right: 8),
                    itemCount: _checklists.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex--;
                        final item = _checklists.removeAt(oldIndex);
                        _checklists.insert(newIndex, item);
                      });
                      _save();
                    },
                    itemBuilder: (context, index) {
                      final cl = _checklists[index];
                      return _buildChecklistTile(cl, index);
                    },
                  ),
      ),
    );
  }

  Widget _buildChecklistTile(UnitChecklist cl, int index) {
    return Card(
      key: ValueKey(cl.id),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        leading: ReorderableDragStartListener(
          index: index,
          child: const Icon(Icons.drag_handle),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(cl.title,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            if (cl.isMandatory)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red[300]!),
                ),
                child: Text('חובה',
                    style:
                        TextStyle(fontSize: 11, color: Colors.red[700])),
              )
            else
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[400]!),
                ),
                child: Text('אופציונלי',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey[700])),
              ),
          ],
        ),
        subtitle: Text(
          '${cl.sections.length} קטגוריות · ${cl.totalItems} פריטים',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              onPressed: () => _editChecklist(index),
            ),
            IconButton(
              icon: Icon(Icons.delete, size: 20, color: Colors.red[400]),
              onPressed: () => _deleteChecklist(index),
            ),
          ],
        ),
        children: [
          for (final section in cl.sections)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(section.title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  for (final item in section.items)
                    Padding(
                      padding: const EdgeInsets.only(right: 16, top: 2),
                      child: Row(
                        children: [
                          Icon(Icons.check_box_outline_blank,
                              size: 16, color: Colors.grey[400]),
                          const SizedBox(width: 6),
                          Text(item.title,
                              style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Editor screen for a single checklist
// ─────────────────────────────────────────────────────────────────

class _ChecklistEditorScreen extends StatefulWidget {
  final UnitChecklist? checklist;

  const _ChecklistEditorScreen({this.checklist});

  @override
  State<_ChecklistEditorScreen> createState() =>
      _ChecklistEditorScreenState();
}

class _ChecklistEditorScreenState extends State<_ChecklistEditorScreen> {
  late TextEditingController _titleController;
  late bool _isMandatory;
  late List<_EditableSection> _sections;

  @override
  void initState() {
    super.initState();
    final cl = widget.checklist;
    _titleController = TextEditingController(text: cl?.title ?? '');
    _isMandatory = cl?.isMandatory ?? false;
    _sections = cl?.sections
            .map((s) => _EditableSection(
                  id: s.id,
                  titleController: TextEditingController(text: s.title),
                  items: s.items
                      .map((i) => _EditableItem(
                            id: i.id,
                            controller:
                                TextEditingController(text: i.title),
                          ))
                      .toList(),
                ))
            .toList() ??
        [];
  }

  @override
  void dispose() {
    _titleController.dispose();
    for (final s in _sections) {
      s.titleController.dispose();
      for (final i in s.items) {
        i.controller.dispose();
      }
    }
    super.dispose();
  }

  String _generateId(String prefix) =>
      '${prefix}_${DateTime.now().millisecondsSinceEpoch}';

  void _addSection() {
    setState(() {
      _sections.add(_EditableSection(
        id: _generateId('s'),
        titleController: TextEditingController(),
        items: [],
      ));
    });
  }

  void _removeSection(int index) {
    setState(() {
      _sections[index].titleController.dispose();
      for (final i in _sections[index].items) {
        i.controller.dispose();
      }
      _sections.removeAt(index);
    });
  }

  void _addItem(int sectionIndex) {
    setState(() {
      _sections[sectionIndex].items.add(_EditableItem(
        id: _generateId('i'),
        controller: TextEditingController(),
      ));
    });
  }

  void _removeItem(int sectionIndex, int itemIndex) {
    setState(() {
      _sections[sectionIndex].items[itemIndex].controller.dispose();
      _sections[sectionIndex].items.removeAt(itemIndex);
    });
  }

  void _saveAndReturn() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('יש להזין כותרת לצ\'קליסט')),
      );
      return;
    }

    final sections = _sections
        .where((s) => s.titleController.text.trim().isNotEmpty)
        .map((s) => ChecklistSection(
              id: s.id,
              title: s.titleController.text.trim(),
              items: s.items
                  .where((i) => i.controller.text.trim().isNotEmpty)
                  .map((i) => ChecklistItem(
                        id: i.id,
                        title: i.controller.text.trim(),
                      ))
                  .toList(),
            ))
        .where((s) => s.items.isNotEmpty)
        .toList();

    if (sections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('יש להוסיף לפחות קטגוריה אחת עם פריט אחד')),
      );
      return;
    }

    final result = UnitChecklist(
      id: widget.checklist?.id ?? _generateId('cl'),
      title: title,
      sections: sections,
      isMandatory: _isMandatory,
    );

    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.checklist == null;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(isNew ? 'צ\'קליסט חדש' : 'עריכת צ\'קליסט'),
          actions: [
            TextButton.icon(
              onPressed: _saveAndReturn,
              icon: const Icon(Icons.check, color: Colors.white),
              label: const Text('שמירה',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Title
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'כותרת הצ\'קליסט',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            // Mandatory toggle
            SwitchListTile(
              title: const Text('חובה'),
              subtitle:
                  const Text('צ\'קליסט חובה חוסם מעבר לאימון'),
              value: _isMandatory,
              onChanged: (v) => setState(() => _isMandatory = v),
            ),
            const Divider(height: 24),

            // Sections
            for (int si = 0; si < _sections.length; si++) ...[
              _buildSectionEditor(si),
              const SizedBox(height: 12),
            ],

            // Add section button
            OutlinedButton.icon(
              onPressed: _addSection,
              icon: const Icon(Icons.add),
              label: const Text('הוספת קטגוריה'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionEditor(int si) {
    final section = _sections[si];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: section.titleController,
                    decoration: const InputDecoration(
                      labelText: 'שם קטגוריה',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete, color: Colors.red[400]),
                  onPressed: () => _removeSection(si),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (int ii = 0; ii < section.items.length; ii++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: section.items[ii].controller,
                        decoration: InputDecoration(
                          hintText: 'פריט ${ii + 1}',
                          isDense: true,
                          border: const UnderlineInputBorder(),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.remove_circle_outline,
                          size: 20, color: Colors.red[300]),
                      onPressed: () => _removeItem(si, ii),
                    ),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: () => _addItem(si),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('הוספת פריט', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditableSection {
  final String id;
  final TextEditingController titleController;
  final List<_EditableItem> items;

  _EditableSection({
    required this.id,
    required this.titleController,
    required this.items,
  });
}

class _EditableItem {
  final String id;
  final TextEditingController controller;

  _EditableItem({required this.id, required this.controller});
}
