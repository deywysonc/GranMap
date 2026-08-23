import 'package:flutter/material.dart';

import '../models/campus_map.dart';
import '../services/personal_data_service.dart';
import '../services/search_service.dart';
import '../theme/granmap_theme.dart';
import '../widgets/granmap_ui.dart';
import 'route_screen.dart';

class SearchScreen extends StatefulWidget {
  final CampusMap campus;
  final Set<String> blockedEdgeIds;
  final int initialRouteView;

  const SearchScreen({
    super.key,
    required this.campus,
    this.blockedEdgeIds = const {},
    this.initialRouteView = 0,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _search = const SearchService();
  final _personal = PersonalDataService();
  List<CampusPoi> _results = const [];
  List<String> _favorites = const [];
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _results = widget.campus.pois;
    _loadFavorites();
  }

  @override
  void dispose() {
    _controller.dispose();
    _personal.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    final value = await _personal.loadFavorites();
    if (mounted) setState(() => _favorites = value);
  }

  void _apply() {
    final matches = _search.search(widget.campus.pois, _controller.text);
    setState(() {
      _results = matches
          .where((poi) {
            return switch (_filter) {
              'rooms' => poi.type == 'classroom' || poi.type == 'auditorium',
              'labs' => poi.type == 'laboratory',
              'services' => const {
                'library',
                'finance',
                'restroom',
                'cafeteria',
                'court',
              }.contains(poi.type),
              'admin' => poi.type == 'administration',
              _ => true,
            };
          })
          .toList(growable: false);
    });
  }

  CampusPoi get _origin =>
      widget.campus.poiById('entrada_gran') ?? widget.campus.pois.first;

  Future<void> _open(CampusPoi poi) async {
    await _personal.addHistory(poiId: poi.id, poiName: poi.name);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RouteScreen(
          campus: widget.campus,
          origin: _origin,
          destination: poi,
          blockedEdgeIds: widget.blockedEdgeIds,
          initialView: widget.initialRouteView,
        ),
      ),
    );
  }

  Future<void> _toggle(CampusPoi poi) async {
    final value = await _personal.toggleFavorite(poi.id, _favorites);
    if (mounted) setState(() => _favorites = value);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 108),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Buscar',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (widget.initialRouteView >= 2) ...[
                  const SizedBox(height: 12),
                  GranMapSurface(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 11,
                    ),
                    gradient: LinearGradient(
                      colors: [
                        GranMapColors.orange.withValues(alpha: .14),
                        GranMapColors.violet.withValues(alpha: .08),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          widget.initialRouteView == 2
                              ? Icons.directions_walk_rounded
                              : Icons.view_in_ar_rounded,
                          color: GranMapColors.orange,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Escolha o destino para abrir o modo ${widget.initialRouteView == 2 ? 'Walk' : 'AR'}.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  autofocus: false,
                  onChanged: (_) => _apply(),
                  decoration: InputDecoration(
                    hintText: 'Sala, laboratório, professor...',
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: GranMapColors.orange,
                    ),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _controller.clear();
                              _apply();
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _SearchFilter(
                        label: 'Todos',
                        selected: _filter == 'all',
                        onTap: () => _setFilter('all'),
                      ),
                      _SearchFilter(
                        label: 'Salas',
                        selected: _filter == 'rooms',
                        onTap: () => _setFilter('rooms'),
                      ),
                      _SearchFilter(
                        label: 'Labs',
                        selected: _filter == 'labs',
                        onTap: () => _setFilter('labs'),
                      ),
                      _SearchFilter(
                        label: 'Serviços',
                        selected: _filter == 'services',
                        onTap: () => _setFilter('services'),
                      ),
                      _SearchFilter(
                        label: 'Admin',
                        selected: _filter == 'admin',
                        onTap: () => _setFilter('admin'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (_results.isEmpty)
                  const GranMapEmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'Nada encontrado',
                    message: 'Tente outro nome ou selecione outro filtro.',
                  )
                else
                  for (final poi in _results) ...[
                    _SearchResultCard(
                      poi: poi,
                      favorite: _favorites.contains(poi.id),
                      onFavorite: () => _toggle(poi),
                      onTap: () => _open(poi),
                    ),
                    const SizedBox(height: 9),
                  ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _setFilter(String value) {
    _filter = value;
    _apply();
  }
}

class _SearchFilter extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SearchFilter({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? GranMapColors.orange : GranMapColors.navy,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected ? GranMapColors.orange : GranMapColors.line,
            ),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: selected ? Colors.white : GranMapColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  final CampusPoi poi;
  final bool favorite;
  final VoidCallback onFavorite;
  final VoidCallback onTap;

  const _SearchResultCard({
    required this.poi,
    required this.favorite,
    required this.onFavorite,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tone = _tone(poi.type);
    return GranMapSurface(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      onTap: onTap,
      child: Row(
        children: [
          GranMapIconBadge(icon: _icon(poi.type), color: tone, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(poi.name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  '${_typeLabel(poi.type)} • ${poi.floor == 0 ? 'Térreo' : 'Piso ${poi.floor}'}${poi.sector.isEmpty ? '' : ' • ${poi.sector}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: GranMapColors.textMuted),
                ),
              ],
            ),
          ),
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: GranMapColors.mint,
              shape: BoxShape.circle,
            ),
          ),
          IconButton(
            tooltip: favorite ? 'Remover dos favoritos' : 'Favoritar',
            onPressed: onFavorite,
            icon: Icon(
              favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: favorite ? GranMapColors.orange : GranMapColors.orange,
              size: 18,
            ),
          ),
          IconButton(
            tooltip: 'Traçar rota até ${poi.name}',
            onPressed: onTap,
            icon: const Icon(
              Icons.near_me_rounded,
              color: GranMapColors.orange,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

String _typeLabel(String type) => switch (type) {
  'classroom' => 'Sala acadêmica',
  'laboratory' => 'Laboratório',
  'administration' => 'Administrativo',
  'library' => 'Serviços',
  'finance' => 'Administrativo',
  'restroom' => 'Serviços',
  'cafeteria' => 'Alimentação',
  'entrance' || 'upper_entrance' => 'Entrada',
  _ => 'Local',
};

IconData _icon(String type) => switch (type) {
  'laboratory' => Icons.science_outlined,
  'library' => Icons.menu_book_rounded,
  'finance' => Icons.star_outline_rounded,
  'restroom' => Icons.wc_rounded,
  'cafeteria' => Icons.local_cafe_outlined,
  'administration' => Icons.apartment_rounded,
  'entrance' || 'upper_entrance' => Icons.login_rounded,
  _ => Icons.location_on_outlined,
};

Color _tone(String type) => switch (type) {
  'library' => GranMapColors.violet,
  'finance' => GranMapColors.amber,
  'restroom' => GranMapColors.mint,
  'cafeteria' => const Color(0xFFE845A1),
  'administration' => GranMapColors.sky,
  _ => GranMapColors.sky,
};
