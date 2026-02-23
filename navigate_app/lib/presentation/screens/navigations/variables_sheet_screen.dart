import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/variables_sheet.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../services/astronomical_service.dart';
import '../../../services/variables_sheet_pdf_service.dart';
import '../../widgets/signature_pad.dart';
import '../../widgets/form_section.dart';
import '../../widgets/editable_table.dart';

/// מסך דף משתנים — נספח 24
class VariablesSheetScreen extends StatefulWidget {
  final domain.Navigation navigation;

  const VariablesSheetScreen({super.key, required this.navigation});

  @override
  State<VariablesSheetScreen> createState() => _VariablesSheetScreenState();
}

class _VariablesSheetScreenState extends State<VariablesSheetScreen> {
  final NavigationRepository _repository = NavigationRepository();
  final PageController _pageController = PageController();
  late domain.Navigation _navigation;
  late VariablesSheet _sheet;
  int _currentPage = 0;
  bool _isSaving = false;
  bool _isDirty = false;

  // Controllers for text fields — page 1
  final _preliminaryTrainingCtrl = TextEditingController();
  final _medicCheckNotesCtrl = TextEditingController();
  final _weightCheckNotesCtrl = TextEditingController();
  final _driverBriefingNotesCtrl = TextEditingController();
  final _departureTimeCtrl = TextEditingController();
  final _checkpointPassageTimeCtrl = TextEditingController();
  final _navigationEndTimeCtrl = TextEditingController();
  final _emergencyGatheringPointCtrl = TextEditingController();
  final _ceilingTimeCtrl = TextEditingController();
  final _safetyCeilingTimeCtrl = TextEditingController();
  final _weatherNotesCtrl = TextEditingController();

  // Controllers for text fields — page 2
  final _commandPostAxisCtrl = TextEditingController();
  final _helicopterPhoneCtrl = TextEditingController();
  final _helicopterFrequencyCtrl = TextEditingController();
  final _helicopterInstructionsCtrl = TextEditingController();
  final _fireInstructionsCtrl = TextEditingController();
  final _incidentsAndResponsesCtrl = TextEditingController();

  // Controllers for text fields — page 3
  final _casualtySweepByCtrl = TextEditingController();
  final _casualtySweepDateCtrl = TextEditingController();
  final _casualtySweepTimeCtrl = TextEditingController();
  final _searchRescueInstructionsCtrl = TextEditingController();
  final _vehicleNumber1Ctrl = TextEditingController();
  final _vehicleNumber2Ctrl = TextEditingController();
  final _commanderNotesCtrl = TextEditingController();
  final _previousLessonsCtrl = TextEditingController();
  final _safetyBriefingCtrl = TextEditingController();
  final _coordinationNotesCtrl = TextEditingController();

  // Mutable lists for editable tables
  List<PreparationScheduleRow> _preparationSchedule = [];
  List<SystemCheckRow> _systemCheckTable = [];
  List<CommunicationRow> _communicationTable = [];
  List<NeighboringForceRow> _neighboringForces = [];
  List<AdditionalDataRow> _additionalData = [];

