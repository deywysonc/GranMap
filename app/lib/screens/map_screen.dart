import 'dart:async';

import 'package:flutter/material.dart';

import '../models/campus_map.dart';
import '../positioning/gran_presence_service.dart';
import '../services/external_maps_service.dart';
import '../theme/granmap_theme.dart';
import '../widgets/campus_map_canvas.dart';
import '../widgets/campus_twin_canvas.dart';

class MapScreen extends StatefulWidget {
  final CampusMap campus;
  final VoidCallback? onSearchRequested;
  final ValueChanged<int>? onRouteModeRequested;
  final ValueChanged<CampusPoi>? onPoiRouteRequested;

  const MapScreen({
    super.key,
    required this.campus,
    this.onSearchRequested,
    this.onRouteModeRequested,
    this.onPoiRouteRequested,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final GranPresenceService _presence = GranPresenceService.instance;
  final ExternalMapsService _externalMaps = const ExternalMapsService();
  int _floor = 0;
  int _view = 0;
  int _cameraReset = 0;
  String? _selectedPoiId;

  @override
  void initState() {
    super.initState();
    if (!widget.campus.floors.any((floor) => floor.level == _floor) &&
        widget.campus.floors.isNotEmpty) {
      _floor = widget.campus.floors.first.level;
    }
    _presence.addListener(_onPresenceChanged);
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.campus, widget.campus)) return;
    if (!widget.campus.floors.any((floor) => floor.level == _floor) &&
        widget.campus.floors.isNotEmpty) {
      _floor = widget.campus.floors.first.level;
    }
    if (widget.campus.poiById(_selectedPoiId ?? '')?.floor != _floor) {
      _selectedPoiId = null;
    }
  }

  @override
  void dispose() {
    _presence.removeListener(_onPresenceChanged);
    super.dispose();
  }

  void _onPresenceChanged() {
    if (mounted) setState(() {});
  }

  void _selectPoi(CampusPoi poi) {
    setState(() {
      _selectedPoiId = poi.id;
      _floor = poi.floor;
    });
  }

  void _selectFloor(int floor) {
    if (_floor == floor) return;
    setState(() {
      _floor = floor;
      _selectedPoiId = null;
      _cameraReset++;
    });
  }

  void _requestCameraRoute() {
    if (widget.onRouteModeRequested != null) {
      widget.onRouteModeRequested!(3);
    } else {
      widget.onSearchRequested?.call();
    }
  }

