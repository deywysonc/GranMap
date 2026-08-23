import 'package:flutter/material.dart';

import '../models/campus_map.dart';
import '../theme/granmap_theme.dart';
import '../widgets/campus_map_canvas.dart';
import '../widgets/campus_twin_canvas.dart';

class MapScreen extends StatefulWidget {
  final CampusMap campus;
  final VoidCallback? onSearchRequested;
  final ValueChanged<int>? onRouteModeRequested;

  const MapScreen({
    super.key,
    required this.campus,
    this.onSearchRequested,
    this.onRouteModeRequested,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  int _floor = 0;
  int _view = 0;
  int _cameraReset = 0;

  @override
  Widget build(BuildContext context) {
    final places = widget.campus.pois
        .where((poi) => poi.floor == _floor)
        .length;
    final floorItems =
        widget.campus.floors
            .map(
              (floor) => _SelectorItem(
                floor.level == 0 ? 'T' : '${floor.level}º',
                floor.level,
              ),
            )
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final mapAccuracy =
        _floor == 1 &&
            widget.campus.metadata.geometryStatus == 'floorplan_relative'
        ? 'planta arquitetônica • distâncias provisórias'
        : 'estrutura aproximada';
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 62,
          bottom: 154,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            child: _view == 1
                ? CampusTwinCanvas(
                    key: ValueKey('twin_${_floor}_$_cameraReset'),
                    campus: widget.campus,
                    focusFloor: _floor,
                  )
                : CampusMapCanvas(
                    key: ValueKey('map_${_floor}_$_cameraReset'),
                    campus: widget.campus,
                    floor: _floor,
                    fullBleed: true,
                  ),
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 140,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xEE050C17), Color(0x00050C17)],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 14,
          right: 14,
          top: 12,
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: widget.onSearchRequested,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xF20A1728),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: GranMapColors.line),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x55000000),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          color: GranMapColors.textMuted,
                          size: 20,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Buscar um destino',
                            style: TextStyle(color: GranMapColors.textMuted),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _MapSquareButton(
                icon: Icons.layers_outlined,
                onTap: () => setState(() => _floor = _floor == 0 ? 1 : 0),
              ),
            ],
          ),
        ),
        Positioned(
          left: 14,
          top: 76,
          child: _VerticalSelector(
            items: floorItems,
            selected: _floor,
            onSelected: (value) {
              if (widget.campus.floors.any((floor) => floor.level == value)) {
                setState(() => _floor = value);
              }
            },
          ),
        ),
        Positioned(
          right: 14,
          top: 76,
          child: _ViewSelector(
            selected: _view,
            onSelected: (value) {
              if (value > 1) {
                widget.onRouteModeRequested?.call(value);
                if (widget.onRouteModeRequested == null) {
                  widget.onSearchRequested?.call();
                }
                return;
              }
              setState(() => _view = value);
            },
          ),
        ),
        Positioned(
          right: 14,
          bottom: 188,
          child: _MapSquareButton(
            icon: Icons.my_location_rounded,
            onTap: () {
              setState(() => _cameraReset++);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Mapa recentralizado na Entrada Gran.'),
                ),
              );
            },
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 70,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 13, 18, 16),
            decoration: const BoxDecoration(
              color: Color(0xF5091525),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(top: BorderSide(color: GranMapColors.line)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x88000000),
                  blurRadius: 24,
                  offset: Offset(0, -8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: GranMapColors.orange.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: GranMapColors.orange.withValues(alpha: .25),
                    ),
                  ),
                  child: const Icon(
                    Icons.map_outlined,
                    color: GranMapColors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _floor == 0
                            ? 'Mapa do térreo'
                            : 'Mapa do piso superior',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '$places locais • $mapAccuracy',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: GranMapColors.textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Buscar destino',
                  onPressed: widget.onSearchRequested,
                  icon: const Icon(
                    Icons.near_me_rounded,
                    color: GranMapColors.orange,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MapSquareButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MapSquareButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xF20A1728),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: GranMapColors.line),
          ),
          child: Icon(icon, color: GranMapColors.textMuted, size: 21),
        ),
      ),
    );
  }
}

class _SelectorItem {
  final String label;
  final int value;
  const _SelectorItem(this.label, this.value);
}

class _VerticalSelector extends StatelessWidget {
  final List<_SelectorItem> items;
  final int selected;
  final ValueChanged<int> onSelected;

  const _VerticalSelector({
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF20A1728),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GranMapColors.line),
      ),
      child: Column(
        children: [
          for (final item in items)
            InkWell(
              onTap: () => onSelected(item.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 42,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected == item.value
                      ? GranMapColors.orange.withValues(alpha: .13)
                      : Colors.transparent,
                  border: Border(
                    left: BorderSide(
                      color: selected == item.value
                          ? GranMapColors.orange
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  item.label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: selected == item.value
                        ? GranMapColors.orange
                        : GranMapColors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ViewSelector extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelected;

  const _ViewSelector({required this.selected, required this.onSelected});

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
            Semantics(
              button: true,
              selected: selected == index,
              label: 'Visual ${labels[index]}',
              child: InkWell(
                onTap: () => onSelected(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 52,
                  height: 40,
                  alignment: Alignment.center,
                  color: selected == index
                      ? GranMapColors.orange.withValues(alpha: .13)
                      : Colors.transparent,
                  child: Text(
                    labels[index],
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: selected == index
                          ? GranMapColors.orange
                          : GranMapColors.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
