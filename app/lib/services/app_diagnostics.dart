import 'dart:convert';

import 'package:flutter/foundation.dart';

class AppDiagnostics {
  AppDiagnostics._();

  static final AppDiagnostics instance = AppDiagnostics._();
  static const _maximumEvents = 120;

  final List<Map<String, dynamic>> _events = [];
  bool _installed = false;

  void install() {
    if (_installed) return;
    _installed = true;
    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      record(
        'flutter.error',
        message: details.exceptionAsString(),
        stack: details.stack,
      );
      if (previousFlutterHandler != null) {
        previousFlutterHandler(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    final previousPlatformHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      record('platform.error', message: '$error', stack: stack);
      return previousPlatformHandler?.call(error, stack) ?? false;
    };
    record('app.started');
  }

  void record(
    String event, {
    String? message,
    StackTrace? stack,
    Map<String, Object?> data = const {},
  }) {
    final sanitizedMessage = _truncate(
      message?.replaceAll(RegExp(r'Bearer\s+\S+'), 'Bearer [removido]'),
    );
    _events.insert(0, {
      'at': DateTime.now().toUtc().toIso8601String(),
      'event': event,
      'message': ?sanitizedMessage,
      if (stack != null) 'stack': _truncate('$stack', limit: 1600),
      if (data.isNotEmpty) 'data': data,
    });
    if (_events.length > _maximumEvents) {
      _events.removeRange(_maximumEvents, _events.length);
    }
  }

  String exportReport({Map<String, Object?> context = const {}}) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert({
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'context': context,
      'events': List<Map<String, dynamic>>.unmodifiable(_events),
    });
  }

  String? _truncate(String? value, {int limit = 600}) {
    if (value == null || value.isEmpty) return null;
    return value.length <= limit ? value : '${value.substring(0, limit)}…';
  }
}
