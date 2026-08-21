import 'dart:async';

import 'package:flutter/material.dart';

import '../models/campus_map.dart';
import '../navigation/navigation_service.dart';
import '../navigation/navigation_session.dart';
import '../navigation/route_result.dart';
import '../positioning/device_sensor_service.dart';
import '../positioning/gps_entrance_service.dart';
import '../positioning/pdr_positioning_service.dart';
import '../positioning/position_sample.dart';
import '../services/granmap_api.dart';
import '../theme/granmap_theme.dart';
import '../widgets/campus_lens_canvas.dart';
import '../widgets/campus_map_canvas.dart';
import '../widgets/campus_twin_canvas.dart';
import '../widgets/granmap_ui.dart';
import '../widgets/walk_view_canvas.dart';
import '../widgets/anchor_scanner_sheet.dart';

class AdvancedRouteScreen extends StatefulWidget {
  final CampusMap campus;
  final CampusPoi origin;
  final CampusPoi destination;
  final Set<String> blockedEdgeIds;

  const AdvancedRouteScreen({
    super.key,
    required this.campus,
    required this.origin,
    required this.destination,
    this.blockedEdgeIds = const {},
  });

  @override
  State<AdvancedRouteScreen> createState() => _AdvancedRouteScreenState();
}

class _AdvancedRouteScreenState extends State<AdvancedRouteScreen> {
  final NavigationService _navigationService = const NavigationService();
  final GranMapApi _api = GranMapApi();

  RouteResult? _route;
  NavigationSession? _session;
  Timer? _closureTimer;
  DeviceSensorService? _deviceSensors;
  PdrPositioningService? _pdr;
  StreamSubscription<PositionSample>? _physicalPositionSubscription;
  late Set<String> _blockedEdgeIds;
  String? _rerouteNotice;
  String? _positioningNotice;
  bool _realPositioning = false;
  bool _positioningBusy = false;
  bool _accessibleOnly = false;
  int _routeView = 0;

