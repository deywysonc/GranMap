import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/app_session.dart';
import '../services/granmap_api.dart';
import '../theme/granmap_theme.dart';
import '../widgets/granmap_ui.dart';

class EditProfileScreen extends StatefulWidget {
  final AppUser user;
  final AppSession? session;
  final GranMapApi? api;

  const EditProfileScreen({
    super.key,
    required this.user,
    this.session,
    this.api,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final GranMapApi _api;
  late final TextEditingController _name;
  late final TextEditingController _group;

  List<String> _courses = const [];
  late String _course;
  late int _semester;
  bool _saving = false;
  bool _loadingCourses = false;
  String? _error;
  String? _coursesError;
  String? _nameError;
  String? _groupError;

  AppSession get _session => widget.session ?? AppSession.instance;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? GranMapApi();
    _name = TextEditingController(text: widget.user.name);
    _group = TextEditingController(text: widget.user.group);
    _course = widget.user.course;
    _semester = widget.user.semester;
    _loadCourses();
  }

  @override
  void dispose() {
    if (widget.api == null) _api.dispose();
    _name.dispose();
    _group.dispose();
    super.dispose();
  }

  Future<void> _loadCourses() async {
    if (_loadingCourses) return;
    setState(() {
      _loadingCourses = true;
      _coursesError = null;
    });
    try {
      final courses = await _api.fetchCourses().timeout(
        const Duration(seconds: 5),
      );
      if (!mounted) return;
      setState(() {
        _courses = courses;
        if (!_courses.contains(_course)) _courses = [_course, ..._courses];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _courses = [_course];
        _coursesError = 'Não foi possível atualizar os cursos.';
      });
    } finally {
      if (mounted) setState(() => _loadingCourses = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final nameLength = _name.text.trim().length;
    final groupLength = _group.text.trim().length;
    setState(() {
      _nameError = nameLength < 2 || nameLength > 100
          ? 'Informe um nome entre 2 e 100 caracteres.'
          : null;
      _groupError = groupLength == 0 || groupLength > 60
          ? 'Informe uma turma com até 60 caracteres.'
          : null;
      _saving = _nameError == null && _groupError == null;
      _error = null;
    });
    if (!_saving) return;
    FocusScope.of(context).unfocus();

    try {
      await _session.updateProfile(
        name: _name.text.trim(),
        course: _course,
        semester: _semester,
        group: _group.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } on SessionException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
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
                            maxLength: 100,
                            enabled: !_saving,
                            textInputAction: TextInputAction.next,
                            textCapitalization: TextCapitalization.words,
                            onChanged: (_) {
                              if (_nameError != null || _error != null) {
                                setState(() {
                                  _nameError = null;
                                  _error = null;
                                });
                              }
                            },
                            decoration: InputDecoration(
                              labelText: 'Nome',
                              errorText: _nameError,
                              counterText: '',
                              prefixIcon: const Icon(
                                Icons.person_outline_rounded,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_loadingCourses) const LinearProgressIndicator(),
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
                            onChanged: _saving
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(() => _course = value);
                                    }
                                  },
                          ),
                          if (_coursesError != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _coursesError!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _saving || _loadingCourses
                                  ? null
                                  : _loadCourses,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Tentar atualizar os cursos'),
                            ),
                          ],
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            initialValue: _semester,
                            decoration: const InputDecoration(
                              labelText: 'Semestre',
                              prefixIcon: Icon(Icons.timeline_rounded),
                            ),
                            items: [
                              for (var semester = 1; semester <= 20; semester++)
                                DropdownMenuItem(
                                  value: semester,
                                  child: Text('$semesterº semestre'),
                                ),
                            ],
                            onChanged: _saving
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(() => _semester = value);
                                    }
                                  },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _group,
                            maxLength: 60,
                            enabled: !_saving,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _save(),
                            onChanged: (_) {
                              if (_groupError != null || _error != null) {
                                setState(() {
                                  _groupError = null;
                                  _error = null;
                                });
                              }
                            },
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              labelText: 'Turma',
                              errorText: _groupError,
                              counterText: '',
                              prefixIcon: const Icon(Icons.groups_outlined),
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
