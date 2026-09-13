import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../ai_service.dart';
import '../db.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Create or edit a single meal.
///
/// Pass [existing] to edit a saved meal, or [initialDate] to log a meal on a
/// past day from the calendar. The date and time are always editable, which is
/// what makes backfilling a missed day possible.
class MealEditorPage extends StatefulWidget {
  const MealEditorPage({super.key, this.existing, this.initialDate});

  final Meal? existing;
  final DateTime? initialDate;

  @override
  State<MealEditorPage> createState() => _MealEditorPageState();
}

class _MealEditorPageState extends State<MealEditorPage> {
  XFile? _photo; // newly picked photo, if any
  String? _savedPhotoPath; // photo already stored with the meal
  final _ingredients = TextEditingController();
  bool _busy = false;
  String? _error;

  // Estimate fields (editable after analysis, or typed by hand)
  final _desc = TextEditingController();
  final _protein = TextEditingController();
  final _fiber = TextEditingController();
  final _cal = TextEditingController();
  String _confidence = '';
  String _note = '';

  late DateTime _eatenAt;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final m = widget.existing;
    if (m != null) {
      _eatenAt = m.eatenAt;
      _savedPhotoPath = m.photoPath;
      _ingredients.text = m.ingredients;
      _desc.text = m.description;
      _protein.text = '${m.proteinG}';
      _fiber.text = '${m.fiberG}';
      _cal.text = '${m.calories}';
      _confidence = m.confidence;
    } else {
      final now = DateTime.now();
      final d = widget.initialDate;
      // A meal backfilled onto another day defaults to noon on that day.
      _eatenAt = d == null || dateOnly(d) == dateOnly(now)
          ? now
          : DateTime(d.year, d.month, d.day, 12, 0);
    }
  }

  @override
  void dispose() {
    _ingredients.dispose();
    _desc.dispose();
    _protein.dispose();
    _fiber.dispose();
    _cal.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource src) async {
    final x = await ImagePicker()
        .pickImage(source: src, maxWidth: 1280, imageQuality: 80);
    if (x != null) setState(() => _photo = x);
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _eatenAt,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'When did you eat this?',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_eatenAt),
      helpText: 'What time?',
    );
    if (!mounted) return;
    setState(() => _eatenAt = DateTime(date.year, date.month, date.day,
        time?.hour ?? _eatenAt.hour, time?.minute ?? _eatenAt.minute));
  }

  Future<void> _analyze() async {
    if (_photo == null &&
        _savedPhotoPath == null &&
        _ingredients.text.trim().isEmpty) {
      setState(() => _error = 'Add a photo or type the ingredients first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = _photo != null
          ? await _photo!.readAsBytes()
          : (_savedPhotoPath != null && File(_savedPhotoPath!).existsSync()
              ? await File(_savedPhotoPath!).readAsBytes()
              : null);
      final r = await AiService.analyzeMeal(
        imageBytes: bytes,
        mimeType: _photo?.mimeType ?? 'image/jpeg',
        ingredients: _ingredients.text,
      );
      setState(() {
        _desc.text = r['description']?.toString() ?? 'Meal';
        _protein.text = '${r['protein_g'] ?? 0}';
        _fiber.text = '${r['fiber_g'] ?? 0}';
        _cal.text = '${r['calories'] ?? 0}';
        _confidence = r['confidence']?.toString() ?? '';
        _note = r['note']?.toString() ?? '';
      });
    } catch (e) {
      setState(() => _error = AiException.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    var path = _savedPhotoPath;
    if (_photo != null) {
      final dir = await getApplicationDocumentsDirectory();
      path =
          p.join(dir.path, 'meal_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await File(_photo!.path).copy(path);
    }
    final meal = Meal(
      id: widget.existing?.id,
      eatenAt: _eatenAt,
      description: _desc.text.trim().isEmpty ? 'Meal' : _desc.text.trim(),
      ingredients: _ingredients.text.trim(),
      proteinG: int.tryParse(_protein.text) ?? 0,
      fiberG: int.tryParse(_fiber.text) ?? 0,
      calories: int.tryParse(_cal.text) ?? 0,
      confidence: _confidence.isEmpty ? 'manual' : _confidence,
      photoPath: path,
    );
    if (_editing) {
      await AppDb.instance.updateMeal(meal);
    } else {
      await AppDb.instance.insertMeal(meal);
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await confirmDelete(
      context,
      title: 'Delete this meal?',
      body: 'It will be removed from your day totals.',
    );
    if (!ok || !mounted) return;
    await AppDb.instance.deleteMeal(widget.existing!.id!);
    if (mounted) Navigator.pop(context, true);
  }

  Color _confidenceColor() {
    switch (_confidence.toLowerCase()) {
      case 'high':
        return Palette.mint;
      case 'medium':
        return Palette.peach;
      default:
        return Palette.berry;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasEstimate = _desc.text.isNotEmpty;
    final shownPhoto = _photo != null
        ? File(_photo!.path)
        : (_savedPhotoPath != null && File(_savedPhotoPath!).existsSync()
            ? File(_savedPhotoPath!)
            : null);

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit meal ✏️' : 'Log a meal 🍽️'),
        actions: [
          if (_editing)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Delete meal',
              color: Palette.berry,
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          // When it was eaten. Tap to move a meal to another day or time.
          SoftCard(
            onTap: _pickDateTime,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Palette.lavender.withValues(alpha: .16)),
                  alignment: Alignment.center,
                  child: const Text('🗓️', style: TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${relativeDay(_eatenAt)} · ${DateFormat('h:mm a').format(_eatenAt)}',
                          style: theme.textTheme.titleMedium),
                      Text(DateFormat('EEEE, MMMM d, y').format(_eatenAt),
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(Icons.edit_calendar_rounded, color: scheme.primary),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => _pick(ImageSource.camera),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: shownPhoto != null
                  ? Image.file(shownPhoto,
                      height: 220, width: double.infinity, fit: BoxFit.cover)
                  : Container(
                      height: 170,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: .07),
                        border: Border.all(
                            color: scheme.primary.withValues(alpha: .35),
                            width: 2),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('📸', style: TextStyle(fontSize: 42)),
                          const SizedBox(height: 8),
                          Text('Snap your plate',
                              style: theme.textTheme.titleMedium),
                          Text('or type the ingredients below',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(ImageSource.camera),
                  style:
                      OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(ImageSource.gallery),
                  style:
                      OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  icon: const Icon(Icons.photo_library_rounded),
                  label: const Text('Gallery'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ingredients,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Ingredients and amounts (optional)',
              hintText: '2 eggs\n100 g chicken breast\n1 cup rice\n1 tbsp oil',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _analyze,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_awesome_rounded),
            label: Text(_busy
                ? 'Thinking…'
                : hasEstimate
                    ? 'Re-estimate'
                    : 'Estimate nutrition'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!,
                  style: const TextStyle(
                      color: Palette.berry, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 22),
          SoftCard(
            color: Palette.lavender.withValues(alpha: .12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Estimate ✨', style: theme.textTheme.titleMedium),
                    const Spacer(),
                    if (_confidence.isNotEmpty)
                      Pill(
                          label: '$_confidence confidence',
                          dense: true,
                          color: _confidenceColor()),
                  ],
                ),
                if (_note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_note,
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                  ),
                const SizedBox(height: 14),
                TextField(
                  controller: _desc,
                  minLines: 1,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      labelText: 'Meal name', alignLabelWithHint: true),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _num(_protein, 'Protein', 'g')),
                    const SizedBox(width: 8),
                    Expanded(child: _num(_fiber, 'Fiber', 'g')),
                    const SizedBox(width: 8),
                    Expanded(child: _num(_cal, 'Energy', 'kcal')),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                    'Edit any number before saving. Estimates are approximate.',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(_editing ? 'Save changes' : 'Save meal'),
          ),
        ],
      ),
    );
  }

  Widget _num(TextEditingController c, String label, String unit) => TextField(
        controller: c,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
            labelText: label,
            suffixText: unit,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 16)),
      );
}

/// Opens the editor. Returns true when something was saved or deleted.
Future<bool> openMealEditor(BuildContext context,
    {Meal? existing, DateTime? initialDate}) async {
  final saved = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) =>
          MealEditorPage(existing: existing, initialDate: initialDate),
      fullscreenDialog: existing == null,
    ),
  );
  return saved == true;
}
