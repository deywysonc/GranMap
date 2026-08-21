import 'package:flutter/material.dart';

import '../models/academic.dart';
import '../models/campus_map.dart';
import '../models/personal_data.dart';
import '../services/app_session.dart';
import '../services/next_class_service.dart';
import '../services/personal_data_service.dart';
import '../services/user_academic_service.dart';
import '../theme/granmap_theme.dart';
import '../widgets/granmap_ui.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';
import 'route_screen.dart';

class HomeScreen extends StatefulWidget {
  final CampusMap campus;
  final Set<String> blockedEdgeIds;
  final VoidCallback? onSearchRequested;

  const HomeScreen({
    super.key,
    required this.campus,
    this.blockedEdgeIds = const {},
    this.onSearchRequested,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _nextClass = const NextClassService();
  final _personal = PersonalDataService();
  final _academic = UserAcademicService();

  List<String> _favorites = const [];
  List<NavigationHistoryItem> _history = const [];
  AcademicSnapshot? _snapshot;
  bool _loadingAcademic = false;

  @override
  void initState() {
    super.initState();
    AppSession.instance.addListener(_sessionChanged);
    _reloadAll();
  }

  @override
  void dispose() {
    AppSession.instance.removeListener(_sessionChanged);
    _personal.dispose();
    _academic.dispose();
    super.dispose();
  }

  void _sessionChanged() {
    if (!mounted) return;
    setState(() {});
    _reloadAll();
  }

  Future<void> _reloadAll() async {
    if (mounted) setState(() => _loadingAcademic = true);
    final values = await Future.wait<dynamic>([
      _personal.loadFavorites(),
      _personal.loadHistory(),
      _academic.load(),
    ]);
    if (!mounted) return;
    setState(() {
      _favorites = values[0] as List<String>;
      _history = values[1] as List<NavigationHistoryItem>;
      _snapshot = values[2] as AcademicSnapshot;
      _loadingAcademic = false;
    });
  }

  CampusPoi get _origin =>
      widget.campus.poiById('entrada_gran') ?? widget.campus.pois.first;

  Future<void> _openRoute(CampusPoi destination) async {
    await _personal.addHistory(
      poiId: destination.id,
      poiName: destination.name,
    );
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RouteScreen(
          campus: widget.campus,
          origin: _origin,
          destination: destination,
          blockedEdgeIds: widget.blockedEdgeIds,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;
    final user = session.user;
    final next = _nextClass.findNext(
      _snapshot?.classes ?? const <AcademicClass>[],
    );
    final recentPois = _recentPois();

    return RefreshIndicator(
      onRefresh: _reloadAll,
      color: GranMapColors.orange,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 108),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GranMapFadeSlide(
                    child: _HomeHeader(
                      name: user?.name,
                      unread: session.unreadNotifications,
                      onNotifications: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const NotificationsScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  _LocationStatus(online: session.backendReachable),
                  const SizedBox(height: 16),
                  GranMapFadeSlide(
                    delay: const Duration(milliseconds: 60),
                    child: _NextClassCard(
                      userLoggedIn: user != null,
                      loading: _loadingAcademic,
                      next: next,
                      snapshot: _snapshot,
                      campus: widget.campus,
                      onLogin: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                        );
                      },
                      onNavigate: _openRoute,
                    ),
                  ),
                  const SizedBox(height: 18),
                  InkWell(
                    onTap: widget.onSearchRequested,
                    borderRadius: BorderRadius.circular(14),
                    child: IgnorePointer(
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Buscar sala, professor, local...',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _SmallSectionLabel('ATALHOS RÁPIDOS'),
                  const SizedBox(height: 11),
                  _QuickAccessGrid(campus: widget.campus, onTap: _openRoute),
                  const SizedBox(height: 22),
                  const _SmallSectionLabel('RECENTES'),
                  const SizedBox(height: 10),
                  for (final poi in recentPois) ...[
                    _RecentDestination(poi: poi, onTap: () => _openRoute(poi)),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 6),
                  _OfflineNotice(
                    online: session.backendReachable,
                    bundled: _snapshot?.isOnline != true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<CampusPoi> _recentPois() {
    final result = <CampusPoi>[];
    for (final item in _history) {
      final poi = widget.campus.poiById(item.poiId);
      if (poi != null && !result.any((old) => old.id == poi.id)) {
        result.add(poi);
      }
      if (result.length == 3) return result;
    }
    for (final id in _favorites) {
      final poi = widget.campus.poiById(id);
      if (poi != null && !result.any((old) => old.id == poi.id)) {
        result.add(poi);
      }
      if (result.length == 3) return result;
    }
    for (final id in ['entrada_gran', 'biblioteca']) {
      final poi = widget.campus.poiById(id);
      if (poi != null && !result.any((old) => old.id == poi.id)) {
        result.add(poi);
      }
    }
    return result.take(3).toList();
  }
}

class _HomeHeader extends StatelessWidget {
  final String? name;
  final int unread;
  final VoidCallback onNotifications;

  const _HomeHeader({
    required this.name,
    required this.unread,
    required this.onNotifications,
  });

  @override
  Widget build(BuildContext context) {
    final firstName = name?.trim().split(RegExp(r'\s+')).first;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                firstName == null
                    ? 'Bem-vindo ao GranMap'
                    : '${_greeting()}, $firstName 👋',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: GranMapColors.textMuted),
              ),
              const SizedBox(height: 2),
              Text(
                'O que você procura?',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Notificações',
          onPressed: onNotifications,
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text('$unread'),
            child: const Icon(Icons.notifications_none_rounded, size: 21),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [GranMapColors.orangeLight, GranMapColors.orange],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(
              _initials(name),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Bom dia';
    if (hour < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  static String _initials(String? value) {
    if (value == null || value.trim().isEmpty) return 'GM';
    final words = value.trim().split(RegExp(r'\s+'));
    return words.take(2).map((word) => word[0].toUpperCase()).join();
  }
}

class _LocationStatus extends StatelessWidget {
  final bool online;

  const _LocationStatus({required this.online});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: GranMapColors.navy,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GranMapColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: online ? GranMapColors.mint : GranMapColors.amber,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              online
                  ? 'GranMap sincronizado • Térreo'
                  : 'Mapa offline disponível • Térreo',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: GranMapColors.textMuted),
            ),
          ),
          Icon(
            online ? Icons.wifi_rounded : Icons.offline_bolt_rounded,
            size: 16,
            color: online ? GranMapColors.mint : GranMapColors.amber,
          ),
        ],
      ),
    );
  }
}

class _NextClassCard extends StatelessWidget {
  final bool userLoggedIn;
  final bool loading;
  final NextClassInfo? next;
  final AcademicSnapshot? snapshot;
  final CampusMap campus;
  final VoidCallback onLogin;
  final ValueChanged<CampusPoi> onNavigate;

  const _NextClassCard({
    required this.userLoggedIn,
    required this.loading,
    required this.next,
    required this.snapshot,
    required this.campus,
    required this.onLogin,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const GranMapSurface(child: LinearProgressIndicator());
    }
    if (!userLoggedIn) {
      return GranMapSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _OrangeEyebrow('SUA ROTINA ACADÊMICA'),
            const SizedBox(height: 9),
            Text(
              'Entre para ver sua próxima aula',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onLogin,
                icon: const Icon(Icons.login_rounded, size: 18),
                label: const Text('Entrar no GranMap'),
              ),
            ),
          ],
        ),
      );
    }
    final info = next;
    if (info == null) {
      return GranMapSurface(
        child: Row(
          children: [
            const GranMapIconBadge(
              icon: Icons.event_available_rounded,
              color: GranMapColors.mint,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Agenda livre agora',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    snapshot?.message ?? 'Nenhuma próxima aula encontrada.',
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
    final item = info.academicClass;
    final room = campus.poiById(item.roomPoiId);
    return GranMapSurface(
      border: Border.all(color: const Color(0xFF20334C)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _OrangeEyebrow(
                info.isCurrent ? 'ACONTECENDO AGORA' : 'PRÓXIMA AULA',
              ),
              const Spacer(),
              Text(
                _relative(info),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: GranMapColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(item.subject, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 7),
          Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 15,
                color: GranMapColors.textMuted,
              ),
              const SizedBox(width: 5),
              Text(
                '${item.startTime} – ${item.endTime}',
                style: _detailStyle(context),
              ),
              const SizedBox(width: 13),
              const Icon(
                Icons.location_on_outlined,
                size: 15,
                color: GranMapColors.textMuted,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  item.roomName,
                  style: _detailStyle(context),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: room == null ? null : () => onNavigate(room),
              icon: const Icon(Icons.near_me_rounded, size: 18),
              label: Text(
                info.isCurrent ? 'Ir para esta aula' : 'Ir para minha aula',
              ),
            ),
          ),
        ],
      ),
    );
  }

  static TextStyle? _detailStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: GranMapColors.textMuted);

  static String _relative(NextClassInfo info) {
    if (info.isCurrent) return 'agora';
    final duration = info.startsAt.difference(DateTime.now());
    if (duration.inDays > 0) return 'em ${duration.inDays} d';
    if (duration.inHours > 0) return 'em ${duration.inHours} h';
    return 'em ${duration.inMinutes.clamp(0, 999)} min';
  }
}

