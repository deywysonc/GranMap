import 'package:flutter/material.dart';

import '../services/app_session.dart';
import '../services/granmap_api.dart';
import '../theme/granmap_theme.dart';
import '../widgets/granmap_ui.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final GranMapApi _api = GranMapApi();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _group = TextEditingController(text: 'EC4A');

  List<String> _courses = const [];
  String? _course;
  int _semester = 1;
  bool _loadingCourses = true;
  bool _saving = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  @override
  void dispose() {
    _api.dispose();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _group.dispose();
    super.dispose();
  }

  Future<void> _loadCourses() async {
    try {
      final courses = await _api.fetchCourses();
      if (!mounted) return;
      setState(() {
        _courses = courses;
        _course = courses.isEmpty ? null : courses.first;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível carregar os cursos.');
      }
    } finally {
      if (mounted) setState(() => _loadingCourses = false);
    }
  }

  Future<void> _register() async {
    if (_course == null ||
        _name.text.trim().isEmpty ||
        _email.text.trim().isEmpty ||
        _password.text.length < 6 ||
        _group.text.trim().isEmpty) {
      setState(() {
        _error = 'Preencha todos os campos. A senha deve ter 6+ caracteres.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await AppSession.instance.register(
        name: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        course: _course!,
        semester: _semester,
        group: _group.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
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
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Nome',
                                prefixIcon: Icon(Icons.badge_outlined),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(
                                labelText: 'E-mail',
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _password,
                              obscureText: _hidePassword,
                              decoration: InputDecoration(
                                labelText: 'Senha (mínimo 6 caracteres)',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  onPressed: () => setState(
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
                                onChanged: (value) =>
                                    setState(() => _course = value),
                              ),
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
                                        semester <= 12;
                                        semester++
                                      )
                                        DropdownMenuItem(
                                          value: semester,
                                          child: Text('$semesterº'),
                                        ),
                                    ],
                                    onChanged: (value) {
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
                                    textCapitalization:
                                        TextCapitalization.characters,
                                    decoration: const InputDecoration(
                                      labelText: 'Turma',
                                      hintText: 'EC4A',
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
                                onPressed: _saving ? null : _register,
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
