import 'package:flutter/material.dart';

import '../services/app_session.dart';
import '../services/granmap_api.dart';
import '../theme/granmap_theme.dart';
import '../widgets/granmap_ui.dart';
import 'register_screen.dart';
import 'password_reset_screen.dart';

class LoginScreen extends StatefulWidget {
  final AppSession? session;

  const LoginScreen({super.key, this.session});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _hidePassword = true;
  String? _error;
  String? _emailError;
  String? _passwordError;

  AppSession get _session => widget.session ?? AppSession.instance;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loading) return;
    final email = _email.text.trim();
    final emailError = email.isEmpty
        ? 'Informe seu e-mail.'
        : !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
        ? 'Informe um e-mail válido.'
        : null;
    final passwordError = _password.text.trim().isEmpty
        ? 'Informe sua senha.'
        : null;

    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
      _loading = emailError == null && passwordError == null;
      _error = null;
    });
    if (!_loading) return;
    FocusScope.of(context).unfocus();

    try {
      await _session.login(email: email, password: _password.text);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } on SessionException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Não foi possível acessar o GranMap Backend.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: GranMapBackdrop(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 36),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: GranMapFadeSlide(
                  child: Column(
                    children: [
                      const GranMapBrandMark(size: 66),
                      const SizedBox(height: 20),
                      Text(
                        'Bom ter você de volta.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 7),
                      Text(
                        'Entre para sincronizar sua rotina na faculdade.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 26),
                      GranMapSurface(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            TextField(
                              controller: _email,
                              enabled: !_loading,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              onSubmitted: (_) =>
                                  FocusScope.of(context).nextFocus(),
                              onChanged: (_) {
                                if (_emailError != null || _error != null) {
                                  setState(() {
                                    _emailError = null;
                                    _error = null;
                                  });
                                }
                              },
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
                              enabled: !_loading,
                              obscureText: _hidePassword,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
                              onSubmitted: (_) => _login(),
                              onChanged: (_) {
                                if (_passwordError != null || _error != null) {
                                  setState(() {
                                    _passwordError = null;
                                    _error = null;
                                  });
                                }
                              },
                              decoration: InputDecoration(
                                labelText: 'Senha',
                                errorText: _passwordError,
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  tooltip: _hidePassword
                                      ? 'Mostrar senha'
                                      : 'Ocultar senha',
                                  onPressed: _loading
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
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _loading
                                    ? null
                                    : () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const PasswordResetScreen(),
                                        ),
                                      ),
                                child: const Text('Esqueci minha senha'),
                              ),
                            ),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 220),
                              child: _error == null
                                  ? const SizedBox.shrink()
                                  : Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(11),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .errorContainer,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
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
                                    ),
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _loading ? null : _login,
                                icon: _loading
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.arrow_forward_rounded),
                                label: Text(
                                  _loading ? 'Entrando...' : 'Entrar',
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: _loading
                                    ? null
                                    : () async {
                                        final registered =
                                            await Navigator.of(context)
                                                .push<bool>(
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        RegisterScreen(
                                                          session: _session,
                                                        ),
                                                  ),
                                                );
                                        if (!context.mounted) return;
                                        if (registered == true) {
                                          Navigator.of(context).pop(true);
                                        }
                                      },
                                child: const Text('Criar minha conta'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const GranMapStatusPill(
                        label: 'Mapa e rotas funcionam sem conta',
                        icon: Icons.shield_outlined,
                        color: GranMapColors.mint,
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