  Future<void> _handleLocationAction() async {
    final snapshot = _presence.snapshot;
    if (snapshot.isAway) {
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
    if (snapshot.status == GranPresenceStatus.permissionDenied ||
        snapshot.status == GranPresenceStatus.servicesDisabled) {
      await _presence.openRequiredSettings();
      return;
    }
    if (snapshot.status == GranPresenceStatus.unavailable ||
        snapshot.status == GranPresenceStatus.uncertain ||
        snapshot.status == GranPresenceStatus.checking) {
      await _presence.refresh();
    }
    if (!mounted) return;
    setState(() => _cameraReset++);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mapa interno recentralizado.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final floors = widget.campus.floors.toList()
      ..sort((a, b) => a.level.compareTo(b.level));
    final selected = widget.campus.poiById(_selectedPoiId ?? '');
    final places = widget.campus.pois
        .where((poi) => poi.floor == _floor)
        .length;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        78 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Material(
                  color: GranMapColors.navy,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: widget.onSearchRequested,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: GranMapColors.line),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.search_rounded,
                            color: GranMapColors.orange,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Para onde você vai?',
                              style: TextStyle(color: GranMapColors.textMuted),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _MapSquareButton(
                icon: Icons.camera_alt_outlined,
                tooltip: 'Navegar com câmera',
                onTap: _requestCameraRoute,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<int>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: [
                      for (final floor in floors)
                        ButtonSegment(
                          value: floor.level,
                          label: Text(_floorLabel(floor.level)),
                        ),
                    ],
                    selected: {_floor},
                    onSelectionChanged: (selection) =>
                        _selectFloor(selection.first),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SegmentedButton<int>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: const [
                  ButtonSegment(value: 0, label: Text('2D')),
                  ButtonSegment(value: 1, label: Text('3D')),
                ],
                selected: {_view},
                onSelectionChanged: (selection) =>
                    setState(() => _view = selection.first),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ClipRRect(
              key: const ValueKey('map-explore-viewport'),
              borderRadius: BorderRadius.circular(20),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _view == 1
                    ? CampusTwinCanvas(
                        key: ValueKey('twin_${_floor}_$_cameraReset'),
                        campus: widget.campus,
                        focusFloor: _floor,
                        selectedPoiId: _selectedPoiId,
                        onPoiSelected: _selectPoi,
                      )
                    : CampusMapCanvas(
                        key: ValueKey('map_${_floor}_$_cameraReset'),
                        campus: widget.campus,
                        floor: _floor,
                        fullBleed: true,
                        selectedPoiId: _selectedPoiId,
                        onPoiSelected: _selectPoi,
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (selected != null)
            _SelectedPlaceCard(
              poi: selected,
              onClose: () => setState(() => _selectedPoiId = null),
              onRoute: () {
                if (widget.onPoiRouteRequested != null) {
                  widget.onPoiRouteRequested!(selected);
                } else {
                  widget.onSearchRequested?.call();
                }
              },
            )
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_floorLabel(_floor)} · $places locais',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: GranMapColors.textMuted),
                  ),
                ),
                IconButton(
                  tooltip: 'Guia e legenda do mapa',
                  onPressed: _showMapGuide,
                  icon: const Icon(Icons.info_outline_rounded, size: 20),
                ),
                IconButton(
                  tooltip: _locationTooltip,
                  onPressed: () => unawaited(_handleLocationAction()),
                  icon: Icon(
                    Icons.my_location_rounded,
                    color: _locationTone,
                    size: 20,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _showMapGuide() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .8,
      ),
      builder: (context) => SingleChildScrollView(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Explore a Gran Tietê',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Toque em um local para ver os detalhes e traçar a rota. Arraste para explorar e use dois dedos para ampliar.',
                ),
                const SizedBox(height: 16),
                const _LegendRow(Color(0xFF8BAECD), 'Salas'),
                const _LegendRow(Color(0xFF70B9CB), 'Laboratórios'),
                const _LegendRow(Color(0xFF7BBDB6), 'Entradas e serviços'),
                const _LegendRow(Color(0xFFDDA36D), 'Circulação e lanchonete'),
                const _LegendRow(Color(0xFF87B99D), 'Áreas abertas e quadra'),
                const _LegendRow(
                  GranMapColors.orange,
                  'Rota e local selecionado',
                ),
                const SizedBox(height: 12),
                Text(
                  _locationSummary,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _locationSummary => switch (_presence.snapshot.status) {
    GranPresenceStatus.inside => 'Você está na Gran Tietê',
    GranPresenceStatus.nearby =>
      '${_presence.snapshot.distanceLabel} da Gran Tietê',
    GranPresenceStatus.outside =>
      '${_presence.snapshot.distanceLabel} da Gran Tietê',
    GranPresenceStatus.permissionDenied => 'Localização sem permissão',
    GranPresenceStatus.servicesDisabled => 'GPS desligado',
    GranPresenceStatus.uncertain => 'Posição atual ainda não confirmada',
    GranPresenceStatus.unavailable => 'Posição indisponível',
    GranPresenceStatus.checking => 'Verificando localização',
  };

  String get _locationTooltip => _presence.snapshot.isAway
      ? 'Abrir rota externa até a Gran Tietê'
      : 'Atualizar minha localização';

  Color get _locationTone => switch (_presence.snapshot.status) {
    GranPresenceStatus.inside => GranMapColors.mint,
    GranPresenceStatus.nearby => GranMapColors.sky,
    GranPresenceStatus.outside => GranMapColors.orange,
    GranPresenceStatus.permissionDenied ||
    GranPresenceStatus.servicesDisabled => GranMapColors.amber,
    _ => GranMapColors.textMuted,
  };
}

class _MapSquareButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _MapSquareButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    tooltip: tooltip,
    onPressed: onTap,
    icon: Icon(icon, color: GranMapColors.orange),
    style: IconButton.styleFrom(
      fixedSize: const Size(48, 48),
      backgroundColor: GranMapColors.navy,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: GranMapColors.line),
      ),
    ),
  );
}

class _SelectedPlaceCard extends StatelessWidget {
  final CampusPoi poi;
  final VoidCallback onClose;
  final VoidCallback onRoute;

  const _SelectedPlaceCard({
    required this.poi,
    required this.onClose,
    required this.onRoute,
  });

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('map-selected-place'),
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
    decoration: BoxDecoration(
      color: GranMapColors.navy,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: GranMapColors.orange.withValues(alpha: .35)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                poi.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 3),
              Text(
                '${_placeType(poi.type)} · ${_floorLabel(poi.floor)}',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: GranMapColors.textMuted),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: onRoute,
                icon: const Icon(Icons.near_me_rounded, size: 17),
                label: const Text('Ir para cá'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Fechar local selecionado',
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
  );
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendRow(this.color, this.label);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    ),
  );
}

String _floorLabel(int floor) => floor == 0
    ? 'Térreo'
    : floor == 1
    ? 'Superior'
    : 'Piso $floor';

String _placeType(String type) => switch (type) {
  'classroom' => 'Sala',
  'laboratory' || 'project_laboratory' => 'Laboratório',
  'entrance' || 'upper_entrance' => 'Entrada',
  'library' => 'Biblioteca',
  'administration' => 'Secretaria',
  'finance' => 'Financeiro',
  'restroom' => 'Banheiros',
  'court' => 'Quadra',
  'cafeteria' => 'Lanchonete',
  'ramp' => 'Rampa',
  'auditorium' => 'Auditório',
  'agronomy' => 'Área de agronomia',
  _ => 'Local',
};
