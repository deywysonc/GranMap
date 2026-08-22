import 'dart:async';

import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';

import '../models/campus_map.dart';
import '../positioning/device_sensor_service.dart';
import '../positioning/sensor_service.dart';
import '../positioning/sensor_snapshot.dart';
import '../positioning/simulation_sensor_service.dart';
import '../services/app_session.dart';
import '../services/app_diagnostics.dart';
import '../services/granmap_api.dart';
import '../theme/granmap_theme.dart';
import '../widgets/granmap_ui.dart';

class DeveloperScreen extends StatefulWidget {
  final CampusMap campus;

  const DeveloperScreen({super.key, required this.campus});

  @override
  State<DeveloperScreen> createState() => _DeveloperScreenState();
}

class _DeveloperScreenState extends State<DeveloperScreen> {
  final SimulationSensorService _simulation = SimulationSensorService();
  final GranMapApi _api = GranMapApi();
  final List<String> _logs = [];
  final List<Map<String, dynamic>> _fingerprints = [];

  late SensorService _sensors;
  DeviceSensorService? _deviceSensors;
  StreamSubscription<SensorSnapshot>? _subscription;
  SensorSnapshot? _snapshot;
  bool _running = true;
  bool _usingDevice = false;
  bool _uploading = false;
  int _lastLoggedStep = -1;
  double _noise = .18;
  late String _captureNodeId;
  String _deviceModel = 'unknown-device';

  @override
  void initState() {
    super.initState();
    _sensors = _simulation;
    _captureNodeId = widget.campus.nodes.first.id;
    _subscription = _sensors.snapshots.listen(_onSnapshot);
    _sensors.start();
    _loadDeviceModel();
  }

