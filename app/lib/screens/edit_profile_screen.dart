import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/app_session.dart';
import '../services/granmap_api.dart';
import '../theme/granmap_theme.dart';
import '../widgets/granmap_ui.dart';

class EditProfileScreen extends StatefulWidget {
  final AppUser user;

  const EditProfileScreen({super.key, required this.user});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final GranMapApi _api = GranMapApi();
  late final TextEditingController _name;
  late final TextEditingController _group;

  List<String> _courses = const [];
  late String _course;
  late int _semester;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.user.name);
    _group = TextEditingController(text: widget.user.group);
    _course = widget.user.course;
    _semester = widget.user.semester;
    _loadCourses();
  }

  @override
  void dispose() {
    _api.dispose();
    _name.dispose();
    _group.dispose();
    super.dispose();
  }

  Future<void> _loadCourses() async {
    try {
      final courses = await _api.fetchCourses();
      if (!mounted) return;
      setState(() {
        _courses = courses;
        if (!_courses.contains(_course)) _courses = [_course, ..._courses];
      });
    } catch (_) {
      setState(() => _courses = [_course]);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await AppSession.instance.updateProfile(
        name: _name.text.trim(),
        course: _course,
        semester: _semester,
        group: _group.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível salvar o perfil.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Seu perfil')),
      body: GranMapBackdrop(
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  const GranMapPageHeader(
                    eyebrow: 'Personalização',
                    title: 'Edite sua jornada',
                    subtitle: 'Esses dados deixam horários, turmas e atalhos mais relevantes para você.',
                  ),
                  const SizedBox(height: 22),
                  GranMapFadeSlide(
                    child: GranMapSurface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const GranMapIconBadge(
                                icon: Icons.badge_outlined,
                                color: GranMapColors.orange,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Identidade acadêmica',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: _name,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Nome',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _course,
                            decoration: const InputDecoration(
                              labelText: 'Curso',
                              prefixIcon: Icon(Icons.school_outlined),
                            ),
                            items: (_courses.isEmpty ? [_course] : _courses)
                                .map(
                                  (course) => DropdownMenuItem(
                                    value: course,
                                    child: Text(course),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _course = value);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            initialValue: _semester,
                            decoration: const InputDecoration(
                              labelText: 'Semestre',
                              prefixIcon: Icon(Icons.timeline_rounded),
                            ),
                            items: [
                              for (var semester = 1; semester <= 12; semester++)
                                DropdownMenuItem(
                                  value: semester,
                                  child: Text('$semesterº semestre'),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _semester = value);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _group,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Turma',
                              prefixIcon: Icon(Icons.groups_outlined),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .errorContainer,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.check_rounded),
                            label: Text(
                              _saving ? 'Salvando...' : 'Salvar alterações',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
