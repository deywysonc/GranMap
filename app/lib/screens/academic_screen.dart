import 'package:flutter/material.dart';

import '../models/academic.dart';
import '../models/campus_map.dart';
import '../services/app_session.dart';
import '../services/personal_data_service.dart';
import '../services/user_academic_service.dart';
import '../theme/granmap_theme.dart';
import '../widgets/granmap_ui.dart';
import 'login_screen.dart';
import 'route_screen.dart';

class AcademicScreen extends StatefulWidget {
  final CampusMap campus;
  final Set<String> blockedEdgeIds;

  const AcademicScreen({
    super.key,
    required this.campus,
    this.blockedEdgeIds = const {},
  });

  @override
  State<AcademicScreen> createState() => _AcademicScreenState();
}

class _AcademicScreenState extends State<AcademicScreen> {
  final UserAcademicService _academic = UserAcademicService();
  final PersonalDataService _personal = PersonalDataService();

  AcademicSnapshot? _snapshot;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    AppSession.instance.addListener(_sessionChanged);
    _load();
  }

  @override
  void dispose() {
    AppSession.instance.removeListener(_sessionChanged);
    _academic.dispose();
    _personal.dispose();
    super.dispose();
  }

  void _sessionChanged() {
    if (mounted) {
      setState(() {});
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final snapshot = await _academic.load();
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _loading = false;
    });
  }

  CampusPoi get _origin =>
      widget.campus.poiById('entrada_gran') ??
      widget.campus.poiById('entrance_gran') ??
      widget.campus.pois.first;

  Future<void> _navigate(AcademicClass item) async {
    final room = widget.campus.poiById(item.roomPoiId);
    if (room == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.roomName} não existe no mapa.')),
      );
      return;
    }

    await _personal.addHistory(poiId: room.id, poiName: room.name);

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RouteScreen(
          campus: widget.campus,
          origin: _origin,
          destination: room,
          blockedEdgeIds: widget.blockedEdgeIds,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;
    final user = session.user;
    final classes = _snapshot?.classes ?? const <AcademicClass>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Minha grade')),
      body: GranMapBackdrop(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 118),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GranMapFadeSlide(
                        child: GranMapPageHeader(
                          eyebrow: 'Agenda',
                          title: 'Minha vida acadêmica',
                          subtitle: user == null
                              ? 'Sua grade e seus caminhos no mesmo lugar.'
                              : '${user.course} • ${user.semester}º semestre • ${user.group}',
                          trailing: user == null
                              ? null
                              : GranMapStatusPill(
                                  label: _snapshot?.isOnline == true
                                      ? 'Atualizada'
                                      : 'Cópia local',
                                  icon: _snapshot?.isOnline == true
                                      ? Icons.cloud_done_rounded
                                      : Icons.cloud_off_rounded,
                                  color: _snapshot?.isOnline == true
                                      ? GranMapColors.mint
                                      : GranMapColors.coral,
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (user == null)
                        GranMapFadeSlide(
                          delay: const Duration(milliseconds: 80),
                          child: _AcademicGuest(
                            onLogin: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const LoginScreen(),
                                ),
                              );
                            },
                          ),
                        )
                      else ...[
                        _AcademicSummary(classes: classes, loading: _loading),
                        const SizedBox(height: 24),
                        const GranMapSectionTitle(title: 'Sua grade'),
                        const SizedBox(height: 10),
                        if (_loading)
                          const GranMapSurface(
                            child: Column(
                              children: [
                                LinearProgressIndicator(),
                                SizedBox(height: 12),
                                Text('Sincronizando sua agenda...'),
                              ],
                            ),
                          )
                        else if (classes.isEmpty)
                          GranMapEmptyState(
                            icon: Icons.event_busy_rounded,
                            title: 'Nenhuma aula encontrada',
                            message:
                                _snapshot?.message ??
                                'Confira seu ensalamento.',
                            action: TextButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Atualizar'),
                            ),
                          )
                        else
                          for (
                            var index = 0;
                            index < classes.length;
                            index++
                          ) ...[
                            GranMapFadeSlide(
                              delay: Duration(
                                milliseconds: 50 + (index.clamp(0, 6) * 45),
                              ),
                              child: _ClassCard(
                                item: classes[index],
                                index: index,
                                onNavigate: () => _navigate(classes[index]),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                        if (_snapshot?.cachedAt != null) ...[
                          const SizedBox(height: 10),
                          Center(
                            child: Text(
                              'Cópia local de ${_formatCache(_snapshot!.cachedAt!)}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatCache(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')} às '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }
}

class _AcademicGuest extends StatelessWidget {
  final VoidCallback onLogin;

  const _AcademicGuest({required this.onLogin});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [GranMapColors.navyRaised, Color(0xFF3A1B0A)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const GranMapIconBadge(
              icon: Icons.auto_stories_rounded,
              color: GranMapColors.mint,
              size: 56,
            ),
            const SizedBox(height: 22),
            Text(
              'Sua semana, sem surpresas.',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'Veja horários, salas e abra a rota com um toque.',
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: GranMapColors.ink,
              ),
              onPressed: onLogin,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Conectar minha conta'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AcademicSummary extends StatelessWidget {
  final List<AcademicClass> classes;
  final bool loading;

  const _AcademicSummary({required this.classes, required this.loading});

  @override
  Widget build(BuildContext context) {
    final distinctDays = classes.map((item) => item.weekday).toSet().length;
    final distinctRooms = classes.map((item) => item.roomPoiId).toSet().length;
    return Row(
      children: [
        Expanded(
          child: _SummaryMetric(
            icon: Icons.menu_book_rounded,
            value: loading ? '—' : '${classes.length}',
            label: 'aulas',
            color: GranMapColors.orange,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryMetric(
            icon: Icons.calendar_month_rounded,
            value: loading ? '—' : '$distinctDays',
            label: 'dias',
            color: GranMapColors.coral,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryMetric(
            icon: Icons.meeting_room_rounded,
            value: loading ? '—' : '$distinctRooms',
            label: 'salas',
            color: GranMapColors.mint,
          ),
        ),
      ],
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _SummaryMetric({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GranMapSurface(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
      child: Column(
        children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(height: 7),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClassCard extends StatelessWidget {
  final AcademicClass item;
  final int index;
  final VoidCallback onNavigate;

  const _ClassCard({
    required this.item,
    required this.index,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    const tones = [
      GranMapColors.orange,
      GranMapColors.coral,
      GranMapColors.mint,
      GranMapColors.sky,
    ];
    final tone = tones[index % tones.length];
    return GranMapSurface(
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: tone,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(24),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(15, 15, 9, 15),
                child: Row(
                  children: [
                    Container(
                      width: 58,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Text(
                            item.startTime,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: tone),
                          ),
                          Text(
                            item.endTime,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.subject,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${item.weekday} • ${item.professor}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 7),
                          GranMapStatusPill(
                            label: item.roomName,
                            icon: Icons.location_on_rounded,
                            color: tone,
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Traçar rota para a sala',
                      onPressed: onNavigate,
                      icon: const Icon(Icons.near_me_rounded),
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
}
