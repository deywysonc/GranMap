import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_preferences.dart';
import '../theme/granmap_theme.dart';
import '../widgets/granmap_ui.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onCompleted;

  const OnboardingScreen({super.key, required this.onCompleted});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  static const _pages = [
    _OnboardingPage(
      icon: Icons.route_rounded,
      eyebrow: 'ENCONTRE SEU CAMINHO',
      title: 'Da entrada até sua sala',
      description: 'Pesquise qualquer ambiente, escolha uma rota e acompanhe a mudança de corredor ou piso.',
      color: GranMapColors.orange,
    ),
    _OnboardingPage(
      icon: Icons.my_location_rounded,
      eyebrow: 'LOCALIZAÇÃO HONESTA',
      title: 'Confiança antes da precisão',
      description: 'O GranMap informa quando sua posição é simulada, aproximada ou reancorada por QR. Os sensores de movimento ficam ativos enquanto o aplicativo estiver em uso.',
      color: GranMapColors.sky,
    ),
    _OnboardingPage(
      icon: Icons.offline_bolt_rounded,
      eyebrow: 'PRONTO PARA CONEXÃO RUIM',
      title: 'O mapa continua com você',
      description: 'O núcleo funciona offline e sincroniza favoritos e contribuições quando a conexão voltar.',
      color: GranMapColors.mint,
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _pages.length - 1;
    return Scaffold(
      body: GranMapBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _finish,
                  child: const Text('Pular'),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (value) => setState(() => _page = value),
                  itemBuilder: (context, index) => _pages[index],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var index = 0; index < _pages.length; index++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            width: index == _page ? 24 : 7,
                            height: 7,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: index == _page
                                  ? GranMapColors.orange
                                  : GranMapColors.line,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: last ? _finish : _next,
                        icon: Icon(
                          last
                              ? Icons.explore_rounded
                              : Icons.arrow_forward_rounded,
                        ),
                        label: Text(last ? 'Explorar o GranMap' : 'Continuar'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _next() {
    _controller.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    unawaited(AppPreferences.instance.completeOnboarding());
    widget.onCompleted();
  }
}

class _OnboardingPage extends StatelessWidget {
  final IconData icon;
  final String eyebrow;
  final String title;
  final String description;
  final Color color;

  const _OnboardingPage({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 126,
            height: 126,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .11),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: .28)),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: .12),
                  blurRadius: 42,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: Icon(icon, size: 56, color: color),
          ),
          const SizedBox(height: 38),
          Text(
            eyebrow,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: color, letterSpacing: 1.2),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 14),
          Text(
            description,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: GranMapColors.textMuted, height: 1.5),
          ),
        ],
      ),
    );
  }
}
