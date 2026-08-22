import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/campus_map.dart';
import '../navigation/navigation_service.dart';
import '../navigation/navigation_session.dart';
import '../navigation/route_result.dart';
import '../services/app_preferences.dart';
import '../services/app_runtime_config.dart';
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

  const RouteScreen({
    super.key,
    required this.campus,
    required this.origin,
    required this.destination,
    this.blockedEdgeIds = const {},
  });

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  final _navigation = const NavigationService();
  RouteResult? _route;
  NavigationSession? _session;
  bool _accessibleOnly = AppPreferences.instance.accessibleRoutes;
  int _view = 0;
  int _lastFeedbackSegment = -1;

  @override
  void initState() {
    super.initState();
    _configure();
  }

  @override
  void dispose() {
    _session?.removeListener(_changed);
    _session?.dispose();
    super.dispose();
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
        title: const Text('Navegação ativa'),
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
  final VoidCallback onStart;

  const _DestinationSheet({
    required this.destination,
    required this.route,
    required this.accessible,
    required this.onStart,
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
                onPressed: () {},
                icon: const Icon(
                  Icons.favorite_border_rounded,
                  color: GranMapColors.textMuted,
                ),
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(
                  Icons.share_outlined,
                  color: GranMapColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.near_me_rounded, size: 18),
              label: const Text('Iniciar navegação'),
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
