import 'dart:async';

import 'package:flutter/foundation.dart';

import 'device_sensor_service.dart';
import 'sensor_service.dart';
import 'sensor_snapshot.dart';

/// Mantém os sensores de movimento ativos enquanto o GranMap está visível.
///
/// O contador de consumidores permite que o shell e a navegação PDR usem a
/// mesma fonte física sem abrir assinaturas duplicadas. Quando o aplicativo
/// sai do primeiro plano, as assinaturas são pausadas e retomadas ao voltar.
class AppSensorService extends ChangeNotifier implements SensorService {
  AppSensorService._();

  static final AppSensorService instance = AppSensorService._();

  final DeviceSensorService _device = DeviceSensorService();
  int _consumers = 0;
  bool _foreground = true;
  bool _active = false;
  Completer<void>? _syncCompleter;

  bool get active => _active;
  bool get foreground => _foreground;

  @override
  Stream<SensorSnapshot> get snapshots => _device.snapshots;

  @override
  Future<void> start() async {
    _consumers++;
    await _sync();
  }

  @override
  Future<void> stop() async {
    if (_consumers > 0) _consumers--;
    await _sync();
  }

  Future<void> setForeground(bool value) async {
    if (_foreground == value) return;
    _foreground = value;
    await _sync();
  }

  Future<void> _sync() async {
    final currentSync = _syncCompleter;
    if (currentSync != null) {
      await currentSync.future;
      return _sync();
    }
    final completer = Completer<void>();
    _syncCompleter = completer;
    try {
      final shouldRun = _foreground && _consumers > 0;
      if (shouldRun == _active) return;
      if (shouldRun) {
        await _device.start();
      } else {
        await _device.stop();
      }
      _active = shouldRun;
      notifyListeners();
    } finally {
      _syncCompleter = null;
      completer.complete();
    }
  }

  @override
  Future<void> reset() => _device.reset();
}
