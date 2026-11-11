import 'package:flutter/material.dart';

import '../services/app_runtime_config.dart';
import '../theme/granmap_theme.dart';
import '../widgets/granmap_ui.dart';

class AvailabilityScreen extends StatefulWidget {
  final bool maintenance;
  final VoidCallback onAvailable;

  const AvailabilityScreen({
    super.key,
    required this.maintenance,
    required this.onAvailable,
  });

  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends State<AvailabilityScreen> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final config = AppRuntimeConfig.instance;
    return Scaffold(
      body: GranMapBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: GranMapSurface(
                  padding: const EdgeInsets.all(26),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GranMapIconBadge(
                        icon: widget.maintenance
                            ? Icons.construction_rounded
                            : Icons.system_update_rounded,
                        color: widget.maintenance
                            ? GranMapColors.amber
                            : GranMapColors.orange,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        widget.maintenance
                            ? 'Manutenção rápida'
                            : 'Atualização necessária',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.maintenance
                            ? 'Estamos aplicando uma atualização rápida. Seu mapa offline continua disponível; tente novamente em alguns minutos.'
                            : 'Uma nova versão do GranMap (${config.minimumBuild}+) é necessária para continuar usando os recursos online.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge
                            ?.copyWith(color: GranMapColors.textMuted),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _loading ? null : _retry,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(
                            _loading ? 'Verificando…' : 'Verificar novamente',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _retry() async {
    setState(() => _loading = true);
    await AppRuntimeConfig.instance.refresh();
    final config = AppRuntimeConfig.instance;
    if (!config.maintenanceMode && !config.requiresUpdate) {
      widget.onAvailable();
      return;
    }
    if (mounted) setState(() => _loading = false);
  }
}
