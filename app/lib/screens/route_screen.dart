import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/campus_map.dart';
import '../navigation/navigation_service.dart';
import '../navigation/navigation_session.dart';
import '../navigation/route_result.dart';
import '../positioning/app_sensor_service.dart';
import '../positioning/gran_presence_service.dart';
import '../positioning/pdr_positioning_service.dart';
import '../positioning/position_sample.dart';
import '../positioning/sensor_service.dart';
import '../services/app_preferences.dart';
import '../services/app_runtime_config.dart';
import '../services/external_maps_service.dart';
import '../services/granmap_api.dart';
import '../services/personal_data_service.dart';
import '../theme/granmap_theme.dart';
import '../widgets/campus_lens_canvas.dart';
import '../widgets/anchor_scanner_sheet.dart';
import '../widgets/campus_map_canvas.dart';
import '../widgets/campus_twin_canvas.dart';
import 'advanced_route_screen.dart';

class RouteScreen extends StatefulWidget {
  final CampusMap campus;
  final CampusPoi origin;
  final CampusPoi destination;
  final Set<String> blockedEdgeIds;
  final int initialView;
  final SensorService? sensors;
  final GranMapApi? api;
  final Future<String?> Function(BuildContext)? scanAnchor;

  const RouteScreen({
    super.key,
    required this.campus,
    required this.origin,
    required this.destination,
    this.blockedEdgeIds = const {},
    this.initialView = 0,
    this.sensors,
    this.api,
    this.scanAnchor,
  });

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> with WidgetsBindingObserver {
  final _navigation = const NavigationService();
  final _personal = PersonalDataService();
  final _presence = GranPresenceService.instance;
  final _externalMaps = const ExternalMapsService();
  late final GranMapApi _api;
  RouteResult? _route;
  NavigationSession? _session;
  bool _accessibleOnly = AppPreferences.instance.accessibleRoutes;
  late int _view;
  int _lastFeedbackSegment = -1;
  bool _favorite = false;
  bool _favoriteBusy = false;
  int _favoriteGeneration = 0;
  bool _physicalMode = false;
  bool _positioningBusy = false;
  bool _resumePhysical = false;
  bool _foreground = true;
  int _trackingGeneration = 0;
  PdrPositioningService? _pdr;
  StreamSubscription<PositionSample>? _physicalSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _api = widget.api ?? GranMapApi();
    _view = widget.initialView == 2 ? 0 : widget.initialView.clamp(0, 3);
    if (_view == 3 && !AppRuntimeConfig.instance.arEnabled) _view = 0;
    _presence.addListener(_changed);
    _configure();
    _loadFavorite();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _trackingGeneration++;
    unawaited(_physicalSubscription?.cancel());
    unawaited(_pdr?.dispose());
    _session?.removeListener(_changed);
    _session?.dispose();
    _presence.removeListener(_changed);
    _personal.dispose();
    if (widget.api == null) _api.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      if (_resumePhysical) {
        _resumePhysical = false;
        unawaited(_trackSteps());
      }
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _resumePhysical =
          _resumePhysical || (_physicalMode && (_session?.isPlaying ?? false));
      if (_physicalMode) {
        _session?.pause();
        unawaited(_stopPhysicalTracking());
        setState(() => _positioningBusy = false);
      }
    }
  }

  Future<void> _stopPhysicalTracking() async {
    _trackingGeneration++;
    final subscription = _physicalSubscription;
    _physicalSubscription = null;
    final stopping = _pdr?.stop();
    await subscription?.cancel();
    await stopping;
  }

  Future<void> _startPreview() async {
    _physicalMode = false;
    _resumePhysical = false;
    await _stopPhysicalTracking();
    if (!mounted) return;
    _session?.setExternalTracking(false);
    _session?.reset();
    _session?.start();
  }

  Future<void> _confirmPhysicalOrigin() async {
    if (!AppRuntimeConfig.instance.physicalPositioningEnabled) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Confirme o ponto de partida',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              Text(
                '${widget.origin.name} • '
                '${widget.origin.floor == 0 ? 'Térreo' : widget.origin.floor == 1 ? 'Superior' : 'Piso ${widget.origin.floor}'}',
              ),
              const SizedBox(height: 8),
              const Text(
                'Os sensores de passos e direção acompanham seu deslocamento a '
                'partir desse ponto. Se trocar de piso, confirme sua localização '
                'por uma placa QR ou manualmente nas ferramentas.',
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Estou nesse ponto — acompanhar passos'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true && mounted) await _trackSteps(resetOrigin: true);
  }

  Future<void> _trackSteps({bool resetOrigin = false}) async {
    if (_positioningBusy || !mounted || !_foreground) return;
    final session = _session;
    if (session == null) return;
    setState(() => _positioningBusy = true);
    await _stopPhysicalTracking();
    if (!mounted || !_foreground) return;
    final generation = _trackingGeneration;
    try {
      _physicalMode = true;
      session.setExternalTracking(true);
      if (resetOrigin) session.reset();
      _pdr ??= PdrPositioningService(
        campus: widget.campus,
        sensors: widget.sensors ?? AppSensorService.instance,
        initialPosition: session.position,
      );
      if (resetOrigin) {
        final origin = session.position;
        _pdr!.reanchor(
          PositionSample(
            x: origin.x,
            y: origin.y,
            z: origin.z,
            floor: origin.floor,
            headingDegrees: origin.headingDegrees,
            accuracyMeters: 8,
            confidence: .45,
            timestamp: DateTime.now(),
          ),
        );
      }
      _physicalSubscription = _pdr!.positions.listen((position) {
        if (mounted &&
            generation == _trackingGeneration &&
            _physicalMode &&
            (_session?.isPlaying ?? false)) {
          _session?.applyExternalPosition(position);
        }
      });
      session.start();
      await _pdr!.start();
    } catch (_) {
      if (!mounted || generation != _trackingGeneration) return;
      await _stopPhysicalTracking();
      session.pause();
      if (mounted) {
        setState(() => _positioningBusy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sensores indisponíveis. A prévia animada continua disponível.',
            ),
          ),
        );
      }
    } finally {
      if (mounted && generation == _trackingGeneration) {
        setState(() => _positioningBusy = false);
      }
    }
  }

  Future<void> _toggleActive() async {
    if (_positioningBusy) return;
    if (!_physicalMode) {
      _session?.toggle();
    } else if (_session?.isPlaying ?? false) {
      setState(() => _positioningBusy = true);
      _session?.pause();
      await _stopPhysicalTracking();
      if (mounted) setState(() => _positioningBusy = false);
    } else {
      await _trackSteps();
    }
  }

  void _applyPhysicalAnchor(PositionSample sample, {required String label}) {
    if (!_physicalMode || _session == null) return;
    final wasPlaying = _session!.isPlaying;
    _pdr?.reanchor(sample);
    _session!.applyExternalPosition(sample);
    if (!wasPlaying) _session!.pause();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label)));
  }

  Future<void> _reanchorQr() async {
    final session = _session;
    if (!_physicalMode || session == null) return;
    final code = await (widget.scanAnchor ?? AnchorScannerSheet.show)(context);
    if (code == null || !mounted || !_physicalMode) return;
    try {
      final anchors = await _api.fetchPositioningAnchors().timeout(
        const Duration(seconds: 5),
      );
      if (!mounted || !_physicalMode || !identical(session, _session)) return;
      final normalized = code.trim().toLowerCase();
      final anchor = anchors
          .where(
            (item) =>
                item['anchor_code']?.toString().toLowerCase() == normalized,
          )
          .firstOrNull;
      if (anchor == null) throw StateError('Âncora não cadastrada.');
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
      if (!sample.x.isFinite ||
          !sample.y.isFinite ||
          !sample.z.isFinite ||
          !widget.campus.floors.any((floor) => floor.level == sample.floor)) {
        throw StateError('Âncora fora do mapa atual.');
      }
      _applyPhysicalAnchor(
        sample,
        label: 'Posição reancorada por QR • piso ${sample.floor}.',
      );
    } catch (_) {
      if (mounted && _physicalMode && identical(session, _session)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível confirmar o QR. Escolha um ponto em Confirmar posição manual.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _confirmManualPosition() async {
    if (!_physicalMode) return;
    final points =
        widget.campus.pois
            .where((poi) => widget.campus.nodeById(poi.navigationNode) != null)
            .toList()
          ..sort((a, b) {
            final floor = a.floor.compareTo(b.floor);
            return floor == 0 ? a.name.compareTo(b.name) : floor;
          });
    final point = await showModalBottomSheet<CampusPoi>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Confirme onde você está',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Selecione o ponto e o piso que você reconhece. '
                      'A posição manual é aproximada; o GPS não determina o piso.',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final poi in points)
                      ListTile(
                        leading: const Icon(Icons.location_on_outlined),
                        title: Text('Estou em ${poi.name}'),
                        subtitle: Text(
                          '${poi.floor == 0 ? 'Térreo' : poi.floor == 1 ? 'Superior' : 'Piso ${poi.floor}'}${poi.sector.isEmpty ? '' : ' • ${poi.sector}'}',
                        ),
                        onTap: () => Navigator.of(context).pop(poi),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (point == null || !mounted || !_physicalMode) return;
    _applyPhysicalAnchor(
      PositionSample(
        x: point.x,
        y: point.y,
        z: point.z,
        floor: point.floor,
        headingDegrees: _session?.position.headingDegrees ?? 0,
        accuracyMeters: 8,
        confidence: .45,
        timestamp: DateTime.now(),
      ),
      label: 'Posição manual aproximada confirmada • piso ${point.floor}.',
    );
  }

  Future<void> _loadFavorite() async {
    final generation = _favoriteGeneration;
    try {
      final favorites = await _personal.loadCachedFavorites();
      if (mounted && generation == _favoriteGeneration) {
        setState(() => _favorite = favorites.contains(widget.destination.id));
      }
    } catch (_) {
      // A rota continua disponível mesmo sem carregar os favoritos.
    }
  }

  Future<void> _toggleFavorite() async {
    if (_favoriteBusy) return;
    _favoriteGeneration++;
    final previous = _favorite;
    setState(() {
      _favoriteBusy = true;
      _favorite = !previous;
    });
    try {
      final favorites = await _personal.loadCachedFavorites();
      final next = await _personal.toggleFavorite(
        widget.destination.id,
        favorites,
      );
      if (mounted) {
        setState(() => _favorite = next.contains(widget.destination.id));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _favorite = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível salvar o favorito. Tente novamente.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _favoriteBusy = false);
    }
  }

  Future<void> _copyRoute() async {
    await Clipboard.setData(
      ClipboardData(
        text:
            'GranMap: rota até ${widget.destination.name}, '
            '${widget.destination.floor == 0 ? 'térreo' : 'piso ${widget.destination.floor}'}.',
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Resumo da rota copiado.')));
    }
  }

  void _configure({bool resume = false}) {
    final wasPlaying = _session?.isPlaying ?? false;
    _session?.removeListener(_changed);
    _session?.dispose();
    _route = _navigation.calculateRoute(
      campus: widget.campus,
      origin: widget.origin,
      destination: widget.destination,
      accessibleOnly: _accessibleOnly,
      blockedEdgeIds: widget.blockedEdgeIds,
    );
    final route = _route;
    _session = route == null ? null : NavigationSession(route: route);
    if (_physicalMode) _session?.setExternalTracking(true);
    _session?.addListener(_changed);
    if (_physicalMode && _pdr != null) {
      _session?.applyExternalPosition(_pdr!.current);
      if (!wasPlaying) _session?.pause();
    } else if (resume) {
      _session?.start();
    }
  }

  void _changed() {
    final session = _session;
    if (session != null && session.segmentIndex != _lastFeedbackSegment) {
      _lastFeedbackSegment = session.segmentIndex;
      if (session.hasArrived) {
        HapticFeedback.heavyImpact();
      } else if (session.status == NavigationSessionStatus.navigating) {
        HapticFeedback.selectionClick();
      }
    }
    if (mounted) setState(() {});
  }

  void _selectRouteView(int value) {
    if (value == 3 && !AppRuntimeConfig.instance.arEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O modo AR está temporariamente indisponível.'),
        ),
      );
      return;
    }
    setState(() => _view = value == 2 ? 0 : value.clamp(0, 3));
  }

  Future<void> _handlePresenceAction() async {
    final presence = _presence.snapshot;
    if (presence.isAway) {
      final opened = await _externalMaps.openDirectionsToGran();
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível abrir o aplicativo de mapas.'),
          ),
        );
      }
      return;
    }
    if (presence.status == GranPresenceStatus.permissionDenied ||
        presence.status == GranPresenceStatus.servicesDisabled) {
      await _presence.openRequiredSettings();
    } else {
      await _presence.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;
    final session = _session;
    if (route == null || session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Rota indisponível')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.route_rounded,
                  size: 54,
                  color: GranMapColors.orange,
                ),
                const SizedBox(height: 14),
                Text(
                  'Não encontramos um caminho',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 7),
                Text(
                  _accessibleOnly
                      ? 'Não existe uma rota acessível disponível neste momento.'
                      : 'Confira os bloqueios atuais ou escolha outro destino.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: GranMapColors.textMuted),
                ),
                if (_accessibleOnly) ...[
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => setState(() {
                      _accessibleOnly = false;
                      _configure();
                    }),
                    child: const Text('Usar rota padrão'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Fechar',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text(
          _physicalMode ? 'Acompanhando passos' : 'Rota na faculdade',
        ),
        actions: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: _confidenceColor(session.position.confidence),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _physicalMode ? 'Em rota' : 'Prévia',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: GranMapColors.textMuted),
          ),
          IconButton(
            tooltip: 'Ferramentas de navegação',
            onPressed: () => _showTools(route, session),
            icon: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: _InstructionBanner(session: session),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          session.currentFloor == 0
                              ? 'Térreo'
                              : 'Piso ${session.currentFloor}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                      _RouteViewSelector(
                        selected: _view,
                        onSelected: _selectRouteView,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ClipRect(
                    key: const ValueKey('route-visual-viewport'),
                    child: _routeVisual(route, session),
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * .46,
                  ),
                  child: SingleChildScrollView(
                    key: const ValueKey('route-details-sheet'),
                    child: session.status == NavigationSessionStatus.ready
                        ? _DestinationSheet(
                            destination: widget.destination,
                            route: route,
                            accessible: _accessibleOnly,
                            favorite: _favorite,
                            onFavorite: _favoriteBusy ? null : _toggleFavorite,
                            onShare: _copyRoute,
                            presence: _presence.snapshot,
                            onPresenceAction: () =>
                                unawaited(_handlePresenceAction()),
                            onPreview: () => unawaited(_startPreview()),
                            onStart: () => unawaited(_confirmPhysicalOrigin()),
                            sensorsEnabled: AppRuntimeConfig
                                .instance
                                .physicalPositioningEnabled,
                          )
                        : _ActiveNavigationSheet(
                            route: route,
                            session: session,
                            physical: _physicalMode,
                            busy: _positioningBusy,
                            onToggle: () => unawaited(_toggleActive()),
                            onPreview: () => unawaited(_startPreview()),
                            onRecalculate: () =>
                                setState(() => _configure(resume: true)),
                            onEnd: () => Navigator.of(context).pop(),
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _routeVisual(RouteResult route, NavigationSession session) {
    return switch (_view) {
      1 => CampusTwinCanvas(
        campus: widget.campus,
        focusFloor: session.currentFloor,
        route: route.nodes,
        userPosition: session.position,
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
        fullBleed: true,
      ),
    };
  }

  Future<void> _showTools(RouteResult route, NavigationSession session) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: GranMapColors.inkSoft,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ferramentas de navegação',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Priorizar rota acessível'),
                subtitle: const Text(
                  'Evita escadas e prioriza rampas ou passagens acessíveis.',
                ),
                value: _accessibleOnly,
                activeTrackColor: GranMapColors.orange,
                onChanged: (value) {
                  Navigator.of(context).pop();
                  setState(() {
                    _accessibleOnly = value;
                    _configure();
                  });
                  AppPreferences.instance.setAccessibleRoutes(value);
                },
              ),
              const SizedBox(height: 8),
              if (_physicalMode) ...[
                const Text(
                  'Ao mudar de piso, confirme um ponto no novo piso para atualizar seu trajeto.',
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _positioningBusy
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            unawaited(_reanchorQr());
                          },
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text('Ler placa QR'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _positioningBusy
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            unawaited(_confirmManualPosition());
                          },
                    icon: const Icon(Icons.edit_location_alt_outlined),
                    label: const Text('Confirmar posição manual'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (kDebugMode)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      _session?.pause();
                      if (_physicalMode) await _stopPhysicalTracking();
                      if (!mounted) return;
                      Navigator.of(this.context).push(
                        MaterialPageRoute(
                          builder: (_) => AdvancedRouteScreen(
                            campus: widget.campus,
                            origin: widget.origin,
                            destination: widget.destination,
                            blockedEdgeIds: widget.blockedEdgeIds,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.sensors_rounded),
                    label: const Text('Sensores e diagnóstico avançado'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InstructionBanner extends StatelessWidget {
  final NavigationSession session;
  const _InstructionBanner({required this.session});

  @override
  Widget build(BuildContext context) {
    final instruction = session.currentInstruction;
    final arrived = session.hasArrived;
    return Semantics(
      liveRegion: true,
      label: arrived
          ? 'Você chegou ao destino.'
          : '${instruction.title}. ${instruction.detail}',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xF20A1728),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: arrived
                ? GranMapColors.mint.withValues(alpha: .35)
                : GranMapColors.orange.withValues(alpha: .26),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: (arrived ? GranMapColors.mint : GranMapColors.orange)
                    .withValues(alpha: .12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                arrived
                    ? Icons.flag_rounded
                    : _instructionIcon(instruction.type),
                color: arrived ? GranMapColors.mint : GranMapColors.orange,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    arrived ? 'Você chegou' : instruction.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    instruction.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: GranMapColors.textMuted),
                  ),
                ],
              ),
            ),
            if (!arrived)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _duration(session.demoRemainingDuration),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text(
                    session.remainingUnits == 0
                        ? 'destino'
                        : '~${session.remainingUnits.ceil()} m',
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: GranMapColors.textMuted),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _DestinationSheet extends StatelessWidget {
  final CampusPoi destination;
  final RouteResult route;
  final bool accessible;
  final bool favorite;
  final VoidCallback? onFavorite;
  final VoidCallback onShare;
  final VoidCallback onStart;
  final VoidCallback onPreview;
  final VoidCallback onPresenceAction;
  final GranPresenceSnapshot presence;
  final bool sensorsEnabled;

  const _DestinationSheet({
    required this.destination,
    required this.route,
    required this.accessible,
    required this.favorite,
    required this.onFavorite,
    required this.onShare,
    required this.onStart,
    required this.onPreview,
    required this.onPresenceAction,
    required this.presence,
    required this.sensorsEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 9, 18, 18),
      decoration: const _SheetDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: GranMapColors.textMuted,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: GranMapColors.orange.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: GranMapColors.orange.withValues(alpha: .22),
                  ),
                ),
                child: const Icon(
                  Icons.flag_outlined,
                  color: GranMapColors.orange,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      destination.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${destination.floor == 0 ? 'Térreo' : destination.floor == 1 ? 'Superior' : 'Piso ${destination.floor}'} • ~${route.routeCost.ceil()} m${accessible ? ' • acessível' : ''}',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: GranMapColors.textMuted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: favorite ? 'Remover dos favoritos' : 'Favoritar',
                onPressed: onFavorite,
                icon: Icon(
                  favorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: favorite
                      ? GranMapColors.orange
                      : GranMapColors.textMuted,
                ),
              ),
              IconButton(
                tooltip: 'Copiar resumo da rota',
                onPressed: onShare,
                icon: const Icon(
                  Icons.share_outlined,
                  color: GranMapColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: sensorsEnabled ? onStart : onPreview,
              icon: Icon(
                sensorsEnabled
                    ? Icons.navigation_rounded
                    : Icons.play_circle_outline_rounded,
                size: 18,
              ),
              label: Text(
                sensorsEnabled ? 'Acompanhar passos' : 'Ver prévia da rota',
              ),
            ),
          ),
          if (sensorsEnabled) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onPreview,
                icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                label: const Text('Ver prévia da rota'),
              ),
            ),
          ],
          const SizedBox(height: 10),
          _ArrivalStatus(presence: presence),
          if (!presence.isAtGran) ...[
            TextButton.icon(
              onPressed: onPresenceAction,
              icon: Icon(
                presence.isAway
                    ? Icons.directions_car_filled_rounded
                    : Icons.my_location_rounded,
              ),
              label: Text(
                presence.isAway
                    ? 'Ir até a Gran Tietê'
                    : 'Atualizar localização externa',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ArrivalStatus extends StatelessWidget {
  final GranPresenceSnapshot presence;

  const _ArrivalStatus({required this.presence});

  @override
  Widget build(BuildContext context) {
    final (icon, tone, title, subtitle) = switch (presence.status) {
      GranPresenceStatus.inside => (
        Icons.check_circle_rounded,
        GranMapColors.mint,
        'Você está na Gran Tietê',
        'GPS próximo da faculdade; confirme sua origem interna.',
      ),
      GranPresenceStatus.nearby => (
        Icons.directions_walk_rounded,
        GranMapColors.sky,
        'Você está perto da entrada',
        '${presence.distanceLabel} até a Gran Tietê.',
      ),
      GranPresenceStatus.outside => (
        Icons.route_rounded,
        GranMapColors.orange,
        'Primeiro, chegue à Gran Tietê',
        '${presence.distanceLabel} até a faculdade.',
      ),
      GranPresenceStatus.permissionDenied => (
        Icons.location_disabled_rounded,
        GranMapColors.amber,
        'Permita sua localização',
        'O GPS indica proximidade da faculdade, sem identificar sala ou piso.',
      ),
      GranPresenceStatus.servicesDisabled => (
        Icons.gps_off_rounded,
        GranMapColors.amber,
        'Ligue a localização do celular',
        'O GPS é usado para detectar sua chegada.',
      ),
      GranPresenceStatus.uncertain => (
        Icons.location_searching_rounded,
        GranMapColors.sky,
        'Confirmando sua posição',
        'A leitura ainda não tem precisão suficiente.',
      ),
      GranPresenceStatus.unavailable => (
        Icons.signal_wifi_connected_no_internet_4_rounded,
        GranMapColors.coral,
        'Posição indisponível',
        'Você ainda pode explorar uma prévia da rota.',
      ),
      GranPresenceStatus.checking => (
        Icons.my_location_rounded,
        GranMapColors.sky,
        'Localizando você…',
        'Aguarde alguns segundos ou atualize.',
      ),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: tone.withValues(alpha: .22)),
      ),
      child: Row(
        children: [
          Icon(icon, color: tone, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: GranMapColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveNavigationSheet extends StatelessWidget {
  final RouteResult route;
  final NavigationSession session;
  final VoidCallback onToggle;
  final VoidCallback onRecalculate;
  final VoidCallback onEnd;
  final VoidCallback onPreview;
  final bool physical;
  final bool busy;

  const _ActiveNavigationSheet({
    required this.route,
    required this.session,
    required this.onToggle,
    required this.onRecalculate,
    required this.onEnd,
    required this.onPreview,
    required this.physical,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    final current = session.currentInstructionIndex;
    final visible = route.instructions.skip(current).take(3).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 16),
      decoration: const _SheetDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: GranMapColors.textMuted,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            physical
                ? 'Passos e orientação • posição aproximada'
                : 'Prévia animada • movimento simulado',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 6),
          for (var index = 0; index < visible.length; index++) ...[
            _CompactStep(instruction: visible[index], active: index == 0),
            if (index != visible.length - 1) const SizedBox(height: 6),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRecalculate,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: const Text('Recalcular'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: GranMapColors.danger,
                    side: BorderSide(
                      color: GranMapColors.danger.withValues(alpha: .28),
                    ),
                  ),
                  onPressed: onEnd,
                  icon: const Icon(Icons.close_rounded, size: 17),
                  label: const Text('Encerrar'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy
                  ? null
                  : session.hasArrived
                  ? onEnd
                  : onToggle,
              icon: Icon(
                session.isPlaying
                    ? Icons.pause_rounded
                    : Icons.navigation_rounded,
                size: 18,
              ),
              label: Text(
                session.hasArrived
                    ? 'Concluir'
                    : session.isPlaying
                    ? (physical ? 'Pausar sensores' : 'Pausar prévia')
                    : (physical ? 'Retomar sensores' : 'Continuar prévia'),
              ),
            ),
          ),
          if (physical)
            TextButton(
              onPressed: busy ? null : onPreview,
              child: const Text('Usar prévia animada'),
            ),
        ],
      ),
    );
  }
}

class _CompactStep extends StatelessWidget {
  final RouteInstruction instruction;
  final bool active;

  const _CompactStep({required this.instruction, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: active
            ? GranMapColors.orange.withValues(alpha: .07)
            : GranMapColors.navy,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active
              ? GranMapColors.orange.withValues(alpha: .3)
              : GranMapColors.line,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: active ? GranMapColors.orange : GranMapColors.textMuted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              instruction.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: active ? GranMapColors.orange : GranMapColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteViewSelector extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelected;

  const _RouteViewSelector({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    const modes = {0: '2D', 1: '3D', 3: 'AR'};
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xF20A1728),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GranMapColors.line),
      ),
      child: Row(
        children: [
          for (final mode in modes.entries)
            InkWell(
              onTap: () => onSelected(mode.key),
              child: Container(
                width: 46,
                height: 34,
                alignment: Alignment.center,
                color: selected == mode.key
                    ? GranMapColors.orange.withValues(alpha: .16)
                    : Colors.transparent,
                child: Text(
                  mode.value,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected == mode.key
                        ? GranMapColors.orange
                        : GranMapColors.textMuted,
                    fontWeight: selected == mode.key
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SheetDecoration extends BoxDecoration {
  const _SheetDecoration()
    : super(
        color: const Color(0xFA091525),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: const Border(top: BorderSide(color: GranMapColors.line)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x88000000),
            blurRadius: 26,
            offset: Offset(0, -10),
          ),
        ],
      );
}

IconData _instructionIcon(String type) => switch (type) {
  'right' || 'turn_right' => Icons.arrow_forward_rounded,
  'left' || 'turn_left' => Icons.arrow_back_rounded,
  'ramp' || 'floor_change' => Icons.stairs_rounded,
  'arrive' => Icons.flag_rounded,
  _ => Icons.arrow_upward_rounded,
};

String _duration(Duration value) {
  if (value.inMinutes > 0) return '${value.inMinutes} min';
  return '${value.inSeconds}s';
}

Color _confidenceColor(double value) {
  if (value >= .75) return GranMapColors.mint;
  if (value >= .45) return GranMapColors.amber;
  return GranMapColors.danger;
}
