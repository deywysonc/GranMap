import 'package:flutter/material.dart';

import '../services/granmap_api.dart';
import '../theme/granmap_theme.dart';
import '../widgets/granmap_ui.dart';

class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({super.key});

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final GranMapApi _api = GranMapApi();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _token = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirmation = TextEditingController();
  bool _codeRequested = false;
  bool _busy = false;
  bool _hidePassword = true;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _api.dispose();
    _email.dispose();
    _token.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar senha')),
      body: GranMapBackdrop(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 36),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Column(
                  children: [
                    const GranMapPageHeader(
                      eyebrow: 'ACESSO SEGURO',
                      title: 'Crie uma nova senha',
                      subtitle: 'Solicite um código e use-o em até 30 minutos. Todas as sessões antigas serão encerradas.',
                    ),
                    const SizedBox(height: 18),
                    GranMapSurface(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          TextField(
                            controller: _email,
                            enabled: !_codeRequested && !_busy,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                              labelText: 'E-mail',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                          ),
                          if (_codeRequested) ...[
                            const SizedBox(height: 12),
                            TextField(
                              controller: _token,
                              autocorrect: false,
                              decoration: const InputDecoration(
                                labelText: 'Código recebido',
                                prefixIcon: Icon(Icons.key_rounded),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _password,
                              obscureText: _hidePassword,
                              autofillHints: const [AutofillHints.newPassword],
                              decoration: InputDecoration(
                                labelText: 'Nova senha',
                                helperText: 'Use pelo menos 10 caracteres.',
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
                            const SizedBox(height: 12),
                            TextField(
                              controller: _confirmation,
                              obscureText: _hidePassword,
                              onSubmitted: (_) => _confirm(),
                              decoration: const InputDecoration(
                                labelText: 'Confirmar nova senha',
                                prefixIcon: Icon(Icons.verified_user_outlined),
                              ),
                            ),
                          ],
                          if (_message != null || _error != null) ...[
                            const SizedBox(height: 13),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color:
                                    (_error == null
                                            ? GranMapColors.mint
                                            : GranMapColors.danger)
                                        .withValues(alpha: .1),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Text(_error ?? _message!),
                            ),
                          ],
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _busy
                                  ? null
                                  : (_codeRequested ? _confirm : _requestCode),
                              icon: Icon(
                                _codeRequested
                                    ? Icons.lock_reset_rounded
                                    : Icons.mark_email_read_outlined,
                              ),
                              label: Text(
                                _busy
                                    ? 'Aguarde…'
                                    : (_codeRequested
                                          ? 'Salvar nova senha'
                                          : 'Enviar código'),
                              ),
                            ),
                          ),
                          if (_codeRequested)
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                      _codeRequested = false;
                                      _token.clear();
                                      _message = null;
                                      _error = null;
                                    }),
                              child: const Text('Usar outro e-mail'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _requestCode() async {
    if (!_email.text.contains('@')) {
      setState(() => _error = 'Informe um e-mail válido.');
      return;
    }
    await _guard(() async {
      final result = await _api.requestPasswordReset(_email.text.trim());
      final developmentToken = result['development_token']?.toString();
      if (developmentToken != null) _token.text = developmentToken;
      setState(() {
        _codeRequested = true;
        _message = developmentToken == null ? result['message']?.toString() : 'Ambiente de demonstração: o código foi preenchido automaticamente.';
      });
    });
  }

  Future<void> _confirm() async {
    if (_token.text.trim().isEmpty ||
        _password.text.length < 10 ||
        _password.text != _confirmation.text) {
      setState(() {
        _error = 'Confira o código e a confirmação da nova senha.';
      });
      return;
    }
    await _guard(() async {
      await _api.confirmPasswordReset(
        token: _token.text.trim(),
        newPassword: _password.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Senha alterada. Entre novamente.')),
      );
      Navigator.of(context).pop();
    });
  }

  Future<void> _guard(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is ApiException
              ? error.message
              : 'Não foi possível concluir agora.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
