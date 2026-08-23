import 'package:flutter/material.dart';

import '../services/app_session.dart';
import '../services/granmap_api.dart';
import '../services/local_store.dart';
import '../theme/granmap_theme.dart';
import '../widgets/granmap_ui.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final GranMapApi _api = GranMapApi();
  final LocalStore _store = LocalStore();
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  bool _marking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = AppSession.instance.token;
    if (token == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final items = await _api.fetchNotifications(token);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
      await _store.saveNotifications(AppSession.instance.storageScope, items);
      await AppSession.instance.refreshNotificationCount();
    } catch (_) {
      final cached = await _store.readNotifications(
        AppSession.instance.storageScope,
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _items = cached;
          _error = cached.isEmpty
              ? 'As notificações não puderam ser sincronizadas agora.'
              : null;
        });
      }
    }
  }

  Future<void> _markRead(Map<String, dynamic> item) async {
    if (item['read'] == true || _marking) return;
    final token = AppSession.instance.token;
    if (token == null) return;
    setState(() => _marking = true);
    try {
      await _api.markNotificationRead(token, (item['id'] as num).toInt());
      await _load();
    } catch (_) {
      if (mounted) _message('Não foi possível marcar a notificação agora.');
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  Future<void> _markAll() async {
    if (_marking) return;
    final token = AppSession.instance.token;
    if (token == null) return;
    setState(() => _marking = true);
    try {
      await _api.markAllNotificationsRead(token);
      await _load();
    } catch (_) {
      if (mounted) _message('Não foi possível atualizar as notificações.');
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = AppSession.instance.isLoggedIn;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Atualizações da faculdade'),
        actions: [
          if (_items.any((item) => item['read'] != true))
            TextButton(
              onPressed: _marking ? null : _markAll,
              child: Text(_marking ? 'Atualizando…' : 'Marcar lidas'),
            ),
        ],
      ),
      body: GranMapBackdrop(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
            children: [
              if (!loggedIn)
                const GranMapSurface(
                  child: Text(
                    'Entre na sua conta para receber mudanças de sala e atualizações oficiais da sua turma.',
                  ),
                )
              else if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_error != null)
                GranMapSurface(child: Text(_error!))
              else if (_items.isEmpty)
                const GranMapSurface(
                  child: Text(
                    'Nenhuma atualização por aqui. Sua grade está tranquila.',
                  ),
                )
              else
                for (final item in _items) ...[
                  Semantics(
                    button: item['read'] != true,
                    label: '${item['title']}. ${item['body']}',
                    child: GranMapSurface(
                      border: Border.all(
                        color: item['read'] == true
                            ? Theme.of(context).colorScheme.outlineVariant
                            : GranMapColors.orange.withValues(alpha: .42),
                      ),
                      child: InkWell(
                        onTap: () => _markRead(item),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GranMapIconBadge(
                              icon: _icon(item['kind']?.toString() ?? ''),
                              color: item['read'] == true
                                  ? GranMapColors.sky
                                  : GranMapColors.orange,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['title']?.toString() ?? 'Atualização',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(item['body']?.toString() ?? ''),
                                  const SizedBox(height: 7),
                                  Text(
                                    item['read'] == true
                                        ? 'Lida'
                                        : 'Toque para marcar como lida',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _icon(String kind) {
    if (kind.contains('deleted')) return Icons.event_busy_rounded;
    if (kind.contains('created')) return Icons.event_available_rounded;
    return Icons.campaign_rounded;
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }
}
