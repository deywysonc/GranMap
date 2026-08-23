import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/campus_map.dart';
import '../navigation/navigation_service.dart';
import '../navigation/navigation_session.dart';
import '../navigation/route_result.dart';
import '../positioning/gran_presence_service.dart';
import '../services/app_preferences.dart';
import '../services/app_runtime_config.dart';
import '../services/external_maps_service.dart';
import '../services/personal_data_service.dart';
import '../theme/granmap_theme.dart';
import '../widgets/campus_lens_canvas.dart';
import '../widgets/campus_map_canvas.dart';
import '../widgets/campus_twin_canvas.dart';
import '../widgets/walk_view_canvas.dart';
import 'advanced_route_screen.dart';

class RouteScreen extends StatefulWidget {
  final CampusMap campus;
  final CampusPoi origin;
  final CampusPoi destination;
  final Set<String> blockedEdgeIds;
  final int initialView;

  const RouteScreen({
    super.key,
    required this.campus,
    required this.origin,
    required this.destination,
    this.blockedEdgeIds = const {},
    this.initialView = 0,
  });

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  final _navigation = const NavigationService();
  final _personal = PersonalDataService();
  final _presence = GranPresenceService.instance;
  final _externalMaps = const ExternalMapsService();
  RouteResult? _route;
  NavigationSession? _session;
  bool _accessibleOnly = AppPreferences.instance.accessibleRoutes;
  late int _view;
  int _lastFeedbackSegment = -1;
  bool _favorite = false;

  @override
  void initState() {
    super.initState();
    _view = widget.initialView.clamp(0, 3);
    if (_view == 3 && !AppRuntimeConfig.instance.arEnabled) _view = 0;
    _presence.addListener(_changed);
    _configure();
    _loadFavorite();
  }

  @override
  void dispose() {
    _session?.removeListener(_changed);
    _session?.dispose();
    _presence.removeListener(_changed);
    _personal.dispose();
    super.dispose();
  }

  Future<void> _loadFavorite() async {
    final favorites = await _personal.loadFavorites();
    if (mounted) {
      setState(() => _favorite = favorites.contains(widget.destination.id));
    }
  }

  Future<void> _toggleFavorite() async {
    final favorites = await _personal.loadFavorites();
    final next = await _personal.toggleFavorite(
      widget.destination.id,
      favorites,
    );
    if (mounted) {
      setState(() => _favorite = next.contains(widget.destination.id));
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
    _session?.addListener(_changed);
    if (resume) _session?.start();
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
    setState(() => _view = value);
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
          _presence.snapshot.isAway &&
                  session.status != NavigationSessionStatus.ready
              ? 'Prévia da rota interna'
              : 'Navegação interna',
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
            _confidenceLabel(session.position.confidence),
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
      body: Stack(
        children: [
          Positioned.fill(child: _routeVisual(route, session)),
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 120,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xE6050C17), Color(0x00050C17)],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 14,
            right: 74,
            top: 12,
            child: _InstructionBanner(session: session),
          ),
          Positioned(
            right: 14,
            top: 12,
            child: _RouteViewSelector(
              selected: _view,
              onSelected: _selectRouteView,
            ),
          ),
          Positioned(
            left: 14,
            top: 112,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xEA0A1728),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: GranMapColors.line),
              ),
              child: Text(
                session.currentFloor == 0
                    ? 'Térreo'
                    : 'Piso ${session.currentFloor}',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: GranMapColors.textMuted),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: session.status == NavigationSessionStatus.ready
                ? _DestinationSheet(
                    destination: widget.destination,
                    route: route,
                    accessible: _accessibleOnly,
                    favorite: _favorite,
                    onFavorite: _toggleFavorite,
                    onShare: _copyRoute,
                    presence: _presence.snapshot,
                    onPresenceAction: () => unawaited(_handlePresenceAction()),
                    onPreview: session.start,
                    onStart: session.start,
                  )
                : _ActiveNavigationSheet(
                    route: route,
                    session: session,
                    onToggle: session.toggle,
                    onRecalculate: () =>
                        setState(() => _configure(resume: true)),
                    onEnd: () => Navigator.of(context).pop(),
                  ),
          ),
        ],
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
              const SizedBox(height: 6),
              Text(
                'A interface simples usa o mesmo grafo X/Y/Z do modo técnico.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: GranMapColors.textMuted),
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Priorizar rota acessível'),
                subtitle: const Text(
                  'Evita conexões marcadas como não acessíveis.',
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
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
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
                  label: const Text('Sensores, QR, GPS e diagnóstico'),
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
                        : '${session.remainingUnits.ceil()} u',
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
  final VoidCallback onFavorite;
  final VoidCallback onShare;
  final VoidCallback onStart;
  final VoidCallback onPreview;
  final VoidCallback onPresenceAction;
  final GranPresenceSnapshot presence;

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
                      '${destination.floor == 0 ? 'Térreo' : 'Piso ${destination.floor}'} • ${route.routeCost.ceil()} unidades conceituais${accessible ? ' • acessível' : ''}',
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
          _ArrivalStatus(presence: presence),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: presence.isAtGran ? onStart : onPresenceAction,
              icon: Icon(
                presence.isAway
                    ? Icons.directions_car_filled_rounded
                    : presence.isAtGran
                    ? Icons.near_me_rounded
                    : Icons.my_location_rounded,
                size: 18,
              ),
              label: Text(
                presence.isAway
                    ? 'Ir até a Gran Tietê'
                    : presence.isAtGran
                    ? 'Iniciar navegação interna'
                    : 'Confirmar minha localização',
              ),
            ),
          ),
          if (!presence.isAtGran) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onPreview,
                icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                label: const Text('Pré-visualizar rota interna'),
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
        'A rota interna pode começar agora.',
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
        'Assim o app sabe quando liberar a navegação interna.',
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

  const _ActiveNavigationSheet({
    required this.route,
    required this.session,
    required this.onToggle,
    required this.onRecalculate,
    required this.onEnd,
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
              onPressed: session.hasArrived ? onEnd : onToggle,
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
                    ? 'Pausar navegação'
                    : 'Continuar navegação',
              ),
            ),
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
    const labels = ['2D', '3D', 'Walk', 'AR'];
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF20A1728),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GranMapColors.line),
      ),
      child: Column(
        children: [
          for (var index = 0; index < labels.length; index++)
            InkWell(
              onTap: () => onSelected(index),
              child: Container(
                width: 48,
                height: 34,
                alignment: Alignment.center,
                color: selected == index
                    ? GranMapColors.orange.withValues(alpha: .12)
                    : Colors.transparent,
                child: Text(
                  labels[index],
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected == index
                        ? GranMapColors.orange
                        : GranMapColors.textMuted,
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

String _confidenceLabel(double value) {
  if (value >= .75) return 'Posição precisa';
  if (value >= .45) return 'Posição aproximada';
  return 'Baixa confiança';
}