  @override
  void initState() {
    super.initState();
    _blockedEdgeIds = {...widget.blockedEdgeIds};
    if (_blockedEdgeIds.isNotEmpty) {
      _rerouteNotice =
          'A rota já considera ${_blockedEdgeIds.length} bloqueio(s) operacional(is).';
    }
    _configureRoute();
    _closureTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshClosures(),
    );
  }

  @override
  void dispose() {
    _session?.removeListener(_onSessionChanged);
    _session?.dispose();
    _closureTimer?.cancel();
    _physicalPositionSubscription?.cancel();
    _pdr?.dispose();
    _deviceSensors?.dispose();
    _api.dispose();
    super.dispose();
  }

  void _configureRoute({String? startNodeId, bool resume = false}) {
    _session?.removeListener(_onSessionChanged);
    _session?.dispose();
    _route = startNodeId == null
        ? _navigationService.calculateRoute(
            campus: widget.campus,
            origin: widget.origin,
            destination: widget.destination,
            accessibleOnly: _accessibleOnly,
            blockedEdgeIds: _blockedEdgeIds,
          )
        : _navigationService.calculateRouteFromNode(
            campus: widget.campus,
            startNodeId: startNodeId,
            destination: widget.destination,
            accessibleOnly: _accessibleOnly,
            blockedEdgeIds: _blockedEdgeIds,
          );
    final route = _route;
    _session = route == null ? null : NavigationSession(route: route);
    _session?.addListener(_onSessionChanged);
    if (resume) scheduleMicrotask(() => _session?.start());
  }

  Future<void> _refreshClosures() async {
    try {
      final closures = await _api.fetchRouteClosures();
      final next = closures
          .map((item) => item['edge_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      if (_sameSet(next, _blockedEdgeIds) || !mounted) return;
      final previousSession = _session;
      final resume = previousSession?.isPlaying ?? false;
      final startNode = previousSession?.activeNodeId;
      setState(() {
        _blockedEdgeIds = next;
        _rerouteNotice = next.isEmpty
            ? 'O caminho foi atualizado após a liberação dos corredores.'
            : 'Rota recalculada com ${next.length} bloqueio(s) operacional(is).';
        _configureRoute(startNodeId: startNode, resume: resume);
      });
    } catch (_) {
      // A rota atual permanece válida no modo offline.
    }
  }

  bool _sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.every(b.contains);

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  void _setAccessible(bool value) {
    setState(() {
      _accessibleOnly = value;
      _configureRoute();
    });
  }

  void _cycleSpeed() {
    final session = _session;
    if (session == null) return;
    const speeds = [.75, 1.0, 1.5, 2.0];
    final current = speeds.indexOf(session.playbackSpeed);
    session.setPlaybackSpeed(speeds[(current + 1) % speeds.length]);
  }

  Future<void> _toggleRealPositioning() async {
    if (_positioningBusy) return;
    setState(() => _positioningBusy = true);
    if (_realPositioning) {
      await _physicalPositionSubscription?.cancel();
      await _pdr?.stop();
      if (mounted) {
        setState(() {
          _realPositioning = false;
          _positioningBusy = false;
          _positioningNotice =
              'Posicionamento físico pausado; simulação preservada.';
        });
      }
      return;
    }
    try {
      final session = _session;
      if (session == null) return;
      _deviceSensors ??= DeviceSensorService();
      _pdr ??= PdrPositioningService(
        campus: widget.campus,
        sensors: _deviceSensors!,
        initialPosition: session.position,
      );
      try {
        _pdr!.setMagneticReferences(await _api.fetchMagneticReferences());
      } catch (_) {
        // PDR e QR continuam disponíveis sem um mapa magnético em cache/rede.
      }
      _physicalPositionSubscription ??= _pdr!.positions.listen((position) {
        _session?.applyExternalPosition(position);
      });
      await _pdr!.start();
      if (mounted) {
        setState(() {
          _realPositioning = true;
          _positioningNotice = 'PDR físico ativo: passos, bússola e map matching. Reancore por QR para limitar deriva.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _positioningNotice = 'Sensores físicos indisponíveis neste ambiente; a demo continua simulada.';
        });
      }
    } finally {
      if (mounted) setState(() => _positioningBusy = false);
    }
  }

  Future<void> _scanAnchor() async {
    final code = await AnchorScannerSheet.show(context);
    if (code == null || !mounted) return;
    try {
      final anchors = await _api.fetchPositioningAnchors();
      final normalized = code.trim().toLowerCase();
      final anchor = anchors.cast<Map<String, dynamic>?>().firstWhere(
        (item) => item?['anchor_code']?.toString().toLowerCase() == normalized,
        orElse: () => null,
      );
      if (anchor == null) {
        setState(
          () => _positioningNotice =
              'QR lido, mas a âncora não pertence ao mapa publicado.',
        );
        return;
      }
      final sample = PositionSample(
        x: (anchor['x'] as num).toDouble(),
        y: (anchor['y'] as num).toDouble(),
        z: (anchor['z'] as num).toDouble(),
        floor: (anchor['floor'] as num).toInt(),
        headingDegrees: ((anchor['heading'] ?? 0) as num).toDouble(),
        accuracyMeters: .45,
        confidence: .99,
        timestamp: DateTime.now(),
      );
      _pdr?.reanchor(sample);
      _session?.applyExternalPosition(sample);
      setState(() {
        _positioningNotice =
            'Posição reancorada em ${anchor['anchor_code']} • piso ${anchor['floor']}.';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _positioningNotice =
              'Não foi possível validar o QR agora. Tente novamente online.',
        );
      }
    }
  }

  Future<void> _readGps() async {
    try {
      final fix = await GpsEntranceService().currentFix();
      if (!mounted) return;
      setState(() {
        _positioningNotice =
            'GPS recebido (±${fix.accuracyMeters.round()} m). A conversão para X/Y/Z será liberada após georreferenciar as entradas no levantamento.';
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _positioningNotice = error.toString().replaceFirst(
            'Bad state: ',
            '',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;
    final session = _session;

    return Scaffold(
      appBar: AppBar(title: const Text('GranMap Live')),
      body: GranMapBackdrop(
        child: route == null || session == null
            ? _UnavailableRoute(
                accessibleOnly: _accessibleOnly,
                onUseStandardRoute: () => _setAccessible(false),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 920),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_rerouteNotice != null) ...[
                            GranMapSurface(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  const GranMapIconBadge(
                                    icon: Icons.alt_route_rounded,
                                    color: GranMapColors.coral,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Operação da faculdade',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(_rerouteNotice!),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          GranMapFadeSlide(
                            child: GranMapPageHeader(
                              eyebrow: 'Navegação ao vivo',
                              title: widget.destination.name,
                              subtitle:
                                  '${widget.origin.name} → ${widget.destination.name}',
                              trailing: GranMapStatusPill(
                                label: 'Piso ${session.currentFloor}',
                                icon: Icons.layers_rounded,
                                color: GranMapColors.violet,
                              ),
                            ),
                          ),
                          const SizedBox(height: 15),
                          _ConceptualNotice(
                            hasPhysicalMetrics: route.hasPhysicalMetrics,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 9,
                            runSpacing: 9,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              FilterChip(
                                selected: _accessibleOnly,
                                avatar: Icon(
                                  Icons.accessible_forward_rounded,
                                  color: _accessibleOnly
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                ),
                                label: const Text('Rota acessível'),
                                onSelected: _setAccessible,
                              ),
                              GranMapStatusPill(
                                label: _realPositioning
                                    ? 'PDR físico + map matching'
                                    : 'Posição X/Y/Z simulada',
                                icon: Icons.sensors_rounded,
                                color: _realPositioning
                                    ? GranMapColors.mint
                                    : GranMapColors.sky,
                              ),
                              GranMapStatusPill(
                                label: _statusLabel(session.status),
                                icon: session.hasArrived
                                    ? Icons.flag_rounded
                                    : Icons.near_me_rounded,
                                color: session.hasArrived
                                    ? GranMapColors.mint
                                    : GranMapColors.violet,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _positioningBusy
                                    ? null
                                    : _toggleRealPositioning,
                                icon: Icon(
                                  _realPositioning
                                      ? Icons.sensors_off_rounded
                                      : Icons.sensors_rounded,
                                ),
                                label: Text(
                                  _positioningBusy
                                      ? 'Conectando…'
                                      : (_realPositioning
                                            ? 'Pausar sensores'
                                            : 'Usar sensores reais'),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: _scanAnchor,
                                icon: const Icon(Icons.qr_code_scanner_rounded),
                                label: const Text('Reancorar por QR'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _readGps,
                                icon: const Icon(Icons.gps_fixed_rounded),
                                label: const Text('GPS da entrada'),
                              ),
                            ],
                          ),
                          if (_positioningNotice != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _positioningNotice!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                          const SizedBox(height: 15),
                          _LiveInstruction(session: session),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _Metric(
                                icon: Icons.route_rounded,
                                value: _remainingLabel(session, route),
                                label: route.hasPhysicalMetrics
                                    ? 'restantes'
                                    : 'restante demo',
                                color: GranMapColors.violet,
                              ),
                              const SizedBox(width: 9),
                              _Metric(
                                icon: Icons.schedule_rounded,
                                value: _durationLabel(
                                  session.demoRemainingDuration,
                                ),
                                label: 'tempo demo',
                                color: GranMapColors.coral,
                              ),
                              const SizedBox(width: 9),
                              _Metric(
                                icon: Icons.my_location_rounded,
                                value:
                                    '${(session.position.confidence * 100).round()}%',
                                label: 'confiança',
                                color: GranMapColors.mint,
                              ),
                            ],
                          ),
                          const SizedBox(height: 15),
                          GranMapSurface(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    8,
                                    6,
                                    8,
                                    4,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Visual da rota',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge,
                                      ),
                                      const SizedBox(height: 8),
                                      SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: SegmentedButton<int>(
                                          showSelectedIcon: false,
                                          segments: const [
                                            ButtonSegment(
                                              value: 0,
                                              icon: Icon(
                                                Icons.map_outlined,
                                                size: 17,
                                              ),
                                              label: Text('2D'),
                                            ),
                                            ButtonSegment(
                                              value: 1,
                                              icon: Icon(
                                                Icons.view_in_ar_outlined,
                                                size: 17,
                                              ),
                                              label: Text('3D'),
                                            ),
                                            ButtonSegment(
                                              value: 2,
                                              icon: Icon(
                                                Icons.directions_walk_rounded,
                                                size: 17,
                                              ),
                                              label: Text('Walk'),
                                            ),
                                            ButtonSegment(
                                              value: 3,
                                              icon: Icon(
                                                Icons.view_in_ar_rounded,
                                                size: 17,
                                              ),
                                              label: Text('AR'),
                                            ),
                                          ],
                                          selected: {_routeView},
                                          onSelectionChanged: (selection) {
                                            setState(
                                              () =>
                                                  _routeView = selection.first,
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 320),
                                  child: Padding(
                                    key: ValueKey(
                                      '${_routeView}_${session.currentFloor}',
                                    ),
                                    padding: const EdgeInsets.all(4),
                                    child: switch (_routeView) {
                                      1 => CampusTwinCanvas(
                                        campus: widget.campus,
                                        focusFloor: session.currentFloor,
                                        route: route.nodes,
                                        userPosition: session.position,
                                      ),
                                      2 => WalkViewCanvas(
                                        campus: widget.campus,
                                        route: route.nodes,
                                        position: session.position,
                                        segmentIndex: session.segmentIndex,
                                        destination: widget.destination,
                                      ),
                                      3 => CampusLensCanvas(
                                        campus: widget.campus,
                                        route: route.nodes,
                                        position: session.position,
                                        segmentIndex: session.segmentIndex,
                                        destination: widget.destination,
                                      ),
                                      _ => CampusMapCanvas(
                                        campus: widget.campus,
                                        floor: session.currentFloor,
                                        route: route.nodes,
                                        activeNodeId: session.activeNodeId,
                                        userPosition: session.position,
                                      ),
                                    },
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    5,
                                    10,
                                    10,
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            'Progresso da rota',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelMedium,
                                          ),
                                          const Spacer(),
                                          Text(
                                            '${(session.progress * 100).round()}%',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelMedium
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 7),
                                      LinearProgressIndicator(
                                        value: session.progress,
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: FilledButton.icon(
                                              onPressed: session.toggle,
                                              icon: Icon(
                                                session.isPlaying
                                                    ? Icons.pause_rounded
                                                    : session.hasArrived
                                                    ? Icons.replay_rounded
                                                    : Icons.navigation_rounded,
                                              ),
                                              label: Text(
                                                session.isPlaying
                                                    ? 'Pausar navegação'
                                                    : session.hasArrived
                                                    ? 'Repetir percurso'
                                                    : session.status ==
                                                          NavigationSessionStatus
                                                              .paused
                                                    ? 'Continuar navegação'
                                                    : 'Iniciar navegação',
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 9),
                                          IconButton.outlined(
                                            tooltip:
                                                'Velocidade ${_speedLabel(session.playbackSpeed)}',
                                            onPressed: _cycleSpeed,
                                            icon: Text(
                                              _speedLabel(
                                                session.playbackSpeed,
                                              ),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          IconButton.outlined(
                                            tooltip: 'Reiniciar',
                                            onPressed: session.reset,
                                            icon: const Icon(
                                              Icons.restart_alt_rounded,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          const GranMapSectionTitle(title: 'Passo a passo'),
                          const SizedBox(height: 10),
                          GranMapSurface(
                            child: Column(
                              children: [
                                for (
                                  var index = 0;
                                  index < route.instructions.length;
                                  index++
                                )
                                  _InstructionStep(
                                    index: index,
                                    last:
                                        index == route.instructions.length - 1,
                                    active:
                                        index ==
                                        session.currentInstructionIndex,
                                    completed:
                                        index < session.currentInstructionIndex,
                                    instruction: route.instructions[index],
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

  String _statusLabel(NavigationSessionStatus status) {
    return switch (status) {
      NavigationSessionStatus.ready => 'Pronto para navegar',
      NavigationSessionStatus.navigating => 'Navegando',
      NavigationSessionStatus.paused => 'Navegação pausada',
      NavigationSessionStatus.arrived => 'Destino alcançado',
    };
  }

  String _remainingLabel(NavigationSession session, RouteResult route) {
    if (route.hasPhysicalMetrics) {
      return '${session.remainingUnits.toStringAsFixed(0)} m';
    }
    return '${session.remainingUnits.ceil()} u';
  }

  String _durationLabel(Duration duration) {
    if (duration == Duration.zero) return '0s';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    if (minutes == 0) return '${seconds}s';
    if (seconds == 0) return '${minutes}min';
    return '${minutes}m ${seconds}s';
  }

  String _speedLabel(double speed) {
    final formatted = speed == speed.roundToDouble()
        ? speed.toStringAsFixed(0)
        : speed.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
    return '$formatted×';
  }
}

class _ConceptualNotice extends StatelessWidget {
  final bool hasPhysicalMetrics;

  const _ConceptualNotice({required this.hasPhysicalMetrics});

  @override
  Widget build(BuildContext context) {
    if (hasPhysicalMetrics) return const SizedBox.shrink();
    return GranMapSurface(
      padding: const EdgeInsets.all(13),
      gradient: LinearGradient(
        colors: [
          GranMapColors.coral.withValues(alpha: .11),
          GranMapColors.violet.withValues(alpha: .07),
        ],
      ),
      child: const Row(
        children: [
          GranMapIconBadge(
            icon: Icons.science_outlined,
            color: GranMapColors.coral,
            size: 40,
          ),
          SizedBox(width: 11),
          Expanded(
            child: Text(
              'Modo demonstração: percurso, progresso e tempo usam a escala '
              'da maquete — não são medidas oficiais da faculdade.',
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveInstruction extends StatelessWidget {
  final NavigationSession session;

  const _LiveInstruction({required this.session});

  @override
  Widget build(BuildContext context) {
    final instruction = session.currentInstruction;
    final arrived = session.hasArrived;
    return GranMapSurface(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: arrived
            ? [
                GranMapColors.mint.withValues(alpha: .2),
                GranMapColors.violet.withValues(alpha: .07),
              ]
            : [GranMapColors.violet, GranMapColors.violetDark],
      ),
      border: Border.all(
        color: arrived
            ? GranMapColors.mint.withValues(alpha: .35)
            : GranMapColors.violet.withValues(alpha: .45),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: arrived
                  ? GranMapColors.mint.withValues(alpha: .14)
                  : Colors.white.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(
              _instructionIcon(instruction.type),
              color: arrived ? GranMapColors.mint : Colors.white,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  arrived ? 'VOCÊ CHEGOU' : 'PRÓXIMA INSTRUÇÃO',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: arrived
                        ? GranMapColors.mint
                        : Colors.white.withValues(alpha: .72),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  instruction.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: arrived
                        ? Theme.of(context).colorScheme.onSurface
                        : Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  instruction.detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: arrived
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : Colors.white.withValues(alpha: .78),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UnavailableRoute extends StatelessWidget {
  final bool accessibleOnly;
  final VoidCallback onUseStandardRoute;

  const _UnavailableRoute({
    required this.accessibleOnly,
    required this.onUseStandardRoute,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: GranMapEmptyState(
          icon: accessibleOnly
              ? Icons.accessible_forward_rounded
              : Icons.route_rounded,
          title: accessibleOnly
              ? 'Não há rota acessível cadastrada'
              : 'Rota indisponível',
          message: accessibleOnly
              ? 'A maquete não possui um caminho sem barreiras para este destino.'
              : 'Não foi possível conectar estes dois pontos.',
          action: accessibleOnly
              ? OutlinedButton.icon(
                  onPressed: onUseStandardRoute,
                  icon: const Icon(Icons.alt_route_rounded),
                  label: const Text('Usar rota padrão'),
                )
              : null,
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _Metric({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GranMapSurface(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 13),
        child: Column(
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(height: 6),
            FittedBox(
              child: Text(
                value,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _InstructionStep extends StatelessWidget {
  final int index;
  final bool last;
  final bool active;
  final bool completed;
  final RouteInstruction instruction;

  const _InstructionStep({
    required this.index,
    required this.last,
    required this.active,
    required this.completed,
    required this.instruction,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = completed
        ? GranMapColors.mint
        : active
        ? scheme.primary
        : scheme.outlineVariant;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 42,
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: active || completed
                        ? tone
                        : scheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: tone.withValues(alpha: .28),
                              blurRadius: 14,
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: completed
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 17,
                          )
                        : Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: active
                                  ? scheme.onPrimary
                                  : scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
                if (!last)
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: 2,
                      color: completed
                          ? GranMapColors.mint
                          : scheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: active || completed ? 1 : .62,
              child: Padding(
                padding: EdgeInsets.only(bottom: last ? 0 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      instruction.title,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(color: active ? scheme.primary : null),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      instruction.detail,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

IconData _instructionIcon(String type) {
  return switch (type) {
    'arrival' => Icons.flag_rounded,
    'ramp' => Icons.accessible_forward_rounded,
    'stairs' => Icons.stairs_rounded,
    'opening' => Icons.door_sliding_rounded,
    'open_area' => Icons.open_with_rounded,
    'service' => Icons.storefront_rounded,
    'door' => Icons.meeting_room_rounded,
    _ => Icons.straight_rounded,
  };
}
