import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../core/constants/default_checklists.dart';
import '../../../domain/entities/unit.dart' as domain;
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
  domain.Unit? _parentUnit;
  List<UnitChecklist> _parentChecklists = [];

  static final _dateFormat = DateFormat('dd/MM/yyyy');

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
        // Load parent unit if exists
        domain.Unit? parent;
        List<UnitChecklist> parentCl = [];
        if (unit.parentUnitId != null) {
          parent = await _unitRepo.getById(unit.parentUnitId!);
          if (parent != null) {
            parentCl = parent.checklists;
          }
        }
        setState(() {
          _checklists = List.from(unit.checklists);
          _parentUnit = parent;
          _parentChecklists = parentCl;
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
      setState(() => _checklists = kDefaultUnitChecklists());
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
    if (index != null) {
      // Edit mode — auto-save via callback
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _ChecklistEditorScreen(
            checklist: existing,
            onAutoSave: (updated) {
              setState(() => _checklists[index] = updated);
              _save();
            },
          ),
        ),
      );
    } else {
      // Create mode — pop with result
      final result = await Navigator.push<UnitChecklist>(
        context,
        MaterialPageRoute(
          builder: (_) => const _ChecklistEditorScreen(),
        ),
      );
      if (result != null) {
        setState(() => _checklists.add(result));
        await _save();
      }
    }
  }

  // ─────────────────────────────────────────────
  // Import from parent unit
  // ─────────────────────────────────────────────

  Future<void> _showImportDialog() async {
    if (_parentUnit == null || _parentChecklists.isEmpty) return;

    final selected = await showDialog<List<UnitChecklist>>(
      context: context,
      builder: (ctx) => _ImportChecklistsDialog(
        parentUnitName: _parentUnit!.name,
        parentChecklists: _parentChecklists,
        localChecklists: _checklists,
      ),
    );

    if (selected != null && selected.isNotEmpty) {
      int imported = 0;
      for (final source in selected) {
        final success = await _importChecklist(source);
        if (success) imported++;
      }
      await _save();
      if (mounted && imported > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('יובאו $imported צ\'קליסטים בהצלחה')),
        );
      }
    }
  }

  /// Returns true if a checklist was actually added
  Future<bool> _importChecklist(UnitChecklist source) async {
    final localMatch = _checklists
        .where((c) => c.copiedFromChecklistId == source.id)
        .firstOrNull;

    if (localMatch == null) {
      // First import — create copy
      _addCopy(source);
      return true;
    }

    // Already imported — ask user
    if (!mounted) return false;
    final createNew = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dateStr = localMatch.copiedAt != null
            ? _dateFormat.format(localMatch.copiedAt!)
            : '?';
        return AlertDialog(
          title: const Text('צ\'קליסט כבר יובא'),
          content: Text(
            'הצ\'קליסט "${source.title}" כבר יובא בתאריך $dateStr.\n'
            'ליצור עותק חדש?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('צור עותק חדש'),
            ),
          ],
        );
      },
    );

    if (createNew == true) {
      _addCopy(source);
      return true;
    }
    return false;
  }

  void _addCopy(UnitChecklist source) {
    final now = DateTime.now();
    final copy = source.copyWith(
      id: 'cp_${now.millisecondsSinceEpoch}',
      copiedFromUnitId: _parentUnit!.id,
      copiedFromChecklistId: source.id,
      copiedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    setState(() => _checklists.add(copy));
  }

  /// Check if source was updated since local copy
  bool _sourceUpdatedSinceCopy(UnitChecklist source, UnitChecklist local) {
    if (source.updatedAt == null || local.copiedAt == null) return false;
    return source.updatedAt!.isAfter(local.copiedAt!);
  }

  @override
  Widget build(BuildContext context) {
    final hasParentChecklists =
        _parentUnit != null && _parentChecklists.isNotEmpty;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ניהול צ\'קליסטים'),
          actions: [
            if (hasParentChecklists)
              IconButton(
                icon: const Icon(Icons.download),
                tooltip: 'ייבוא מיחידת אם',
                onPressed: _showImportDialog,
              ),
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
                        if (hasParentChecklists) ...[
                          const SizedBox(height: 4),
                          TextButton.icon(
                            onPressed: _showImportDialog,
                            icon: const Icon(Icons.download),
                            label: const Text('ייבוא מיחידת אם'),
                          ),
                        ],
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
    // Check if this checklist was imported and if source has newer version
    final isCopied = cl.copiedFromUnitId != null;
    UnitChecklist? sourceInParent;
    bool hasNewerVersion = false;
    if (isCopied && cl.copiedFromChecklistId != null) {
      sourceInParent = _parentChecklists
          .where((p) => p.id == cl.copiedFromChecklistId)
          .firstOrNull;
      if (sourceInParent != null) {
        hasNewerVersion = _sourceUpdatedSinceCopy(sourceInParent, cl);
      }
    }

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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${cl.sections.length} קטגוריות · ${cl.totalItems} פריטים',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            if (isCopied) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.copy, size: 12, color: Colors.blue[400]),
                  const SizedBox(width: 4),
                  Text(
                    'הועתק מיחידת אם${cl.copiedAt != null ? ' · ${_dateFormat.format(cl.copiedAt!)}' : ''}',
                    style: TextStyle(fontSize: 11, color: Colors.blue[600]),
                  ),
                ],
              ),
              if (hasNewerVersion) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.warning_amber, size: 12, color: Colors.orange[700]),
                    const SizedBox(width: 4),
                    Text(
                      'קיימת גרסה חדשה במקור',
                      style: TextStyle(fontSize: 11, color: Colors.orange[700]),
                    ),
                  ],
                ),
              ],
            ],
          ],
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
                          Expanded(
                            child: Text(item.title,
                                style: const TextStyle(fontSize: 13)),
                          ),
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
// Import dialog — select checklists from parent unit
// ─────────────────────────────────────────────────────────────────

