import 'dart:async';

import 'package:flutter/material.dart';

import '../models/campus_map.dart';
import '../models/personal_data.dart';
import '../services/app_session.dart';
import '../services/app_preferences.dart';
import '../services/personal_data_service.dart';
import '../theme/granmap_theme.dart';
import '../widgets/granmap_ui.dart';
import 'academic_screen.dart';
import 'account_security_screen.dart';
import 'developer_screen.dart';
import 'edit_profile_screen.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';
import 'route_screen.dart';

class ProfileScreen extends StatefulWidget {
  final CampusMap campus;
  final Set<String> blockedEdgeIds;
  final PersonalDataService? personalDataService;
  final AppSession? session;

  const ProfileScreen({
    super.key,
    required this.campus,
    this.blockedEdgeIds = const {},
    this.personalDataService,
    this.session,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final PersonalDataService _personal;
  late final AppSession _session;
  List<String> _favorites = const [];
  List<NavigationHistoryItem> _history = const [];
  int _loadGeneration = 0;
  late String _storageScope;
  bool _clearingSession = false;
  @override
  void initState() {
    super.initState();
    _session = widget.session ?? AppSession.instance;
    _personal =
        widget.personalDataService ?? PersonalDataService(session: _session);
    _storageScope = _currentSessionScope;
    _session.addListener(_sessionChanged);
    AppPreferences.instance.addListener(_preferencesChanged);
    _load();
  }

  @override
  void dispose() {
    _session.removeListener(_sessionChanged);
    AppPreferences.instance.removeListener(_preferencesChanged);
    if (widget.personalDataService == null) _personal.dispose();
    super.dispose();
  }

  void _sessionChanged() {
    if (!mounted) return;
    final scope = _currentSessionScope;
    final changed = scope != _storageScope;
    setState(() {
      if (changed) {
        _storageScope = scope;
        _favorites = const [];
        _history = const [];
      }
    });
    if (changed) _load();
  }

  void _preferencesChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final scope = _currentSessionScope;
    await Future.wait<void>([
      _loadFavorites(generation, scope),
      _loadHistory(generation, scope),
    ]);
  }

  String get _currentSessionScope =>
      '${_session.storageScope}|${_session.token}';

  bool _isCurrentLoad(int generation, String scope) =>
      mounted && generation == _loadGeneration && scope == _currentSessionScope;

  Future<void> _loadFavorites(int generation, String scope) async {
    try {
      final cached = await _personal.loadCachedFavorites().timeout(
        const Duration(seconds: 2),
      );
      if (!_isCurrentLoad(generation, scope)) return;
      setState(() => _favorites = cached);
    } catch (_) {
      // A cópia local não impede tentar a sincronização.
    }
    if (!_isCurrentLoad(generation, scope)) return;
    try {
      final favorites = await _personal.loadFavorites().timeout(
        const Duration(seconds: 6),
      );
      if (_isCurrentLoad(generation, scope)) {
        setState(() => _favorites = favorites);
      }
    } catch (_) {
      // Os favoritos locais continuam disponíveis durante uma falha da rede.
    }
  }

  Future<void> _loadHistory(int generation, String scope) async {
    try {
      final history = await _personal.loadHistory().timeout(
        const Duration(seconds: 6),
      );
      if (_isCurrentLoad(generation, scope)) {
        setState(() => _history = history);
      }
    } catch (_) {
      // O perfil mantém o histórico já carregado.
    }
  }

  Future<void> _clearSession() async {
    if (_clearingSession) return;
    setState(() => _clearingSession = true);
    try {
      await _session.logout();
      if (!mounted) return;
      if (_session.persistenceError == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sessão removida deste aparelho.')),
        );
      }
    } finally {
      if (mounted) setState(() => _clearingSession = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final preferences = AppPreferences.instance;
    final user = session.user;
    return RefreshIndicator(
      onRefresh: () async {
        await session.refreshBackendState();
        await _load();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 108),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: user == null
                  ? _GuestProfile(
                      favorites: _favorites.length,
                      routes: _history.length,
                      persistenceError: session.persistenceError,
                      clearingSession: _clearingSession,
                      onClearSession: _clearSession,
                      onLogin: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _IdentityHeader(
                          name: user.name,
                          course: user.course,
                          semester: user.semester,
                          group: user.group,
                          reputation: user.reputation,
                          onEdit: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => EditProfileScreen(user: user),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: _Metric(
                                value: '${_history.length}',
                                label: 'Rotas',
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: _Metric(
                                value: '${_favorites.length}',
                                label: 'Favoritos',
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: _Metric(
                                value: '${user.reputation}',
                                label: 'Confiança',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 23),
                        const _SectionLabel('ACADÊMICO'),
                        const SizedBox(height: 9),
                        _SettingsGroup(
                          children: [
                            _SettingsRow(
                              icon: Icons.school_outlined,
                              title: 'Minha grade de aulas',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => AcademicScreen(
                                    campus: widget.campus,
                                    blockedEdgeIds: widget.blockedEdgeIds,
                                    session: _session,
                                  ),
                                ),
                              ),
                            ),
                            _SettingsRow(
                              icon: Icons.star_border_rounded,
                              title: 'Favoritos',
                              value: '${_favorites.length}',
                              onTap: _showFavorites,
                            ),
                            _SettingsRow(
                              icon: Icons.notifications_none_rounded,
                              title: 'Notificações',
                              value: session.unreadNotifications == 0
                                  ? null
                                  : '${session.unreadNotifications}',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const NotificationsScreen(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        const _SectionLabel('CONTA'),
                        const SizedBox(height: 9),
                        _SettingsGroup(
                          children: [
                            _SettingsRow(
                              icon: Icons.shield_outlined,
                              title: 'Conta e segurança',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const AccountSecurityScreen(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        const _SectionLabel('MAPA'),
                        const SizedBox(height: 9),
                        _SettingsGroup(
                          children: [
                            const _SettingsRow(
                              icon: Icons.map_outlined,
                              title: 'Dados offline',
                              value: 'Atualizado',
                              valueColor: GranMapColors.mint,
                            ),
                            _SettingsRow(
                              icon: Icons.download_rounded,
                              title: 'Baixar pisos adicionais',
                              onTap: () => _message(
                                'Os dois pisos da demo já estão disponíveis offline.',
                              ),
                            ),
                            _SettingsRow(
                              icon: Icons.sensors_rounded,
                              title: 'Sensores e localização',
                              value: 'Ativos no uso',
                              valueColor: GranMapColors.mint,
                              onTap: () => _message(
                                'Movimento, bússola e localização ficam ativos enquanto o GranMap está aberto e pausam ao sair do app.',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        const _SectionLabel('ACESSIBILIDADE'),
                        const SizedBox(height: 9),
                        _SettingsGroup(
                          children: [
                            _SettingsRow(
                              icon: Icons.accessible_forward_rounded,
                              title: 'Preferir rotas acessíveis',
                              trailing: Switch(
                                value: preferences.accessibleRoutes,
                                activeTrackColor: GranMapColors.orange,
                                onChanged: preferences.setAccessibleRoutes,
                              ),
                            ),
                            const _SettingsRow(
                              icon: Icons.dark_mode_outlined,
                              title: 'Tema visual',
                              value: 'Escuro',
                            ),
                            _SettingsRow(
                              icon: Icons.contrast_rounded,
                              title: 'Contraste alto',
                              trailing: Switch(
                                value: preferences.highContrast,
                                activeTrackColor: GranMapColors.orange,
                                onChanged: preferences.setHighContrast,
                              ),
                            ),
                            _SettingsRow(
                              icon: Icons.developer_mode_rounded,
                              title: 'Diagnóstico técnico',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      DeveloperScreen(campus: widget.campus),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: GranMapColors.danger,
                              side: BorderSide(
                                color: GranMapColors.danger.withValues(
                                  alpha: .22,
                                ),
                              ),
                              backgroundColor: GranMapColors.danger.withValues(
                                alpha: .055,
                              ),
                            ),
                            onPressed: session.logout,
                            icon: const Icon(Icons.logout_rounded, size: 18),
                            label: const Text('Sair da conta'),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _showFavorites() {
    final pois = _favorites
        .map(widget.campus.poiById)
        .whereType<CampusPoi>()
        .toList();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: GranMapColors.inkSoft,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Favoritos', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (pois.isEmpty)
                const Text('Nenhum local favorito ainda.')
              else
                for (final poi in pois.take(8))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.star_rounded,
                      color: GranMapColors.orange,
                    ),
                    title: Text(poi.name),
                    subtitle: Text(
                      poi.floor == 0 ? 'Térreo' : 'Piso ${poi.floor}',
                    ),
                    trailing: const Icon(
                      Icons.near_me_rounded,
                      color: GranMapColors.orange,
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      _openFavorite(poi);
                    },
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openFavorite(CampusPoi poi) async {
    unawaited(_rememberFavorite(poi));
    if (!mounted) return;
    final origin =
        widget.campus.poiById('entrada_gran') ?? widget.campus.pois.first;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RouteScreen(
          campus: widget.campus,
          origin: origin,
          destination: poi,
          blockedEdgeIds: widget.blockedEdgeIds,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _rememberFavorite(CampusPoi poi) async {
    try {
      await _personal
          .addHistory(poiId: poi.id, poiName: poi.name)
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _IdentityHeader extends StatelessWidget {
  final String name;
  final String course;
  final int semester;
  final String group;
  final int reputation;
  final VoidCallback onEdit;

  const _IdentityHeader({
    required this.name,
    required this.course,
    required this.semester,
    required this.group,
    required this.reputation,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [GranMapColors.orangeLight, GranMapColors.orange],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          alignment: Alignment.center,
          child: Text(
            _initials(name),
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: Colors.white),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 2),
              Text(
                '$course • $semesterº sem. • $group',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: GranMapColors.textMuted),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: GranMapColors.orange.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '☆ $reputation de confiança',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: GranMapColors.orange),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Editar perfil',
          onPressed: onEdit,
          icon: const Icon(
            Icons.settings_outlined,
            color: GranMapColors.textMuted,
          ),
        ),
      ],
    );
  }

  static String _initials(String name) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => word[0].toUpperCase())
        .join();
    return initials.isEmpty ? 'G' : initials;
  }
}

class _Metric extends StatelessWidget {
  final String value;
  final String label;

  const _Metric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: GranMapColors.inkSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GranMapColors.line),
      ),
      child: Column(
        children: [
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: GranMapColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

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

class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GranMapColors.inkSoft,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: const BorderSide(color: GranMapColors.line),
      ),
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              const Padding(
                padding: EdgeInsets.only(left: 52),
                child: Divider(),
              ),
          ],
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? value;
  final Color? valueColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsRow({
    required this.icon,
    required this.title,
    this.value,
    this.valueColor,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      minTileHeight: 54,
      onTap: onTap,
      leading: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: GranMapColors.navyRaised,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 16, color: GranMapColors.textMuted),
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      trailing:
          trailing ??
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (value != null) ...[
                Text(
                  value!,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: valueColor ?? GranMapColors.textMuted),
                ),
                const SizedBox(width: 7),
              ],
              if (onTap != null)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: GranMapColors.textMuted,
                ),
            ],
          ),
    );
  }
}

class _GuestProfile extends StatelessWidget {
  final int favorites;
  final int routes;
  final VoidCallback onLogin;
  final String? persistenceError;
  final bool clearingSession;
  final VoidCallback onClearSession;

  const _GuestProfile({
    required this.favorites,
    required this.routes,
    required this.onLogin,
    this.persistenceError,
    required this.clearingSession,
    required this.onClearSession,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const GranMapBrandMark(size: 66),
        const SizedBox(height: 16),
        Text(
          'Seu GranMap começa aqui',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          'Entre para sincronizar grade, favoritos e contribuições.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: GranMapColors.textMuted),
        ),
        const SizedBox(height: 18),
        if (persistenceError != null || clearingSession) ...[
          if (persistenceError != null)
            Semantics(
              liveRegion: true,
              child: Text(
                persistenceError!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: GranMapColors.coral),
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: clearingSession ? null : onClearSession,
            icon: clearingSession
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout_rounded),
            label: Text(
              clearingSession ? 'Limpando sessão...' : 'Tentar limpar sessão',
            ),
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onLogin,
            icon: const Icon(Icons.login_rounded),
            label: const Text('Entrar ou criar conta'),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _Metric(value: '$routes', label: 'Rotas locais'),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _Metric(value: '$favorites', label: 'Favoritos locais'),
            ),
          ],
        ),
      ],
    );
  }
}