  Future<void> _loadDeviceModel() async {
    try {
      final data = (await DeviceInfoPlugin().deviceInfo).data;
      final model = data['model'] ?? data['product'] ?? data['computerName'];
      if (model != null && mounted) setState(() => _deviceModel = '$model');
    } catch (_) {
      // Identificador técnico é opcional e nunca bloqueia uma coleta.
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _simulation.dispose();
    _deviceSensors?.dispose();
    _api.dispose();
    super.dispose();
  }

  void _onSnapshot(SensorSnapshot snapshot) {
    if (!mounted) return;
    if (snapshot.stepCount != _lastLoggedStep && snapshot.stepCount.isEven) {
      _lastLoggedStep = snapshot.stepCount;
      _logs.insert(
        0,
        'Passo ${snapshot.stepCount} • heading '
        '${snapshot.headingDegrees.toStringAsFixed(0)}° • '
        '${(snapshot.confidence * 100).round()}% confiança',
      );
      if (_logs.length > 6) _logs.removeLast();
    }
    setState(() => _snapshot = snapshot);
  }

  Future<void> _toggleSensors() async {
    if (_running) {
      await _sensors.stop();
    } else {
      await _sensors.start();
    }
    if (mounted) setState(() => _running = !_running);
  }

  Future<void> _resetSensors() async {
    _logs.clear();
    _lastLoggedStep = -1;
    await _sensors.reset();
  }

  Future<void> _switchSensorSource() async {
    await _sensors.stop();
    await _subscription?.cancel();
    if (_usingDevice) {
      _sensors = _simulation;
      _usingDevice = false;
    } else {
      _deviceSensors ??= DeviceSensorService();
      _sensors = _deviceSensors!;
      _usingDevice = true;
    }
    _subscription = _sensors.snapshots.listen(_onSnapshot);
    try {
      await _sensors.start();
      _running = true;
      _logs.insert(
        0,
        _usingDevice
            ? 'Fonte física conectada ao pipeline.'
            : 'Fonte determinística restaurada.',
      );
    } catch (_) {
      _sensors = _simulation;
      _usingDevice = false;
      _subscription = _sensors.snapshots.listen(_onSnapshot);
      await _sensors.start();
      _logs.insert(0, 'Sensores físicos indisponíveis; simulação restaurada.');
    }
    if (mounted) setState(() {});
  }

  void _captureFingerprint() {
    final snapshot = _snapshot;
    final node = widget.campus.nodes.firstWhere(
      (item) => item.id == _captureNodeId,
    );
    if (snapshot == null || !_usingDevice) return;
    setState(() {
      _fingerprints.add({
        'x': node.x,
        'y': node.y,
        'z': node.z,
        'floor': node.floor,
        'magnetic_x': snapshot.magneticX,
        'magnetic_y': snapshot.magneticY,
        'magnetic_z': snapshot.magneticZ,
        'device_model': _deviceModel,
        'quality': snapshot.confidence,
      });
      _logs.insert(
        0,
        'Fingerprint #${_fingerprints.length} capturado em ${node.id}.',
      );
    });
  }

  Future<void> _uploadFingerprints() async {
    final token = AppSession.instance.token;
    if (token == null || _fingerprints.isEmpty) return;
    setState(() => _uploading = true);
    try {
      final publication = await _api.fetchCurrentMap();
      final count = await _api.uploadMagneticFingerprints(
        token: token,
        mapVersionId: (publication['id'] as num).toInt(),
        samples: _fingerprints,
      );
      if (!mounted) return;
      setState(() {
        _fingerprints.clear();
        _logs.insert(
          0,
          '$count fingerprints sincronizados com a versão publicada.',
        );
      });
    } catch (error) {
      if (mounted) {
        setState(() => _logs.insert(0, 'Falha ao sincronizar: $error'));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final metadata = widget.campus.metadata;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnóstico técnico'),
        actions: [
          IconButton(
            tooltip: 'Copiar relatório seguro',
            onPressed: _copyDiagnosticReport,
            icon: const Icon(Icons.content_copy_rounded),
          ),
        ],
      ),
      body: GranMapBackdrop(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GranMapPageHeader(
                      eyebrow: 'GranMap Lab',
                      title: 'Central técnica',
                      subtitle: 'Mapa, grafo e sinais da localização reunidos em tempo real.',
                      trailing: GranMapStatusPill(
                        label: _running
                            ? (_usingDevice
                                  ? 'Sensores físicos'
                                  : 'Simulação ativa')
                            : 'Sinais pausados',
                        icon: _running
                            ? Icons.sensors_rounded
                            : Icons.pause_circle_outline_rounded,
                        color: _running
                            ? GranMapColors.mint
                            : GranMapColors.coral,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _CountMetric(
                          icon: Icons.hub_rounded,
                          value: '${widget.campus.nodes.length}',
                          label: 'Nodes',
                          color: GranMapColors.violet,
                        ),
                        _CountMetric(
                          icon: Icons.timeline_rounded,
                          value: '${widget.campus.edges.length}',
                          label: 'Edges',
                          color: GranMapColors.sky,
                        ),
                        _CountMetric(
                          icon: Icons.location_on_rounded,
                          value: '${widget.campus.pois.length}',
                          label: 'POIs',
                          color: GranMapColors.coral,
                        ),
                        _CountMetric(
                          icon: Icons.layers_rounded,
                          value: '${widget.campus.floors.length}',
                          label: 'Pisos',
                          color: GranMapColors.mint,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    GranMapSurface(
                      gradient: LinearGradient(
                        colors: [
                          GranMapColors.violet.withValues(alpha: .16),
                          GranMapColors.sky.withValues(alpha: .07),
                        ],
                      ),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const GranMapIconBadge(
                            icon: Icons.architecture_rounded,
                            color: GranMapColors.violet,
                          ),
                          _MetadataItem(
                            label: 'Coordenadas',
                            value: metadata.coordinateSystem,
                          ),
                          _MetadataItem(
                            label: 'Geometria',
                            value: metadata.geometryStatus,
                          ),
                          _MetadataItem(
                            label: 'Distâncias',
                            value: metadata.distanceStatus,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    GranMapSectionTitle(
                      title: _usingDevice
                          ? 'Telemetria do aparelho'
                          : 'Telemetria simulada',
                    ),
                    const SizedBox(height: 10),
                    GranMapSurface(
                      child: snapshot == null
                          ? const Center(child: CircularProgressIndicator())
                          : Column(
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    _SignalHalo(
                                      confidence: snapshot.confidence,
                                    ),
                                    const SizedBox(width: 18),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Signal Halo',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'A interface nunca afirma precisão maior '
                                            'do que os sinais permitem.',
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          LinearProgressIndicator(
                                            value: snapshot.confidence,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                Wrap(
                                  spacing: 9,
                                  runSpacing: 9,
                                  children: [
                                    _TelemetryMetric(
                                      label: 'Passos',
                                      value: '${snapshot.stepCount}',
                                    ),
                                    _TelemetryMetric(
                                      label: 'Direção',
                                      value:
                                          '${snapshot.headingDegrees.toStringAsFixed(0)}°',
                                    ),
                                    _TelemetryMetric(
                                      label: 'Aceleração Z',
                                      value:
                                          '${snapshot.accelerationZ.toStringAsFixed(2)} m/s²',
                                    ),
                                    _TelemetryMetric(
                                      label: 'Giroscópio Z',
                                      value:
                                          '${snapshot.gyroscopeZ.toStringAsFixed(3)} rad/s',
                                    ),
                                    _TelemetryMetric(
                                      label: 'Campo magnético',
                                      value:
                                          '${snapshot.magneticField.toStringAsFixed(1)} µT',
                                    ),
                                  ],
                                ),
                                if (!_usingDevice) ...[
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.graphic_eq_rounded,
                                        size: 19,
                                        color: GranMapColors.coral,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Ruído dos sensores',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge,
                                      ),
                                      const Spacer(),
                                      Text(
                                        '${(_noise * 100).round()}%',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              color: GranMapColors.coral,
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ],
                                  ),
                                  Slider(
                                    value: _noise,
                                    onChanged: (value) {
                                      setState(() => _noise = value);
                                      _simulation.setNoiseLevel(value);
                                    },
                                  ),
                                ],
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: _toggleSensors,
                                        icon: Icon(
                                          _running
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                        ),
                                        label: Text(
                                          _running
                                              ? 'Pausar sinais'
                                              : 'Retomar sinais',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 9),
                                    IconButton.outlined(
                                      onPressed: _resetSensors,
                                      tooltip: 'Reiniciar telemetria',
                                      icon: const Icon(
                                        Icons.restart_alt_rounded,
                                      ),
                                    ),
                                    const SizedBox(width: 9),
                                    IconButton.outlined(
                                      onPressed: _switchSensorSource,
                                      tooltip: _usingDevice
                                          ? 'Voltar ao simulador'
                                          : 'Usar sensores físicos',
                                      icon: Icon(
                                        _usingDevice
                                            ? Icons.science_outlined
                                            : Icons.phone_android_rounded,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 18),
                    GranMapSurface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Coleta magnética versionada',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Selecione o Node físico em que você está, faça várias leituras em orientações diferentes e sincronize apenas com uma conta institucional.',
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _captureNodeId,
                            decoration: const InputDecoration(
                              labelText: 'Node da coleta',
                            ),
                            items: widget.campus.nodes
                                .map(
                                  (node) => DropdownMenuItem(
                                    value: node.id,
                                    child: Text('P${node.floor} • ${node.id}'),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _captureNodeId = value);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: _usingDevice
                                    ? _captureFingerprint
                                    : null,
                                icon: const Icon(Icons.radar_rounded),
                                label: Text(
                                  'Capturar (${_fingerprints.length})',
                                ),
                              ),
                              FilledButton.icon(
                                onPressed:
                                    !_uploading &&
                                        _fingerprints.isNotEmpty &&
                                        AppSession.instance.isLoggedIn
                                    ? _uploadFingerprints
                                    : null,
                                icon: const Icon(Icons.cloud_upload_outlined),
                                label: Text(
                                  _uploading ? 'Enviando…' : 'Sincronizar lote',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    GranMapSurface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pipeline de posicionamento',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          const Wrap(
                            spacing: 7,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _PipelineStep('Sensores', Icons.sensors_rounded),
                              Icon(Icons.arrow_forward_rounded, size: 17),
                              _PipelineStep(
                                'PDR',
                                Icons.directions_walk_rounded,
                              ),
                              Icon(Icons.arrow_forward_rounded, size: 17),
                              _PipelineStep('Fusão', Icons.join_inner_rounded),
                              Icon(Icons.arrow_forward_rounded, size: 17),
                              _PipelineStep(
                                'Map Matching',
                                Icons.route_rounded,
                              ),
                              Icon(Icons.arrow_forward_rounded, size: 17),
                              _PipelineStep('X/Y/Z', Icons.my_location_rounded),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const GranMapSectionTitle(title: 'Explorador do grafo'),
                    const SizedBox(height: 10),
                    _EntityExplorer<NavigationNode>(
                      title: 'Nodes',
                      icon: Icons.hub_rounded,
                      items: widget.campus.nodes,
                      rowBuilder: (node) => _DiagnosticRow(
                        title: node.id,
                        subtitle:
                            'Piso ${node.floor} • (${node.x}, ${node.y}, ${node.z})',
                        trailing: node.type,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _EntityExplorer<NavigationEdge>(
                      title: 'Edges',
                      icon: Icons.timeline_rounded,
                      items: widget.campus.edges,
                      rowBuilder: (edge) => _DiagnosticRow(
                        title: '${edge.from} → ${edge.to}',
                        subtitle:
                            '${edge.distance} u • ${edge.accessible ? 'acessível' : 'restrita'}',
                        trailing: edge.type,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _EntityExplorer<CampusPoi>(
                      title: 'POIs',
                      icon: Icons.location_on_rounded,
                      items: widget.campus.pois,
                      rowBuilder: (poi) => _DiagnosticRow(
                        title: poi.name,
                        subtitle:
                            'Piso ${poi.floor} • (${poi.x}, ${poi.y}, ${poi.z})',
                        trailing: poi.id,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const GranMapSectionTitle(title: 'Eventos recentes'),
                    const SizedBox(height: 10),
                    GranMapSurface(
                      child: _logs.isEmpty
                          ? Text(
                              'Aguardando telemetria…',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            )
                          : Column(
                              children: [
                                for (final log in _logs)
                                  ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                      Icons.terminal_rounded,
                                      size: 19,
                                      color: GranMapColors.mint,
                                    ),
                                    title: Text(log),
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

  Future<void> _copyDiagnosticReport() async {
    final report = AppDiagnostics.instance.exportReport(
      context: {
        'session': AppSession.instance.exportDebugSession(),
        'map_nodes': widget.campus.nodes.length,
        'map_edges': widget.campus.edges.length,
        'sensor_source': _usingDevice ? 'physical' : 'simulation',
      },
    );
    await Clipboard.setData(ClipboardData(text: report));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Relatório copiado sem senha ou token de acesso.'),
        ),
      );
    }
  }
}

class _CountMetric extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _CountMetric({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 144,
      child: GranMapSurface(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            GranMapIconBadge(icon: icon, color: color, size: 38),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: Theme.of(context).textTheme.titleLarge),
                Text(label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetadataItem extends StatelessWidget {
  final String label;
  final String value;

  const _MetadataItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: .62),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(
            value,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _SignalHalo extends StatelessWidget {
  final double confidence;

  const _SignalHalo({required this.confidence});

  @override
  Widget build(BuildContext context) {
    final tone = confidence >= .8
        ? GranMapColors.mint
        : confidence >= .55
        ? GranMapColors.coral
        : Theme.of(context).colorScheme.error;
    return SizedBox.square(
      dimension: 92,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tone.withValues(alpha: .07),
              border: Border.all(color: tone.withValues(alpha: .18)),
            ),
          ),
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tone.withValues(alpha: .12),
              border: Border.all(color: tone.withValues(alpha: .35)),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.my_location_rounded, color: tone, size: 22),
              Text(
                '${(confidence * 100).round()}%',
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: tone),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TelemetryMetric extends StatelessWidget {
  final String label;
  final String value;

  const _TelemetryMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: .48),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(value, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}

class _PipelineStep extends StatelessWidget {
  final String label;
  final IconData icon;

  const _PipelineStep(this.label, this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _EntityExplorer<T> extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<T> items;
  final Widget Function(T item) rowBuilder;

  const _EntityExplorer({
    required this.title,
    required this.icon,
    required this.items,
    required this.rowBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return GranMapSurface(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        leading: GranMapIconBadge(icon: icon, size: 38),
        title: Text(title),
        subtitle: Text('${items.length} registros'),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          SizedBox(
            height: 340,
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (_, index) => rowBuilder(items[index]),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final String trailing;

  const _DiagnosticRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle),
      trailing: Container(
        constraints: const BoxConstraints(maxWidth: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          trailing,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}
