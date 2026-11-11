import 'dart:async';

import 'package:flutter/foundation.dart';

import '../community/community_models.dart';
import 'app_session.dart';
import 'community_service.dart';

/// Foreground-only retries: no background tracking or permanent loading UI.
class CommunitySyncCoordinator extends ChangeNotifier {
  CommunitySyncCoordinator({
    AppSession? session,
    CommunityService? service,
    this.interval = const Duration(seconds: 20),
    this.timeout = const Duration(seconds: 12),
  }) : _session = session ?? AppSession.instance,
       _service = service ?? CommunityService(session: session),
       _ownsService = service == null;

  static final instance = CommunitySyncCoordinator();
  final AppSession _session;
  final CommunityService _service;
  final bool _ownsService;
  final Duration interval;
  final Duration timeout;
  Timer? _timer;
  bool _started = false;
  bool _foreground = true;
  bool _disposed = false;
  int _generation = 0;
  int? _runningGeneration;
  String? _account;
  CommunitySnapshot? lastSnapshot;
  String? snapshotScope;

  String get _accountKey => '${_session.storageScope}:${_session.token}';

  void start() {
    if (_disposed || _started) return;
    _started = true;
    _foreground = true;
    _account = _accountKey;
    _session.addListener(_sessionChanged);
    _schedule();
    unawaited(syncNow());
  }

  void setForeground(bool foreground) {
    if (_disposed || _foreground == foreground) return;
    _foreground = foreground;
    _generation++;
    _schedule();
    if (foreground) unawaited(syncNow());
  }

  void _sessionChanged() {
    if (_account == _accountKey) return;
    _account = _accountKey;
    _generation++;
    lastSnapshot = null;
    snapshotScope = null;
    notifyListeners();
    unawaited(syncNow());
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (!_started || !_foreground || _disposed) return;
    _timer = Timer.periodic(interval, (_) => unawaited(syncNow()));
  }

  Future<void> syncNow() async {
    if (_disposed || !_started || !_foreground || !_session.isLoggedIn) return;
    final generation = _generation;
    final account = _accountKey;
    final scope = _session.storageScope;
    if (_runningGeneration == generation) return;
    _runningGeneration = generation;
    bool current() =>
        !_disposed &&
        _started &&
        _foreground &&
        generation == _generation &&
        account == _accountKey;
    try {
      // Only drain an actual outbox, not fetch every user's feed on every tick.
      final pending = await _service.hasPendingWork().timeout(timeout);
      if (!current() || !pending) return;
      final snapshot = await _service.load().timeout(timeout);
      if (!current()) return;
      lastSnapshot = snapshot;
      snapshotScope = scope;
      notifyListeners();
    } catch (_) {
      // Durable operations stay queued. Next tick/resume retries; no spinner.
    } finally {
      if (_runningGeneration == generation) _runningGeneration = null;
    }
  }

  void stop() {
    if (!_started) return;
    _started = false;
    _generation++;
    _timer?.cancel();
    _timer = null;
    _session.removeListener(_sessionChanged);
    lastSnapshot = null;
    snapshotScope = null;
  }

  @override
  void dispose() {
    stop();
    _disposed = true;
    if (_ownsService) _service.dispose();
    super.dispose();
  }
}