class _OrangeEyebrow extends StatelessWidget {
  final String text;
  const _OrangeEyebrow(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: GranMapColors.orange,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 7),
        Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: GranMapColors.orange,
            fontWeight: FontWeight.w800,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _SmallSectionLabel extends StatelessWidget {
  final String text;
  const _SmallSectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: GranMapColors.textMuted,
        letterSpacing: 1.1,
        fontSize: 10,
      ),
    );
  }
}

class _QuickAccessGrid extends StatelessWidget {
  final CampusMap campus;
  final ValueChanged<CampusPoi> onTap;

  const _QuickAccessGrid({required this.campus, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const items = [
      ('secretaria', 'Secretaria', Icons.apartment_rounded, GranMapColors.sky),
      (
        'biblioteca',
        'Biblioteca',
        Icons.menu_book_rounded,
        GranMapColors.violet,
      ),
      (
        'financeiro',
        'Financeiro',
        Icons.star_outline_rounded,
        GranMapColors.amber,
      ),
      (
        'banheiros',
        'Banheiros',
        Icons.location_on_outlined,
        GranMapColors.mint,
      ),
    ];
    return Row(
      children: [
        for (var index = 0; index < items.length; index++) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(
            child: _QuickTile(
              label: items[index].$2,
              icon: items[index].$3,
              color: items[index].$4,
              onTap: () {
                final poi = campus.poiById(items[index].$1);
                if (poi != null) onTap(poi);
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _QuickTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
        decoration: BoxDecoration(
          color: GranMapColors.inkSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: GranMapColors.line),
        ),
        child: Column(
          children: [
            GranMapIconBadge(icon: icon, color: color, size: 36),
            const SizedBox(height: 7),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(fontSize: 9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentDestination extends StatelessWidget {
  final CampusPoi poi;
  final VoidCallback onTap;

  const _RecentDestination({required this.poi, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GranMapSurface(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      onTap: onTap,
      child: Row(
        children: [
          const Icon(
            Icons.history_rounded,
            size: 18,
            color: GranMapColors.textMuted,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(poi.name, style: Theme.of(context).textTheme.labelLarge),
                Text(
                  '${poi.floor == 0 ? 'Térreo' : 'Piso ${poi.floor}'}${poi.sector.isEmpty ? '' : ' • ${poi.sector}'}',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: GranMapColors.textMuted),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: GranMapColors.textMuted,
          ),
        ],
      ),
    );
  }
}

class _OfflineNotice extends StatelessWidget {
  final bool online;
  final bool bundled;

  const _OfflineNotice({required this.online, required this.bundled});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: GranMapColors.mint.withValues(alpha: .055),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GranMapColors.mint.withValues(alpha: .18)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.offline_pin_rounded,
            color: GranMapColors.mint,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mapa offline disponível',
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: GranMapColors.mint),
                ),
                Text(
                  online && !bundled
                      ? 'Dados sincronizados. Navegação disponível sem internet.'
                      : 'Navegação principal disponível neste aparelho.',
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
