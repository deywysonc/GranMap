import 'package:flutter/material.dart';

import '../services/app_session.dart';
import '../services/granmap_api.dart';
import '../theme/granmap_theme.dart';
import '../widgets/granmap_ui.dart';

class RegisterScreen extends StatefulWidget {
  final AppSession? session;
  final GranMapApi? api;

  const RegisterScreen({super.key, this.session, this.api});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  late final GranMapApi _api;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _group = TextEditingController(text: 'EC4A');

  List<String> _courses = const [];
  String? _course;
  int _semester = 1;
  bool _loadingCourses = false;
  bool _saving = false;
  bool _hidePassword = true;
  String? _error;
  String? _coursesError;
  String? _nameError;
  String? _emailError;
  String? _passwordError;
  String? _groupError;

  AppSession get _session => widget.session ?? AppSession.instance;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? GranMapApi();
    _loadCourses();
  }

  @override
  void dispose() {
    if (widget.api == null) _api.dispose();
    _name.dispose();
    _email.dispose();
    _password.dispose();
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
        _course = courses.isEmpty ? null : courses.first;
        if (courses.isEmpty) {
          _coursesError = 'Nenhum curso disponível. Tente novamente.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _coursesError = 'Não foi possível carregar os cursos.';
          if (_courses.isEmpty) {
            _courses = const [
              'Engenharia da Computação',
              'Administração',
              'Agronomia',
            ];
            _course ??= _courses.first;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _loadingCourses = false);
    }
  }

  Future<void> _register() async {
    if (_saving || _loadingCourses) return;
    final email = _email.text.trim();
    setState(() {
      final nameLength = _name.text.trim().length;
      _nameError = nameLength < 2 || nameLength > 100
          ? 'Informe um nome entre 2 e 100 caracteres.'
          : null;
      _emailError = email.isEmpty
          ? 'Informe seu e-mail.'
          : email.length < 5 ||
                email.length > 160 ||
                !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
          ? 'Informe um e-mail válido.'
          : null;
      _passwordError = _password.text.isEmpty
          ? 'Informe uma senha.'
          : _password.text.length < 10 || _password.text.length > 128
          ? 'Use uma senha entre 10 e 128 caracteres.'
          : null;
      final groupLength = _group.text.trim().length;
      _groupError = groupLength == 0 || groupLength > 60
          ? 'Informe uma turma com até 60 caracteres.'
          : null;
      _error =
          _course == null ||
              _course!.trim().length < 2 ||
              _course!.trim().length > 160
          ? 'Selecione um curso válido para continuar.'
          : null;
      _saving = [
        _nameError,
        _emailError,
        _passwordError,
        _groupError,
        _error,
      ].every((error) => error == null);
    });
    if (!_saving) return;
    FocusScope.of(context).unfocus();

    try {
      await _session.register(
        name: _name.text.trim(),
        email: email,
        password: _password.text,
        course: _course!,
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
      setState(() => _error = 'Não foi possível criar a conta.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: GranMapBackdrop(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 36),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: GranMapFadeSlide(
                  child: Column(
                    children: [
                      const GranMapBrandMark(size: 60),
                      const SizedBox(height: 18),
                      Text(
                        'Crie seu espaço na faculdade.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 7),
                      Text(
                        'Leva menos de um minuto.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      GranMapSurface(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _FormSection(
                              icon: Icons.person_rounded,
                              title: 'Sua identidade',
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _name,
                              maxLength: 100,
                              enabled: !_saving,
                              textInputAction: TextInputAction.next,
                              textCapitalization: TextCapitalization.words,
                              decoration: InputDecoration(
                                labelText: 'Nome',
                                errorText: _nameError,
                                prefixIcon: const Icon(Icons.badge_outlined),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _email,
                              maxLength: 160,
                              enabled: !_saving,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.email],
                              decoration: InputDecoration(
                                labelText: 'E-mail',
                                errorText: _emailError,
                                prefixIcon: const Icon(Icons.email_outlined),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _password,
                              maxLength: 128,
                              enabled: !_saving,
                              obscureText: _hidePassword,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.newPassword],
                              decoration: InputDecoration(
                                labelText: 'Senha (mínimo 10 caracteres)',
                                errorText: _passwordError,
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  tooltip: _hidePassword
                                      ? 'Mostrar senha'
                                      : 'Ocultar senha',
                                  onPressed: _saving
                                      ? null
                                      : () => setState(
                                          () => _hidePassword = !_hidePassword,
                                        ),
                                  icon: Icon(
                                    _hidePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Divider(),
                            ),
                            const _FormSection(
                              icon: Icons.school_rounded,
                              title: 'Seu contexto acadêmico',
                            ),
                            const SizedBox(height: 14),
                            if (_loadingCourses)
                              const LinearProgressIndicator()
                            else
                              DropdownButtonFormField<String>(
                                initialValue: _course,
                                decoration: const InputDecoration(
                                  labelText: 'Curso',
                                  prefixIcon: Icon(Icons.auto_stories_outlined),
                                ),
                                items: _courses
                                    .map(
                                      (course) => DropdownMenuItem(
                                        value: course,
                                        child: Text(course),
                                      ),
                                    )
                                    .toList(),
                                onChanged: _saving
                                    ? null
                                    : (value) =>
                                          setState(() => _course = value),
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
                                label: const Text('Tentar carregar os cursos'),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<int>(
                                    initialValue: _semester,
                                    decoration: const InputDecoration(
                                      labelText: 'Semestre',
                                    ),
                                    items: [
                                      for (
                                        var semester = 1;
                                        semester <= 20;
                                        semester++
                                      )
                                        DropdownMenuItem(
                                          value: semester,
                                          child: Text('$semesterº'),
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
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _group,
                                    maxLength: 60,
                                    enabled: !_saving,
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: (_) => _register(),
                                    textCapitalization:
                                        TextCapitalization.characters,
                                    decoration: InputDecoration(
                                      labelText: 'Turma',
                                      hintText: 'EC4A',
                                      errorText: _groupError,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 220),
                              child: _error == null
                                  ? const SizedBox.shrink()
                                  : Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: Text(
                                        _error!,
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _saving || _loadingCourses
                                    ? null
                                    : _register,
                                icon: _saving
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.rocket_launch_rounded),
                                label: Text(
                                  _saving
                                      ? 'Criando sua conta...'
                                      : 'Começar no GranMap',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormSection extends StatelessWidget {
  final IconData icon;
  final String title;

  const _FormSection({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GranMapIconBadge(icon: icon, color: GranMapColors.orange, size: 38),
        const SizedBox(width: 10),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}
