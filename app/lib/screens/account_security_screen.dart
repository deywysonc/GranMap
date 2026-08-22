import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_session.dart';
import '../services/granmap_api.dart';
import '../theme/granmap_theme.dart';
import '../widgets/granmap_ui.dart';

class AccountSecurityScreen extends StatefulWidget {
  const AccountSecurityScreen({super.key});

  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  final GranMapApi _api = GranMapApi();
  List<Map<String, dynamic>> _sessions = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    final token = AppSession.instance.token;
    if (token == null) return;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final sessions = await _api.fetchSessions(token);
      if (mounted) setState(() => _sessions = sessions);
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conta e segurança')),
      body: GranMapBackdrop(
        child: RefreshIndicator(
          onRefresh: _loadSessions,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
            children: [
              const GranMapPageHeader(
                eyebrow: 'PRIVACIDADE E ACESSO',
                title: 'Você controla sua conta',
                subtitle: 'Revise acessos, proteja sua senha e decida quais dados permanecem no GranMap.',
              ),
              const SizedBox(height: 18),
              GranMapSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const GranMapSectionTitle(title: 'Sessões ativas'),
                    const SizedBox(height: 4),
                    Text(
                      'Acessos que ainda podem usar sua conta.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    if (_loading)
                      const LinearProgressIndicator()
                    else if (_error != null)
                      _InlineMessage(message: _error!, onRetry: _loadSessions)
                    else
                      for (final session in _sessions)
                        _SessionTile(
                          session: session,
                          busy: _busy,
                          onRevoke: () => _revokeSession(session),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              GranMapSurface(
                child: Column(
                  children: [
                    _ActionTile(
                      icon: Icons.password_rounded,
                      title: 'Alterar senha',
                      subtitle: 'Encerra automaticamente os outros acessos.',
                      onTap: _busy ? null : _changePassword,
                    ),
                    const Divider(height: 1),
                    _ActionTile(
                      icon: Icons.download_rounded,
                      title: 'Exportar meus dados',
                      subtitle: 'Copia um arquivo JSON com perfil, rotas e contribuições.',
                      onTap: _busy ? null : _exportData,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              GranMapSurface(
                border: Border.all(
                  color: GranMapColors.danger.withValues(alpha: .28),
                ),
                child: _ActionTile(
                  icon: Icons.delete_forever_rounded,
                  iconColor: GranMapColors.danger,
                  title: 'Excluir minha conta',
                  subtitle: 'Remove os dados pessoais e anonimiza contribuições que precisam permanecer na auditoria.',
                  onTap: _busy ? null : _deleteAccount,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _revokeSession(Map<String, dynamic> session) async {
    final token = AppSession.instance.token;
    if (token == null) return;
    final current = session['current'] == true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(current ? 'Encerrar esta sessão?' : 'Revogar acesso?'),
        content: Text(
          current
              ? 'Você precisará entrar novamente neste aparelho.'
              : 'O outro aparelho perderá o acesso imediatamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revogar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _guard(() async {
      await _api.revokeSession(token, (session['id'] as num).toInt());
      if (current) {
        await AppSession.instance.logout();
        if (mounted) Navigator.of(context).pop();
      } else {
        await _loadSessions();
      }
    }, success: current ? null : 'Acesso revogado.');
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirmation = TextEditingController();
    final values = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Alterar senha'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Senha atual'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: next,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Nova senha',
                helperText: 'Use pelo menos 10 caracteres.',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirmation,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirmar senha'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, [
              current.text,
              next.text,
              confirmation.text,
            ]),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    current.dispose();
    next.dispose();
    confirmation.dispose();
    if (values == null) return;
    if (values[1].length < 10 || values[1] != values[2]) {
      _snack('Confira a confirmação e use pelo menos 10 caracteres.');
      return;
    }
    final token = AppSession.instance.token;
    if (token == null) return;
    await _guard(
      () => _api.changePassword(
        token: token,
        currentPassword: values[0],
        newPassword: values[1],
      ),
      success: 'Senha alterada. Os outros acessos foram encerrados.',
    );
    await _loadSessions();
  }

  Future<void> _exportData() async {
    final token = AppSession.instance.token;
    if (token == null) return;
    await _guard(() async {
      final data = await _api.exportAccount(token);
      const encoder = JsonEncoder.withIndent('  ');
      await Clipboard.setData(ClipboardData(text: encoder.convert(data)));
    }, success: 'Seus dados foram copiados em formato JSON.');
  }

  Future<void> _deleteAccount() async {
    final password = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir conta permanentemente?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Favoritos, histórico e notificações serão removidos. Contribuições ficam anônimas para preservar a auditoria acadêmica.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Digite sua senha para confirmar',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: GranMapColors.danger,
            ),
            onPressed: () => Navigator.pop(context, password.text),
            child: const Text('Excluir conta'),
          ),
        ],
      ),
    );
    password.dispose();
    if (value == null || value.isEmpty) return;
    final token = AppSession.instance.token;
    if (token == null) return;
    await _guard(() async {
      await _api.deleteAccount(token: token, password: value);
      await AppSession.instance.logout();
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _guard(Future<void> Function() action, {String? success}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (success != null && mounted) _snack(success);
    } catch (error) {
      if (mounted) _snack(_messageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _messageFor(Object error) => error is ApiException
      ? error.message
      : 'Não foi possível concluir agora.';

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SessionTile extends StatelessWidget {
  final Map<String, dynamic> session;
  final bool busy;
  final VoidCallback onRevoke;

  const _SessionTile({
    required this.session,
    required this.busy,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final current = session['current'] == true;
    final lastSeen = DateTime.tryParse(
      session['last_seen_at']?.toString() ?? '',
    );
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: GranMapIconBadge(
        icon: current ? Icons.smartphone_rounded : Icons.devices_rounded,
        color: current ? GranMapColors.mint : GranMapColors.violet,
      ),
      title: Text(current ? 'Este aparelho' : 'Outro acesso'),
      subtitle: Text(
        lastSeen == null
            ? 'Sessão ativa'
            : 'Último uso em ${_formatDate(lastSeen.toLocal())}',
      ),
      trailing: TextButton(
        onPressed: busy ? null : onRevoke,
        child: Text(current ? 'Sair' : 'Revogar'),
      ),
    );
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} às ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor = GranMapColors.orange,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: GranMapIconBadge(icon: icon, color: iconColor),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _InlineMessage extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _InlineMessage({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(message)),
        TextButton(onPressed: onRetry, child: const Text('Tentar novamente')),
      ],
    );
  }
}
