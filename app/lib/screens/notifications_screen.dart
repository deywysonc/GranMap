import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_session.dart';
import '../services/granmap_api.dart';
import '../services/local_store.dart';
import '../services/notifications_service.dart';
import '../theme/granmap_theme.dart';
import '../widgets/granmap_ui.dart';
import 'login_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    this.session,
    this.api,
    this.store,
    this.storageTimeout = const Duration(seconds: 2),
    this.networkTimeout = const Duration(seconds: 6),
  });

  final AppSession? session;
  final GranMapApi? api;
  final LocalStore? store;
  final Duration storageTimeout;
  final Duration networkTimeout;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final AppSession _session;
  late final NotificationsService _service;
  late String? _observedToken;
  late String _observedScope;
  late bool _observedLoggedIn;
  int _generation = 0;
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  bool _marking = false;
  bool _needsLogin = false;
  String? _error;
  Future<void> Function()? _retry;

  @override
  void initState() {
    super.initState();
    _session = widget.session ?? AppSession.instance;
    _service = NotificationsService(
      api: widget.api,
      store: widget.store,
      storageTimeout: widget.storageTimeout,
      networkTimeout: widget.networkTimeout,
    );
    _observedToken = _session.token;
    _observedScope = _session.storageScope;
    _observedLoggedIn = _session.isLoggedIn;
    _session.addListener(_sessionChanged);
    unawaited(_load());
  }

  void _sessionChanged() {
    if (_session.token == _observedToken &&
        _session.storageScope == _observedScope &&
        _session.isLoggedIn == _observedLoggedIn) {
      return;
    }
    _observedToken = _session.token;
    _observedScope = _session.storageScope;
    _observedLoggedIn = _session.isLoggedIn;
    _generation++;
    if (!mounted) return;
    setState(() {
      _items = const [];
      _loading = _observedLoggedIn;
      _marking = false;
      _needsLogin = false;
      _error = null;
      _retry = null;
    });
    unawaited(_load());
  }

  _NotificationRequest? _request() {
    final token = _session.token;
    final scope = _session.storageScope;
    if (token == null || !_session.isLoggedIn) return null;
    return _NotificationRequest(token, scope, ++_generation);
  }

  bool _current(_NotificationRequest request) =>
      mounted &&
      request.generation == _generation &&
      request.token == _session.token &&
      request.scope == _session.storageScope &&
      _session.isLoggedIn;

  Future<void> _load() async {
    if (_marking) return;
    final request = _request();
    if (request == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _items = const [];
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _retry = null;
      _needsLogin = false;
    });
    try {
      try {
        final cached = await _service.readCached(request.scope);
        if (!_current(request)) return;
        if (_items.isEmpty && cached.isNotEmpty) {
          setState(() => _items = cached);
        }
      } catch (_) {
        // Falha local não impede uma consulta válida ao servidor.
      }
      if (!_current(request)) return;
      final items = await _service.fetch(request.token);
      if (!_current(request)) return;
      setState(() {
        _items = items;
        _loading = false;
      });
      _refreshBadge(request);
      await _saveCache(request, items);
    } catch (error) {
      if (!_current(request)) return;
      _showFailure(
        error,
        'Não foi possível sincronizar as notificações. '
        'Confira sua conexão e tente novamente.',
        _load,
      );
    } finally {
      if (_current(request)) setState(() => _loading = false);
    }
  }

  Future<void> _saveCache(
    _NotificationRequest request,
    List<Map<String, dynamic>> items,
  ) async {
    try {
      await _service.saveCached(request.scope, items);
    } catch (_) {
      if (!_current(request)) return;
      setState(() {
        _error =
            'Atualizações recebidas, mas não foi possível salvá-las '
            'neste aparelho. Tente sincronizar novamente.';
        _retry = _load;
        _needsLogin = false;
      });
    }
  }

  Future<void> _markRead(Map<String, dynamic> item) async {
    if (item['read'] == true || _marking || _loading) return;
    final id = NotificationsService.notificationId(item['id']);
    if (id == null) {
      setState(() {
        _error =
            'Esta notificação está indisponível. '
            'Atualize a lista para tentar novamente.';
        _retry = _load;
        _needsLogin = false;
      });
      return;
    }
    await _mark(
      action: (token) => _service.markRead(token, id),
      matches: (candidate) =>
          NotificationsService.notificationId(candidate['id']) == id,
      retry: () => _markRead(item),
    );
  }

  Future<void> _markAll() async {
    if (_marking || _loading || !_items.any((item) => item['read'] != true)) {
      return;
    }
    await _mark(
      action: _service.markAllRead,
      matches: (_) => true,
      retry: _markAll,
    );
  }

  Future<void> _mark({
    required Future<void> Function(String) action,
    required bool Function(Map<String, dynamic>) matches,
    required Future<void> Function() retry,
  }) async {
    final request = _request();
    if (request == null) return;
    setState(() {
      _marking = true;
      _error = null;
      _retry = null;
      _needsLogin = false;
    });
    try {
      await action(request.token);
      if (!_current(request)) return;
      final updated = [
        for (final item in _items)
          if (matches(item)) {...item, 'read': true} else item,
      ];
      setState(() => _items = updated);
      _refreshBadge(request);
      await _saveCache(request, updated);
    } catch (error) {
      if (!_current(request)) return;
      _showFailure(
        error,
        'A leitura não foi confirmada. Confira sua conexão '
        'e tente marcar novamente.',
        retry,
      );
    } finally {
      if (_current(request)) setState(() => _marking = false);
    }
  }

  void _showFailure(
    Object error,
    String message,
    Future<void> Function() retry,
  ) {
    final expired =
        error is ApiException &&
        (error.statusCode == 401 || error.statusCode == 403);
    setState(() {
      _needsLogin = expired;
      _error = expired
          ? 'Sua sessão expirou. Entre novamente para sincronizar '
                'suas notificações.'
          : message;
      _retry = retry;
    });
  }

  void _refreshBadge(_NotificationRequest request) {
    if (!_current(request)) return;
    unawaited(
      Future<void>.sync(_session.refreshNotificationCount)
          .timeout(widget.networkTimeout)
          .catchError((Object _) {}),
    );
  }

  void _runIfCurrent(int generation, Future<void> Function() action) {
    if (mounted && generation == _generation) unawaited(action());
  }

  Future<void> _openLogin() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LoginScreen(session: _session)),
    );
    if (mounted && _session.isLoggedIn && !_loading && !_marking) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = _session.isLoggedIn;
    final displayedGeneration = _generation;
    final retry = _needsLogin ? _openLogin : _retry;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificações'),
        actions: [
          if (loggedIn && _items.any((item) => item['read'] != true))
            TextButton(
              onPressed: _marking || _loading
                  ? null
                  : () => _runIfCurrent(displayedGeneration, _markAll),
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
                GranMapSurface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Entre na sua conta para receber mudanças de sala e '
                        'atualizações oficiais da sua turma.',
                      ),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: () =>
                            _runIfCurrent(displayedGeneration, _openLogin),
                        child: const Text('Entrar na minha conta'),
                      ),
                    ],
                  ),
                )
              else ...[
                if (_loading) ...[
                  if (_items.isEmpty)
                    const Center(child: CircularProgressIndicator())
                  else
                    const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                ],
                if (_error != null) ...[
                  GranMapSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_error!),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _loading || _marking || retry == null
                              ? null
                              : () => _runIfCurrent(displayedGeneration, retry),
                          icon: Icon(
                            _needsLogin
                                ? Icons.login_rounded
                                : Icons.refresh_rounded,
                          ),
                          label: Text(
                            _needsLogin
                                ? 'Entrar novamente'
                                : 'Tentar novamente',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_items.isEmpty && !_loading && _error == null)
                  const GranMapSurface(
                    child: Text('Nenhuma notificação por enquanto.'),
                  ),
                for (final item in _items) ...[
                  Semantics(
                    button: item['read'] != true && !_marking && !_loading,
                    label: '${item['title']}. ${item['body']}',
                    child: GranMapSurface(
                      onTap: _marking || _loading || item['read'] == true
                          ? null
                          : () => _runIfCurrent(
                              displayedGeneration,
                              () => _markRead(item),
                            ),
                      border: Border.all(
                        color: item['read'] == true
                            ? Theme.of(context).colorScheme.outlineVariant
                            : GranMapColors.orange.withValues(alpha: .42),
                      ),
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
                  const SizedBox(height: 10),
                ],
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
    _generation++;
    _session.removeListener(_sessionChanged);
    _service.dispose();
    super.dispose();
  }
}

class _NotificationRequest {
  const _NotificationRequest(this.token, this.scope, this.generation);

  final String token;
  final String scope;
  final int generation;
}
