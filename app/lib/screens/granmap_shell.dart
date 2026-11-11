import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/campus_map_repository.dart';
import '../models/campus_map.dart';
import '../positioning/app_sensor_service.dart';
import '../positioning/gran_presence_service.dart';
import '../services/community_sync_coordinator.dart';
import '../theme/granmap_theme.dart';
import '../widgets/granmap_ui.dart';
import 'community_screen.dart';
import 'home_screen.dart';
import 'map_screen.dart';
import 'profile_screen.dart';
import 'route_screen.dart';
import 'search_screen.dart';

class GranMapShell extends StatefulWidget {
  final CampusMap campus;
  final Set<String> blockedEdgeIds;
  final String mapVersion;
  final CampusMapSource mapSource;
  final DateTime? mapUpdatedAt;
  final String? mapWarning;

  const GranMapShell({
    super.key,
    required this.campus,
    required this.blockedEdgeIds,
    required this.mapVersion,
    required this.mapSource,
    this.mapUpdatedAt,
    this.mapWarning,
  });

  @override
  State<GranMapShell> createState() => _GranMapShellState();
}

class _GranMapShellState extends State<GranMapShell>
    with WidgetsBindingObserver {
  int _index = 0;
  int _requestedRouteView = 0;
  final Set<int> _visitedPages = {0};
  final AppSensorService _sensors = AppSensorService.instance;
  final GranPresenceService _presence = GranPresenceService.instance;
  final CommunitySyncCoordinator _communitySync =
      CommunitySyncCoordinator.instance;

  static const _items = [
    _NavItem(Icons.home_rounded, Icons.home_outlined, 'Início'),
    _NavItem(Icons.search_rounded, Icons.search_rounded, 'Buscar'),
    _NavItem(Icons.navigation_rounded, Icons.navigation_outlined, 'Mapa'),
    _NavItem(Icons.groups_rounded, Icons.groups_outlined, 'Comunidade'),
    _NavItem(Icons.person_rounded, Icons.person_outline_rounded, 'Perfil'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_sensors.start());
    unawaited(_presence.start());
    _communitySync.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    unawaited(_sensors.setForeground(foreground));
    unawaited(_presence.setForeground(foreground));
    _communitySync.setForeground(foreground);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_sensors.stop());
    unawaited(_presence.stop());
    _communitySync.stop();
    super.dispose();
  }

  void _select(int index) {
    if (index == _index && (index != 1 || _requestedRouteView == 0)) return;
    HapticFeedback.selectionClick();
    setState(() {
      // Camera navigation is a destination-picking intent, not a sticky
      // preference for every later search opened from the bottom bar.
      if (index == 1) _requestedRouteView = 0;
      _visitedPages.add(index);
      _index = index;
    });
  }

  void _requestRouteView(int view) {
    setState(() {
      _requestedRouteView = view == 2 ? 0 : view.clamp(0, 3);
      _visitedPages.add(1);
      _index = 1;
    });
  }

  void _openPoiRoute(CampusPoi poi) {
    if (widget.campus.pois.isEmpty) return;
    final origin =
        widget.campus.poiById('entrada_gran') ?? widget.campus.pois.first;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RouteScreen(
          campus: widget.campus,
          origin: origin,
          destination: poi,
          blockedEdgeIds: widget.blockedEdgeIds,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _visitedPages.contains(0)
          ? HomeScreen(
              campus: widget.campus,
              blockedEdgeIds: widget.blockedEdgeIds,
              onSearchRequested: () => _select(1),
            )
          : const SizedBox.shrink(),
      _visitedPages.contains(1)
          ? SearchScreen(
              campus: widget.campus,
              blockedEdgeIds: widget.blockedEdgeIds,
              initialRouteView: _requestedRouteView,
            )
          : const SizedBox.shrink(),
      _visitedPages.contains(2)
          ? MapScreen(
              campus: widget.campus,
              onSearchRequested: () => _select(1),
              onRouteModeRequested: _requestRouteView,
              onPoiRouteRequested: _openPoiRoute,
            )
          : const SizedBox.shrink(),
      _visitedPages.contains(3)
          ? const CommunityScreen()
          : const SizedBox.shrink(),
      _visitedPages.contains(4)
          ? ProfileScreen(
              campus: widget.campus,
              blockedEdgeIds: widget.blockedEdgeIds,
            )
          : const SizedBox.shrink(),
    ];

    return Scaffold(
      extendBody: true,
      body: GranMapBackdrop(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              if (widget.mapWarning != null)
                _MapFreshnessBanner(
                  source: widget.mapSource,
                  updatedAt: widget.mapUpdatedAt,
                  warning: widget.mapWarning,
                ),
              Expanded(
                child: IndexedStack(index: _index, children: pages),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _GranMapBottomBar(
        items: _items,
        selectedIndex: _index,
        onSelected: _select,
      ),
    );
  }
}

class _MapFreshnessBanner extends StatelessWidget {
  final CampusMapSource source;
  final DateTime? updatedAt;
  final String? warning;

  const _MapFreshnessBanner({
    required this.source,
    required this.updatedAt,
    required this.warning,
  });

  @override
  Widget build(BuildContext context) {
    final bundled = source == CampusMapSource.bundled;
    final text =
        warning ??
        (bundled
            ? 'Mapa offline incluído no aplicativo.'
            : 'Mapa salvo em ${_format(updatedAt)}.');
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        color: (bundled ? GranMapColors.violet : GranMapColors.amber)
            .withValues(alpha: .12),
        child: Row(
          children: [
            Icon(
              bundled ? Icons.offline_bolt_rounded : Icons.cloud_off_rounded,
              size: 17,
              color: bundled ? GranMapColors.violet : GranMapColors.amber,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
  }

  String _format(DateTime? date) {
    if (date == null) return 'uma sessão anterior';
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _GranMapBottomBar extends StatelessWidget {
  final List<_NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _GranMapBottomBar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: GranMapColors.inkSoft,
        border: Border(top: BorderSide(color: GranMapColors.line)),
        boxShadow: [
          BoxShadow(
            color: Color(0x77000000),
            blurRadius: 24,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 70,
          child: Row(
            children: [
              for (var index = 0; index < items.length; index++)
                Expanded(
                  child: _NavigationItem(
                    item: items[index],
                    selected: index == selectedIndex,
                    prominent: index == 2,
                    onTap: () => onSelected(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final bool prominent;
  final VoidCallback onTap;

  const _NavigationItem({
    required this.item,
    required this.selected,
    required this.prominent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tone = selected ? GranMapColors.orange : GranMapColors.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: prominent ? 46 : 34,
              height: prominent ? 42 : 30,
              decoration: BoxDecoration(
                color: prominent
                    ? (selected
                          ? GranMapColors.orange
                          : GranMapColors.orange.withValues(alpha: .12))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(prominent ? 13 : 10),
                border: prominent
                    ? Border.all(
                        color: selected
                            ? GranMapColors.orange
                            : GranMapColors.orange.withValues(alpha: .28),
                      )
                    : null,
                boxShadow: prominent && selected
                    ? [
                        BoxShadow(
                          color: GranMapColors.orange.withValues(alpha: .32),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                selected ? item.selectedIcon : item.icon,
                color: prominent && selected ? Colors.white : tone,
                size: prominent ? 22 : 20,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: tone,
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData selectedIcon;
  final IconData icon;
  final String label;

  const _NavItem(this.selectedIcon, this.icon, this.label);
}
