import 'dart:async';

import 'package:flutter/material.dart';

import 'data/campus_map_repository.dart';
import 'screens/granmap_shell.dart';
import 'screens/onboarding_screen.dart';
import 'screens/availability_screen.dart';
import 'services/app_preferences.dart';
import 'services/app_diagnostics.dart';
import 'services/app_runtime_config.dart';
import 'services/app_session.dart';
import 'theme/granmap_theme.dart';
import 'widgets/granmap_ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppDiagnostics.instance.install();
  runApp(const GranMapApp());
}

class GranMapApp extends StatelessWidget {
  const GranMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppPreferences.instance,
      builder: (context, _) => MaterialApp(
        title: 'GranMap',
        debugShowCheckedModeBanner: false,
        theme: GranMapTheme.dark,
        darkTheme: AppPreferences.instance.highContrast
            ? GranMapTheme.highContrastDark
            : GranMapTheme.dark,
        themeMode: ThemeMode.dark,
        home: const GranMapBootstrap(),
      ),
    );
  }
}

class GranMapBootstrap extends StatefulWidget {
  const GranMapBootstrap({super.key});

  @override
  State<GranMapBootstrap> createState() => _GranMapBootstrapState();
}

class _GranMapBootstrapState extends State<GranMapBootstrap> {
  final CampusMapRepository _repository = CampusMapRepository();
  late Future<CampusMapSnapshot> _campusFuture;

  @override
  void initState() {
    super.initState();
    _campusFuture = _initializeApp();
  }

  Future<CampusMapSnapshot> _initializeApp() async {
    try {
      await Future.wait([
        AppPreferences.instance.initialize(),
        AppSession.instance.initialize(),
        AppRuntimeConfig.instance.initialize(),
      ]).timeout(const Duration(seconds: 8));
    } on TimeoutException {
      // O mapa interno deve abrir mesmo que um plugin ou a rede não responda.
    }
    return _repository.loadCampus().timeout(
      const Duration(seconds: 7),
      onTimeout: _repository.loadBundledCampus,
    );
  }

  void _retryInitialization() {
    setState(() => _campusFuture = _initializeApp());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CampusMapSnapshot>(
      future: _campusFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _GranMapLoading();
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            body: GranMapBackdrop(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GranMapEmptyState(
                        icon: Icons.map_outlined,
                        title: 'O mapa não pôde ser aberto',
                        message: '${snapshot.error ?? 'Tente novamente.'}',
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: _retryInitialization,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        final data = snapshot.data!;
        if (AppRuntimeConfig.instance.maintenanceMode ||
            AppRuntimeConfig.instance.requiresUpdate) {
          return AvailabilityScreen(
            maintenance: AppRuntimeConfig.instance.maintenanceMode,
            onAvailable: () => setState(() {}),
          );
        }
        if (!AppPreferences.instance.onboardingCompleted) {
          return OnboardingScreen(onCompleted: () => setState(() {}));
        }
        return GranMapShell(
          campus: data.campus,
          blockedEdgeIds: data.blockedEdgeIds,
          mapVersion: data.version,
          mapSource: data.source,
          mapUpdatedAt: data.updatedAt,
          mapWarning: data.warning,
        );
      },
    );
  }
}

class _GranMapLoading extends StatefulWidget {
  const _GranMapLoading();

  @override
  State<_GranMapLoading> createState() => _GranMapLoadingState();
}

class _GranMapLoadingState extends State<_GranMapLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GranMapBackdrop(
        child: Center(
          child: FadeTransition(
            opacity: Tween<double>(begin: .62, end: 1).animate(
              CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GranMapBrandMark(size: 72),
                SizedBox(height: 20),
                Text(
                  'GranMap',
                  style: TextStyle(
                    fontSize: 29,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                SizedBox(height: 6),
                Text('Preparando a faculdade para você'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