  @override
  void initState() {
    super.initState();
    _navigation = widget.navigation;
    _sheet = _navigation.variablesSheet ?? const VariablesSheet();
    _initControllers();
    _initTables();

    // Auto-fill on first open
    if (_navigation.variablesSheet == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoFill());
    }
  }

  void _initControllers() {
    _preliminaryTrainingCtrl.text = _sheet.preliminaryTraining ?? '';
    _medicCheckNotesCtrl.text = _sheet.medicCheckNotes ?? '';
    _weightCheckNotesCtrl.text = _sheet.weightCheckNotes ?? '';
    _driverBriefingNotesCtrl.text = _sheet.driverBriefingNotes ?? '';
    _departureTimeCtrl.text = _sheet.departureTime ?? '';
    _checkpointPassageTimeCtrl.text = _sheet.checkpointPassageTime ?? '';
    _navigationEndTimeCtrl.text = _sheet.navigationEndTime ?? '';
    _emergencyGatheringPointCtrl.text = _sheet.emergencyGatheringPoint ?? '';
    _ceilingTimeCtrl.text = _sheet.ceilingTime ?? '';
    _safetyCeilingTimeCtrl.text = _sheet.safetyCeilingTime ?? '';
    _weatherNotesCtrl.text = _sheet.weatherNotes ?? '';

    _commandPostAxisCtrl.text = _sheet.commandPostAxis ?? '';
    _helicopterPhoneCtrl.text = _sheet.helicopterPhone ?? '';
    _helicopterFrequencyCtrl.text = _sheet.helicopterFrequency ?? '';
    _helicopterInstructionsCtrl.text = _sheet.helicopterInstructions ?? '';
    _fireInstructionsCtrl.text = _sheet.fireInstructions ?? '';
    _incidentsAndResponsesCtrl.text = _sheet.incidentsAndResponses ?? '';

    _casualtySweepByCtrl.text = _sheet.casualtySweepBy ?? '';
    _casualtySweepDateCtrl.text = _sheet.casualtySweepDate ?? '';
    _casualtySweepTimeCtrl.text = _sheet.casualtySweepTime ?? '';
    _searchRescueInstructionsCtrl.text = _sheet.searchRescueInstructions ?? '';
    _vehicleNumber1Ctrl.text = _sheet.vehicleNumber1 ?? '';
    _vehicleNumber2Ctrl.text = _sheet.vehicleNumber2 ?? '';
    _commanderNotesCtrl.text = _sheet.commanderNotes ?? '';
    _previousLessonsCtrl.text = _sheet.previousNavigatorLessons ?? '';
    _safetyBriefingCtrl.text = _sheet.safetyBriefingSupplement ?? '';
    _coordinationNotesCtrl.text = _sheet.coordinationSheetNotes ?? '';
  }

  void _initTables() {
    _preparationSchedule = _sheet.preparationSchedule.isNotEmpty
        ? List.from(_sheet.preparationSchedule)
        : List.generate(4, (_) => const PreparationScheduleRow());
    _systemCheckTable = _sheet.systemCheckTable.isNotEmpty
        ? List.from(_sheet.systemCheckTable)
        : [
            const SystemCheckRow(systemName: 'מכשיר ניווט'),
            const SystemCheckRow(systemName: 'GPS'),
            const SystemCheckRow(systemName: 'מפה'),
            const SystemCheckRow(systemName: 'סוללה'),
            const SystemCheckRow(systemName: 'תקשורת'),
          ];
    _communicationTable = _sheet.communicationTable.isNotEmpty
        ? List.from(_sheet.communicationTable)
        : List.generate(3, (_) => const CommunicationRow());
    _neighboringForces = _sheet.neighboringForces.isNotEmpty
        ? List.from(_sheet.neighboringForces)
        : [const NeighboringForceRow()];
    _additionalData = _sheet.additionalData.isNotEmpty
        ? List.from(_sheet.additionalData)
        : [const AdditionalDataRow()];
  }

  @override
  void dispose() {
    _pageController.dispose();
    _preliminaryTrainingCtrl.dispose();
    _medicCheckNotesCtrl.dispose();
    _weightCheckNotesCtrl.dispose();
    _driverBriefingNotesCtrl.dispose();
    _departureTimeCtrl.dispose();
    _checkpointPassageTimeCtrl.dispose();
    _navigationEndTimeCtrl.dispose();
    _emergencyGatheringPointCtrl.dispose();
    _ceilingTimeCtrl.dispose();
    _safetyCeilingTimeCtrl.dispose();
    _weatherNotesCtrl.dispose();
    _commandPostAxisCtrl.dispose();
    _helicopterPhoneCtrl.dispose();
    _helicopterFrequencyCtrl.dispose();
    _helicopterInstructionsCtrl.dispose();
    _fireInstructionsCtrl.dispose();
    _incidentsAndResponsesCtrl.dispose();
    _casualtySweepByCtrl.dispose();
    _casualtySweepDateCtrl.dispose();
    _casualtySweepTimeCtrl.dispose();
    _searchRescueInstructionsCtrl.dispose();
    _vehicleNumber1Ctrl.dispose();
    _vehicleNumber2Ctrl.dispose();
    _commanderNotesCtrl.dispose();
    _previousLessonsCtrl.dispose();
    _safetyBriefingCtrl.dispose();
    _coordinationNotesCtrl.dispose();
    super.dispose();
  }

  VariablesSheet _collectSheet() {
    return _sheet.copyWith(
      preliminaryTraining: _preliminaryTrainingCtrl.text.isNotEmpty ? _preliminaryTrainingCtrl.text : null,
      medicCheckNotes: _medicCheckNotesCtrl.text.isNotEmpty ? _medicCheckNotesCtrl.text : null,
      weightCheckNotes: _weightCheckNotesCtrl.text.isNotEmpty ? _weightCheckNotesCtrl.text : null,
      driverBriefingNotes: _driverBriefingNotesCtrl.text.isNotEmpty ? _driverBriefingNotesCtrl.text : null,
      preparationSchedule: _preparationSchedule,
      departureTime: _departureTimeCtrl.text.isNotEmpty ? _departureTimeCtrl.text : null,
      checkpointPassageTime: _checkpointPassageTimeCtrl.text.isNotEmpty ? _checkpointPassageTimeCtrl.text : null,
      navigationEndTime: _navigationEndTimeCtrl.text.isNotEmpty ? _navigationEndTimeCtrl.text : null,
      emergencyGatheringPoint: _emergencyGatheringPointCtrl.text.isNotEmpty ? _emergencyGatheringPointCtrl.text : null,
      ceilingTime: _ceilingTimeCtrl.text.isNotEmpty ? _ceilingTimeCtrl.text : null,
      safetyCeilingTime: _safetyCeilingTimeCtrl.text.isNotEmpty ? _safetyCeilingTimeCtrl.text : null,
      weatherNotes: _weatherNotesCtrl.text.isNotEmpty ? _weatherNotesCtrl.text : null,
      systemCheckTable: _systemCheckTable,
      communicationTable: _communicationTable,
      neighboringForces: _neighboringForces,
      commandPostAxis: _commandPostAxisCtrl.text.isNotEmpty ? _commandPostAxisCtrl.text : null,
      helicopterPhone: _helicopterPhoneCtrl.text.isNotEmpty ? _helicopterPhoneCtrl.text : null,
      helicopterFrequency: _helicopterFrequencyCtrl.text.isNotEmpty ? _helicopterFrequencyCtrl.text : null,
      helicopterInstructions: _helicopterInstructionsCtrl.text.isNotEmpty ? _helicopterInstructionsCtrl.text : null,
      fireInstructions: _fireInstructionsCtrl.text.isNotEmpty ? _fireInstructionsCtrl.text : null,
      incidentsAndResponses: _incidentsAndResponsesCtrl.text.isNotEmpty ? _incidentsAndResponsesCtrl.text : null,
      additionalData: _additionalData,
      casualtySweepBy: _casualtySweepByCtrl.text.isNotEmpty ? _casualtySweepByCtrl.text : null,
      casualtySweepDate: _casualtySweepDateCtrl.text.isNotEmpty ? _casualtySweepDateCtrl.text : null,
      casualtySweepTime: _casualtySweepTimeCtrl.text.isNotEmpty ? _casualtySweepTimeCtrl.text : null,
      searchRescueInstructions: _searchRescueInstructionsCtrl.text.isNotEmpty ? _searchRescueInstructionsCtrl.text : null,
      vehicleNumber1: _vehicleNumber1Ctrl.text.isNotEmpty ? _vehicleNumber1Ctrl.text : null,
      vehicleNumber2: _vehicleNumber2Ctrl.text.isNotEmpty ? _vehicleNumber2Ctrl.text : null,
      commanderNotes: _commanderNotesCtrl.text.isNotEmpty ? _commanderNotesCtrl.text : null,
      previousNavigatorLessons: _previousLessonsCtrl.text.isNotEmpty ? _previousLessonsCtrl.text : null,
      safetyBriefingSupplement: _safetyBriefingCtrl.text.isNotEmpty ? _safetyBriefingCtrl.text : null,
      coordinationSheetNotes: _coordinationNotesCtrl.text.isNotEmpty ? _coordinationNotesCtrl.text : null,
      lastUpdatedAt: DateTime.now(),
    );
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final sheet = _collectSheet();
      final updated = _navigation.copyWith(
        variablesSheet: sheet,
        updatedAt: DateTime.now(),
      );
      await _repository.update(updated);
      _navigation = updated;
      _sheet = sheet;
      _isDirty = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('דף משתנים נשמר'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בשמירה: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _autoFill() async {
    final nav = _navigation;
    final tc = nav.timeCalculationSettings;

    // Season
    String? season;
    if (tc.isSummer) {
      season = 'קיץ';
    } else {
      season = 'חורף';
    }

    // Night/day — added to weather notes
    final dayNight = tc.isNightNavigation ? 'לילה' : 'יום';

    // PTT
    final pttNote = nav.communicationSettings.walkieTalkieEnabled ? 'ווקי-טוקי מופעל' : null;

    // Astronomical calculations — use center of Israel as default
    // In production, this would use the navigation area's center coordinates
    const defaultLat = 31.5; // Israel center
    const defaultLng = 34.9;
    final navDate = nav.activeStartTime ?? nav.trainingStartTime ?? DateTime.now();

    String? sunriseStr;
    String? sunsetStr;
    double? moonIllum;
    try {
      final sunrise = AstronomicalService.getSunrise(defaultLat, defaultLng, navDate);
      final sunset = AstronomicalService.getSunset(defaultLat, defaultLng, navDate);
      moonIllum = AstronomicalService.getMoonIllumination(navDate);
      final fmt = DateFormat('HH:mm');
      sunriseStr = fmt.format(sunrise);
      sunsetStr = fmt.format(sunset);
    } catch (_) {}

    // Safety ceiling time
    String? ceilingTime;
    if (nav.safetyTime != null) {
      if (nav.safetyTime!.type == 'hours' && nav.safetyTime!.hours != null) {
        ceilingTime = '${nav.safetyTime!.hours} שעות';
      }
    }

    // Notes auto-fill
    final autoNotes = [
      'ניווט $dayNight',
      if (pttNote != null) pttNote,
      if (nav.enabledPositionSources.isNotEmpty)
        'מקורות מיקום: ${nav.enabledPositionSources.join(", ")}',
    ].join(' | ');

    setState(() {
      _sheet = _sheet.copyWith(
        season: season,
        weatherNotes: autoNotes.isNotEmpty ? autoNotes : null,
        sunriseTime: sunriseStr,
        sunsetTime: sunsetStr,
        moonIllumination: moonIllum,
        ceilingTime: ceilingTime,
      );
      // Update controllers
      _ceilingTimeCtrl.text = ceilingTime ?? '';
      _weatherNotesCtrl.text = autoNotes;
    });

    _isDirty = true;
  }

  Future<void> _exportPdf() async {
    // Save first
    final sheet = _collectSheet();
    try {
      final service = VariablesSheetPdfService();
      final path = await service.exportPdf(
        navigation: _navigation,
        sheet: sheet,
      );
      if (path != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF יוצא בהצלחה')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בייצוא: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (_isDirty) await _save();
      },
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('דף משתנים — נספח 24'),
            actions: [
              if (_isSaving)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                )
              else ...[
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _autoFill,
                  tooltip: 'מילוי אוטומטי',
                ),
                IconButton(
                  icon: const Icon(Icons.save),
                  onPressed: _save,
                  tooltip: 'שמירה',
                ),
                IconButton(
                  icon: const Icon(Icons.picture_as_pdf),
                  onPressed: _exportPdf,
                  tooltip: 'ייצוא PDF',
                ),
              ],
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (page) {
                    setState(() => _currentPage = page);
                    if (_isDirty) _save();
                  },
                  children: [
                    _buildPage1(),
                    _buildPage2(),
                    _buildPage3(),
                  ],
                ),
              ),
              // Page indicator
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  border: Border(top: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (i) => Container(
                    width: 10, height: 10,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentPage == i ? Colors.blue : Colors.grey.shade400,
                    ),
                  )),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ====== PAGE 1: Sections 1-9 ======
  Widget _buildPage1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('עמוד 1 — הכנה, זמנים, מזג אוויר',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
          const SizedBox(height: 12),

          // Section 1 — הכנה מקדימה
          FormSection(
            sectionNumber: 1,
            title: 'הכנה מקדימה',
            child: Column(
              children: [
                _buildTextField('אימון מקדים', _preliminaryTrainingCtrl),
                const SizedBox(height: 8),
                _buildCheckField('בדיקת חובש', _sheet.medicCheckDone, (v) {
                  setState(() => _sheet = _sheet.copyWith(medicCheckDone: v));
                  _isDirty = true;
                }),
                _buildTextField('הערות חובש', _medicCheckNotesCtrl),
                const SizedBox(height: 8),
                _buildCheckField('בדיקת משקל', _sheet.weightCheckDone, (v) {
                  setState(() => _sheet = _sheet.copyWith(weightCheckDone: v));
                  _isDirty = true;
                }),
                _buildTextField('הערות משקל', _weightCheckNotesCtrl),
                const SizedBox(height: 8),
                _buildCheckField('תדריך נהגים', _sheet.driverBriefingDone, (v) {
                  setState(() => _sheet = _sheet.copyWith(driverBriefingDone: v));
                  _isDirty = true;
                }),
                _buildTextField('הערות נהגים', _driverBriefingNotesCtrl),
              ],
            ),
          ),

          // Section 2 — לוח זמנים הכנה
          FormSection(
            sectionNumber: 2,
            title: 'לוח זמנים הכנה',
            child: EditableTable(
              columns: const [
                EditableColumn(header: 'סוג הכנה', flex: 1.5),
                EditableColumn(header: 'תאריך ביצוע', flex: 1),
                EditableColumn(header: 'הערות', flex: 1),
              ],
              rowCount: _preparationSchedule.length,
              getCellValue: (row, col) {
                final r = _preparationSchedule[row];
                switch (col) {
                  case 0: return r.preparationType;
                  case 1: return r.executionDate;
                  case 2: return r.notes;
                  default: return null;
                }
              },
              onCellChanged: (row, col, value) {
                setState(() {
                  final r = _preparationSchedule[row];
                  switch (col) {
                    case 0: _preparationSchedule[row] = r.copyWith(preparationType: value); break;
                    case 1: _preparationSchedule[row] = r.copyWith(executionDate: value); break;
                    case 2: _preparationSchedule[row] = r.copyWith(notes: value); break;
                  }
                });
                _isDirty = true;
              },
            ),
          ),

          // Sections 3-5 — שעות
          FormSection(
            sectionNumber: 3,
            title: 'שעת יציאה',
            child: _buildTextField('HH:MM', _departureTimeCtrl),
          ),
          FormSection(
            sectionNumber: 4,
            title: 'שעת מעבר',
            child: _buildTextField('HH:MM', _checkpointPassageTimeCtrl),
          ),
          FormSection(
            sectionNumber: 5,
            title: 'שעת סיום ניווט',
            child: _buildTextField('HH:MM', _navigationEndTimeCtrl),
          ),

          // Section 6 — נקודת כינוס חירום
          FormSection(
            sectionNumber: 6,
            title: 'נקודת כינוס חירום',
            child: _buildTextField('נ"צ / תיאור', _emergencyGatheringPointCtrl),
          ),

          // Section 7 — שעת "גג"
          FormSection(
            sectionNumber: 7,
            title: 'שעת "גג" ובטיחות',
            child: Column(
              children: [
                _buildTextField('שעת "גג"', _ceilingTimeCtrl),
                const SizedBox(height: 8),
                _buildTextField('גג בטיחות', _safetyCeilingTimeCtrl),
              ],
            ),
          ),

          // Sections 8-9 — מזג אוויר ואסטרונומיה
          FormSection(
            sectionNumber: 8,
            title: 'מזג אוויר ואסטרונומיה',
            child: Column(
              children: [
                _buildInfoRow('עונה', _sheet.season ?? '—'),
                _buildInfoRow('שקיעה', _sheet.sunsetTime ?? '—'),
                _buildInfoRow('זריחה', _sheet.sunriseTime ?? '—'),
                _buildInfoRow('תאורת ירח', _sheet.moonIllumination != null
                    ? '${(_sheet.moonIllumination! * 100).toStringAsFixed(0)}%'
                    : '—'),
                if (_sheet.weatherTemperature != null)
                  _buildInfoRow('טמפרטורה', _sheet.weatherTemperature!),
                if (_sheet.weatherConditions != null)
                  _buildInfoRow('מזג אוויר', _sheet.weatherConditions!),
                if (_sheet.weatherWindSpeed != null)
                  _buildInfoRow('רוח', '${_sheet.weatherWindSpeed} מ/ש'),
                const SizedBox(height: 8),
                _buildTextField('דגשים מזג אוויר', _weatherNotesCtrl, maxLines: 3),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ====== PAGE 2: Sections 10-17 ======
  Widget _buildPage2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('עמוד 2 — מערכות, תקשורת, בטיחות',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
          const SizedBox(height: 12),

          // Section 10 — בדיקת מערכות
          FormSection(
            sectionNumber: 10,
            title: 'בדיקת מערכות',
            child: EditableTable(
              columns: const [
                EditableColumn(header: 'מערכת', flex: 1.5),
                EditableColumn(header: 'נבדק', flex: 0.7, isCheckbox: true),
                EditableColumn(header: 'תקין', flex: 0.7, isCheckbox: true),
                EditableColumn(header: 'קליטת GPS', flex: 1),
              ],
              rowCount: _systemCheckTable.length,
              getCellValue: (row, col) {
                final r = _systemCheckTable[row];
                switch (col) {
                  case 0: return r.systemName;
                  case 3: return r.gpsReception;
                  default: return null;
                }
              },
              getCellBoolValue: (row, col) {
                final r = _systemCheckTable[row];
                switch (col) {
                  case 1: return r.checkPerformed;
                  case 2: return r.findingsOk;
                  default: return null;
                }
              },
              onCellChanged: (row, col, value) {
                setState(() {
                  final r = _systemCheckTable[row];
                  switch (col) {
                    case 0: _systemCheckTable[row] = r.copyWith(systemName: value); break;
                    case 3: _systemCheckTable[row] = r.copyWith(gpsReception: value); break;
                  }
                });
                _isDirty = true;
              },
              onCellBoolChanged: (row, col, value) {
                setState(() {
                  final r = _systemCheckTable[row];
                  switch (col) {
                    case 1: _systemCheckTable[row] = r.copyWith(checkPerformed: value); break;
                    case 2: _systemCheckTable[row] = r.copyWith(findingsOk: value); break;
                  }
                });
                _isDirty = true;
              },
              canAddRows: true,
              onAddRow: () {
                setState(() => _systemCheckTable.add(const SystemCheckRow()));
                _isDirty = true;
              },
              canRemoveRows: _systemCheckTable.length > 1,
              onRemoveRow: (row) {
                if (_systemCheckTable.length > 1) {
                  setState(() => _systemCheckTable.removeAt(row));
                  _isDirty = true;
                }
              },
            ),
          ),

          // Section 11 — תקשורת
          FormSection(
            sectionNumber: 11,
            title: 'רשתות תקשורת',
            child: EditableTable(
              columns: const [
                EditableColumn(header: 'סוג רשת', flex: 1),
                EditableColumn(header: 'שם רשת', flex: 1),
                EditableColumn(header: 'תדר/ערוץ', flex: 1),
              ],
              rowCount: _communicationTable.length,
              getCellValue: (row, col) {
                final r = _communicationTable[row];
                switch (col) {
                  case 0: return r.networkType;
                  case 1: return r.networkName;
                  case 2: return r.frequency;
                  default: return null;
                }
              },
              onCellChanged: (row, col, value) {
                setState(() {
                  final r = _communicationTable[row];
                  switch (col) {
                    case 0: _communicationTable[row] = r.copyWith(networkType: value); break;
                    case 1: _communicationTable[row] = r.copyWith(networkName: value); break;
                    case 2: _communicationTable[row] = r.copyWith(frequency: value); break;
                  }
                });
                _isDirty = true;
              },
              canAddRows: true,
              onAddRow: () {
                setState(() => _communicationTable.add(const CommunicationRow()));
                _isDirty = true;
              },
              canRemoveRows: _communicationTable.length > 1,
              onRemoveRow: (row) {
                if (_communicationTable.length > 1) {
                  setState(() => _communicationTable.removeAt(row));
                  _isDirty = true;
                }
              },
            ),
          ),

          // Section 12 — כוחות שכנים
          FormSection(
            sectionNumber: 12,
            title: 'כוחות שכנים',
            child: EditableTable(
              columns: const [
                EditableColumn(header: 'כוח', flex: 1),
                EditableColumn(header: 'מיקום', flex: 1),
                EditableColumn(header: 'מרחק', flex: 0.7),
                EditableColumn(header: 'כיוון', flex: 0.7),
                EditableColumn(header: 'סוג אימון', flex: 1),
              ],
              rowCount: _neighboringForces.length,
              getCellValue: (row, col) {
                final r = _neighboringForces[row];
                switch (col) {
                  case 0: return r.forceName;
                  case 1: return r.location;
                  case 2: return r.distance;
                  case 3: return r.direction;
                  case 4: return r.trainingType;
                  default: return null;
                }
              },
              onCellChanged: (row, col, value) {
                setState(() {
                  final r = _neighboringForces[row];
                  switch (col) {
                    case 0: _neighboringForces[row] = r.copyWith(forceName: value); break;
                    case 1: _neighboringForces[row] = r.copyWith(location: value); break;
                    case 2: _neighboringForces[row] = r.copyWith(distance: value); break;
                    case 3: _neighboringForces[row] = r.copyWith(direction: value); break;
                    case 4: _neighboringForces[row] = r.copyWith(trainingType: value); break;
                  }
                });
                _isDirty = true;
              },
              canAddRows: true,
              onAddRow: () {
                setState(() => _neighboringForces.add(const NeighboringForceRow()));
                _isDirty = true;
              },
              canRemoveRows: _neighboringForces.length > 1,
              onRemoveRow: (row) {
                if (_neighboringForces.length > 1) {
                  setState(() => _neighboringForces.removeAt(row));
                  _isDirty = true;
                }
              },
            ),
          ),

          // Section 13 — ציר פיקוד
          FormSection(
            sectionNumber: 13,
            title: 'ציר תנועת הפיקוד',
            child: _buildTextField('ציר / תיאור', _commandPostAxisCtrl, maxLines: 2),
          ),

          // Section 14 — מסוק חילוץ
          FormSection(
            sectionNumber: 14,
            title: 'מסוק חילוץ',
            child: Column(
              children: [
                _buildTextField('טלפון', _helicopterPhoneCtrl),
                const SizedBox(height: 8),
                _buildTextField('תדר', _helicopterFrequencyCtrl),
                const SizedBox(height: 8),
                _buildTextField('הנחיות', _helicopterInstructionsCtrl, maxLines: 2),
              ],
            ),
          ),

          // Section 15 — פקודות אש
          FormSection(
            sectionNumber: 15,
            title: 'פקודות אש',
            child: _buildTextField('פרט פקודות אש', _fireInstructionsCtrl, maxLines: 3),
          ),

          // Section 16 — תקריות
          FormSection(
            sectionNumber: 16,
            title: 'תקריות ותגובות',
            child: _buildTextField('פרט תקריות ותגובות', _incidentsAndResponsesCtrl, maxLines: 3),
          ),

          // Section 17 — נתונים נוספים
          FormSection(
            sectionNumber: 17,
            title: 'נתונים נוספים להכרת הגזרה',
            child: EditableTable(
              columns: const [
                EditableColumn(header: 'שלב ניווט', flex: 1),
                EditableColumn(header: 'פריט נתון', flex: 1.5),
                EditableColumn(header: 'פעילות מניעה', flex: 1.5),
              ],
              rowCount: _additionalData.length,
              getCellValue: (row, col) {
                final r = _additionalData[row];
                switch (col) {
                  case 0: return r.navigationPhase;
                  case 1: return r.dataItem;
                  case 2: return r.preventionActivity;
                  default: return null;
                }
              },
              onCellChanged: (row, col, value) {
                setState(() {
                  final r = _additionalData[row];
                  switch (col) {
                    case 0: _additionalData[row] = r.copyWith(navigationPhase: value); break;
                    case 1: _additionalData[row] = r.copyWith(dataItem: value); break;
                    case 2: _additionalData[row] = r.copyWith(preventionActivity: value); break;
                  }
                });
                _isDirty = true;
              },
              canAddRows: true,
              onAddRow: () {
                setState(() => _additionalData.add(const AdditionalDataRow()));
                _isDirty = true;
              },
              canRemoveRows: _additionalData.length > 1,
              onRemoveRow: (row) {
                if (_additionalData.length > 1) {
                  setState(() => _additionalData.removeAt(row));
                  _isDirty = true;
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  // ====== PAGE 3: Sections 18-25 ======
  Widget _buildPage3() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('עמוד 3 — בטיחות, חתימות, תיאום',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
          const SizedBox(height: 12),

          // Section 18 — סריקת נפגעים
          FormSection(
            sectionNumber: 18,
            title: 'סריקת נפגעים',
            child: Column(
              children: [
                _buildTextField('סורק', _casualtySweepByCtrl),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _buildTextField('תאריך', _casualtySweepDateCtrl)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildTextField('שעה', _casualtySweepTimeCtrl)),
                  ],
                ),
              ],
            ),
          ),

          // Section 19 — חיפוש וחילוץ
          FormSection(
            sectionNumber: 19,
            title: 'הנחיות חיפוש וחילוץ',
            child: _buildTextField('הנחיות', _searchRescueInstructionsCtrl, maxLines: 3),
          ),

          // Section 20 — אישור רכב
          FormSection(
            sectionNumber: 20,
            title: 'אישור רכב',
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _buildTextField('רכב 1', _vehicleNumber1Ctrl)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildTextField('רכב 2', _vehicleNumber2Ctrl)),
                  ],
                ),
                const SizedBox(height: 8),
                _buildCheckField('הגבלה אחרי 23:00', _sheet.afterElevenRestriction, (v) {
                  setState(() => _sheet = _sheet.copyWith(afterElevenRestriction: v));
                  _isDirty = true;
                }),
              ],
            ),
          ),

          // Section 21 — הערות מפקד
          FormSection(
            sectionNumber: 21,
            title: 'הערות מפקד',
            child: Column(
              children: [
                _buildTextField('הערות', _commanderNotesCtrl, maxLines: 3),
                const SizedBox(height: 8),
                _buildTextField('לקחי מנווטים קודמים', _previousLessonsCtrl, maxLines: 3),
              ],
            ),
          ),

          // Section 22 — משלים תדריך בטיחות
          FormSection(
            sectionNumber: 22,
            title: 'משלים תדריך בטיחות',
            child: _buildTextField('פרט', _safetyBriefingCtrl, maxLines: 4),
          ),

          // Section 23 — חתימת מנהל ניווט
          FormSection(
            sectionNumber: 23,
            title: 'חתימת מנהל הניווט',
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: _sheet.managerSignature?.name ?? '',
                        decoration: const InputDecoration(
                          labelText: 'שם',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) {
                          _sheet = _sheet.copyWith(
                            managerSignature: (_sheet.managerSignature ?? const SignatureData())
                                .copyWith(name: v),
                          );
                          _isDirty = true;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: _sheet.managerSignature?.rank ?? '',
                        decoration: const InputDecoration(
                          labelText: 'דרגה',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) {
                          _sheet = _sheet.copyWith(
                            managerSignature: (_sheet.managerSignature ?? const SignatureData())
                                .copyWith(rank: v),
                          );
                          _isDirty = true;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text('חתימה:', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 4),
                SignaturePad(
                  initialBase64: _sheet.managerSignature?.signatureBase64,
                  onChanged: (base64) {
                    _sheet = _sheet.copyWith(
                      managerSignature: (_sheet.managerSignature ?? const SignatureData())
                          .copyWith(signatureBase64: base64),
                    );
                    _isDirty = true;
                  },
                ),
              ],
            ),
          ),

          // Section 24 — חתימת מאשר
          FormSection(
            sectionNumber: 24,
            title: 'חתימת מאשר (מ"פ / סמ"פ)',
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: _sheet.approverSignature?.name ?? '',
                        decoration: const InputDecoration(
                          labelText: 'שם',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) {
                          _sheet = _sheet.copyWith(
                            approverSignature: (_sheet.approverSignature ?? const SignatureData())
                                .copyWith(name: v),
                          );
                          _isDirty = true;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: _sheet.approverSignature?.rank ?? '',
                        decoration: const InputDecoration(
                          labelText: 'דרגה',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) {
                          _sheet = _sheet.copyWith(
                            approverSignature: (_sheet.approverSignature ?? const SignatureData())
                                .copyWith(rank: v),
                          );
                          _isDirty = true;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text('חתימה:', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 4),
                SignaturePad(
                  initialBase64: _sheet.approverSignature?.signatureBase64,
                  onChanged: (base64) {
                    _sheet = _sheet.copyWith(
                      approverSignature: (_sheet.approverSignature ?? const SignatureData())
                          .copyWith(signatureBase64: base64),
                    );
                    _isDirty = true;
                  },
                ),
              ],
            ),
          ),

          // Section 25 — דף תיאום
          FormSection(
            sectionNumber: 25,
            title: 'דף תיאום',
            child: _buildTextField('הערות תיאום', _coordinationNotesCtrl, maxLines: 4),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ====== Helpers ======
  Widget _buildTextField(String label, TextEditingController controller, {int maxLines = 1}) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      onChanged: (_) => _isDirty = true,
    );
  }

  Widget _buildCheckField(String label, bool? value, ValueChanged<bool> onChanged) {
    return CheckboxListTile(
      title: Text(label, style: const TextStyle(fontSize: 14)),
      value: value ?? false,
      onChanged: (v) => onChanged(v ?? false),
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