class _ImportChecklistsDialog extends StatefulWidget {
  final String parentUnitName;
  final List<UnitChecklist> parentChecklists;
  final List<UnitChecklist> localChecklists;

  const _ImportChecklistsDialog({
    required this.parentUnitName,
    required this.parentChecklists,
    required this.localChecklists,
  });

  @override
  State<_ImportChecklistsDialog> createState() =>
      _ImportChecklistsDialogState();
}

class _ImportChecklistsDialogState extends State<_ImportChecklistsDialog> {
  final Set<String> _selectedIds = {};
  static final _dateFormat = DateFormat('dd/MM/yyyy');

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text('ייבוא מ-${widget.parentUnitName}'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: widget.parentChecklists.length,
            itemBuilder: (ctx, index) {
              final source = widget.parentChecklists[index];
              final localMatch = widget.localChecklists
                  .where((c) => c.copiedFromChecklistId == source.id)
                  .firstOrNull;

              final alreadyImported = localMatch != null;
              final hasNewerVersion = alreadyImported &&
                  source.updatedAt != null &&
                  localMatch.copiedAt != null &&
                  source.updatedAt!.isAfter(localMatch.copiedAt!);

              return CheckboxListTile(
                value: _selectedIds.contains(source.id),
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selectedIds.add(source.id);
                    } else {
                      _selectedIds.remove(source.id);
                    }
                  });
                },
                title: Text(source.title),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${source.sections.length} קטגוריות · ${source.totalItems} פריטים',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    if (alreadyImported) ...[
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: hasNewerVersion
                              ? Colors.orange[50]
                              : Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          hasNewerVersion
                              ? 'גרסה חדשה זמינה'
                              : 'יובא כבר · ${localMatch.copiedAt != null ? _dateFormat.format(localMatch.copiedAt!) : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            color: hasNewerVersion
                                ? Colors.orange[800]
                                : Colors.blue[700],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: _selectedIds.isEmpty
                ? null
                : () {
                    final selected = widget.parentChecklists
                        .where((c) => _selectedIds.contains(c.id))
                        .toList();
                    Navigator.pop(context, selected);
                  },
            child: Text('ייבוא (${_selectedIds.length})'),
          ),
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
  final void Function(UnitChecklist)? onAutoSave;

  const _ChecklistEditorScreen({this.checklist, this.onAutoSave});

  @override
  State<_ChecklistEditorScreen> createState() =>
      _ChecklistEditorScreenState();
}

class _ChecklistEditorScreenState extends State<_ChecklistEditorScreen> {
  late TextEditingController _titleController;
  late bool _isMandatory;
  late List<_EditableSection> _sections;
  Timer? _debounceTimer;

  bool get _isEditMode => widget.onAutoSave != null;

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
    if (_isEditMode) {
      _titleController.addListener(_triggerAutoSave);
      for (final s in _sections) {
        s.titleController.addListener(_triggerAutoSave);
        for (final i in s.items) {
          i.controller.addListener(_triggerAutoSave);
        }
      }
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _titleController.dispose();
    for (final s in _sections) {
      s.titleController.dispose();
      for (final i in s.items) {
        i.controller.dispose();
      }
    }
    super.dispose();
  }

  void _triggerAutoSave() {
    if (!_isEditMode) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      final checklist = _buildChecklist();
      if (checklist != null) {
        widget.onAutoSave!(checklist);
      }
    });
  }

  UnitChecklist? _buildChecklist() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return null;

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

    final now = DateTime.now();
    final existing = widget.checklist;
    return UnitChecklist(
      id: existing?.id ?? _generateId('cl'),
      title: title,
      sections: sections,
      isMandatory: _isMandatory,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      copiedFromUnitId: existing?.copiedFromUnitId,
      copiedFromChecklistId: existing?.copiedFromChecklistId,
      copiedAt: existing?.copiedAt,
    );
  }

  bool _hasContent() {
    if (_titleController.text.trim().isNotEmpty) return true;
    for (final s in _sections) {
      if (s.titleController.text.trim().isNotEmpty) return true;
      for (final i in s.items) {
        if (i.controller.text.trim().isNotEmpty) return true;
      }
    }
    return false;
  }

  String _generateId(String prefix) =>
      '${prefix}_${DateTime.now().millisecondsSinceEpoch}';

  void _addSection() {
    final controller = TextEditingController();
    if (_isEditMode) controller.addListener(_triggerAutoSave);
    setState(() {
      _sections.add(_EditableSection(
        id: _generateId('s'),
        titleController: controller,
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
    if (_isEditMode) _triggerAutoSave();
  }

  void _addItem(int sectionIndex) {
    final controller = TextEditingController();
    if (_isEditMode) controller.addListener(_triggerAutoSave);
    setState(() {
      _sections[sectionIndex].items.add(_EditableItem(
        id: _generateId('i'),
        controller: controller,
      ));
    });
  }

  void _removeItem(int sectionIndex, int itemIndex) {
    setState(() {
      _sections[sectionIndex].items[itemIndex].controller.dispose();
      _sections[sectionIndex].items.removeAt(itemIndex);
    });
    if (_isEditMode) _triggerAutoSave();
  }

  void _saveAndReturn() {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('יש להזין כותרת לצ\'קליסט')),
      );
      return;
    }

    final result = _buildChecklist();
    if (result == null || result.sections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('יש להוסיף לפחות קטגוריה אחת עם פריט אחד')),
      );
      return;
    }

    Navigator.pop(context, result);
  }

  Future<bool> _onWillPop() async {
    if (_isEditMode || !_hasContent()) return true;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('יצירת צ\'קליסט'),
          content: const Text('יש תוכן שלא נשמר. מה לעשות?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: const Text('ביטול', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'create'),
              child: const Text('צור צ\'קליסט'),
            ),
          ],
        ),
      ),
    );
    if (action == 'create') {
      _saveAndReturn();
      return false; // _saveAndReturn pops if valid
    }
    return action == 'discard';
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.checklist == null;
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: Text(isNew ? 'צ\'קליסט חדש' : 'עריכת צ\'קליסט'),
          ),
          floatingActionButton: isNew
              ? FloatingActionButton.extended(
                  onPressed: _saveAndReturn,
                  icon: const Icon(Icons.check),
                  label: const Text('צור צ\'קליסט'),
                )
              : null,
          floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
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
                onChanged: (v) {
                  setState(() => _isMandatory = v);
                  if (_isEditMode) _triggerAutoSave();
                },
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
