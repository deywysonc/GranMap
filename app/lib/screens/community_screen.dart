import 'dart:async';

import 'package:flutter/material.dart';

import '../community/community_models.dart';
import '../services/app_session.dart';
import '../services/community_service.dart';
import '../theme/granmap_theme.dart';
import '../widgets/granmap_ui.dart';
import 'login_screen.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final AppSession _session = AppSession.instance;
  late final CommunityService _service;

  CommunitySnapshot? _snapshot;
  bool _loading = true;
  String? _loadError;
  String? _busyProposalId;

  @override
  void initState() {
    super.initState();
    _service = CommunityService(session: _session);
    _session.addListener(_sessionChanged);
    _reload();
  }

  @override
  void dispose() {
    _session.removeListener(_sessionChanged);
    _service.dispose();
    super.dispose();
  }

  void _sessionChanged() {
    if (mounted) _reload(showProgress: false);
  }

  Future<void> _reload({bool showProgress = true}) async {
    if (showProgress && mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final snapshot = await _service.load().timeout(
        const Duration(seconds: 8),
      );
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
        _loadError = null;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'A sincronização demorou mais que o esperado.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Não foi possível consultar as atualizações agora.';
      });
    }
  }

  Future<void> _openCreateProposal() async {
    if (!_session.isLoggedIn) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const LoginScreen()));
      if (!_session.isLoggedIn || !mounted) return;
    }

    final proposal = await showDialog<_ProposalDraft>(
      context: context,
      builder: (_) => const _ProposalDialog(),
    );
    if (proposal == null || !mounted) return;

    try {
      final before = _snapshot?.pendingOperations ?? 0;
      await _service.createProposal(
        subject: proposal.subject,
        fromRoom: proposal.fromRoom,
        toRoom: proposal.toRoom,
        reason: proposal.reason,
      );
      await _reload(showProgress: false);
      if (!mounted) return;
      final queued = (_snapshot?.pendingOperations ?? 0) > before;
      _message(
        queued
            ? 'Sem conexão: contribuição salva e pronta para sincronizar.'
            : 'Contribuição enviada para verificação.',
      );
    } catch (error) {
      if (mounted) _message(error.toString(), error: true);
    }
  }

  Future<void> _vote(RoomChangeContribution contribution, bool agrees) async {
    if (!_session.isLoggedIn) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const LoginScreen()));
      if (!_session.isLoggedIn || !mounted) return;
    }

    setState(() => _busyProposalId = contribution.id);
    try {
      final before = _snapshot?.pendingOperations ?? 0;
      await _service.vote(contribution: contribution, agrees: agrees);
      await _reload(showProgress: false);
      if (!mounted) return;
      final queued = (_snapshot?.pendingOperations ?? 0) > before;
      _message(
        queued
            ? 'Voto salvo no aparelho; será sincronizado automaticamente.'
            : 'Seu voto foi registrado.',
      );
    } catch (error) {
      if (mounted) _message(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busyProposalId = null);
    }
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final contributions =
        snapshot?.contributions ?? const <RoomChangeContribution>[];

    return RefreshIndicator(
      onRefresh: _reload,
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
                      eyebrow: '',
                      title: 'Comunidade',
                      subtitle: 'Atualizações em tempo real',
                      trailing: FilledButton.icon(
                        onPressed: _openCreateProposal,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Informar'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  GranMapFadeSlide(
                    delay: const Duration(milliseconds: 60),
                    child: _TrustCard(session: _session, snapshot: snapshot),
                  ),
                  if (_loading) ...[
                    const SizedBox(height: 18),
                    const GranMapSurface(
                      child: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          ),
                          SizedBox(width: 12),
                          Expanded(child: Text('Sincronizando atualizações…')),
                        ],
                      ),
                    ),
                  ],
                  if (!_loading && _loadError != null) ...[
                    const SizedBox(height: 18),
                    GranMapEmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Comunidade indisponível agora',
                      message:
                          '$_loadError O mapa e as rotas continuam funcionando normalmente.',
                      action: OutlinedButton.icon(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Tentar novamente'),
                      ),
                    ),
                  ],
                  if (!_loading &&
                      _loadError == null &&
                      contributions.isEmpty) ...[
                    const SizedBox(height: 18),
                    const GranMapEmptyState(
                      icon: Icons.forum_rounded,
                      title: 'Tudo tranquilo por aqui',
                      message: 'Quando uma aula mudar de sala, a comunidade pode avisar.',
                    ),
                  ],
                  for (
                    var index = 0;
                    index < contributions.length;
                    index++
                  ) ...[
                    const SizedBox(height: 12),
                    GranMapFadeSlide(
                      delay: Duration(
                        milliseconds: 80 + ((index > 5 ? 5 : index) * 45),
                      ),
                      child: _ContributionCard(
                        contribution: contributions[index],
                        loggedIn: _session.isLoggedIn,
                        busy: _busyProposalId == contributions[index].id,
                        onVote: (agrees) => _vote(contributions[index], agrees),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustCard extends StatelessWidget {
  final AppSession session;
  final CommunitySnapshot? snapshot;

  const _TrustCard({required this.session, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final offline = snapshot?.isOffline ?? !session.backendReachable;
    final pending = snapshot?.pendingOperations ?? 0;
    final failed = snapshot?.failedOperations ?? 0;
    return GranMapSurface(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          GranMapColors.violet.withValues(alpha: .13),
          GranMapColors.mint.withValues(alpha: .07),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const GranMapIconBadge(
                icon: Icons.hub_rounded,
                color: GranMapColors.violet,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rede de confiança',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'A informação oficial sempre tem prioridade.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              GranMapStatusPill(
                label: offline ? 'Modo offline' : 'Sincronizado',
                icon: offline
                    ? Icons.cloud_off_rounded
                    : Icons.cloud_done_rounded,
                color: offline ? GranMapColors.coral : GranMapColors.mint,
              ),
              if (pending > 0)
                GranMapStatusPill(
                  label: '$pending pendente${pending == 1 ? '' : 's'}',
                  icon: Icons.sync_rounded,
                  color: GranMapColors.coral,
                ),
              if (failed > 0)
                GranMapStatusPill(
                  label: '$failed precisa${failed == 1 ? '' : 'm'} de atenção',
                  icon: Icons.sync_problem_rounded,
                  color: GranMapColors.danger,
                ),
              if (session.user != null)
                GranMapStatusPill(
                  label: '${session.user!.reputation} de reputação',
                  icon: Icons.stars_rounded,
                  color: GranMapColors.violet,
                )
              else
                Text(
                  'Entre para contribuir e votar.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContributionCard extends StatelessWidget {
  final RoomChangeContribution contribution;
  final bool loggedIn;
  final bool busy;
  final ValueChanged<bool> onVote;

  const _ContributionCard({
    required this.contribution,
    required this.loggedIn,
    required this.busy,
    required this.onVote,
  });

  @override
  Widget build(BuildContext context) {
    final percentage = (contribution.confidence * 100).round();
    final tone = _statusColor(contribution.status);
    return GranMapSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 5,
            decoration: BoxDecoration(
              color: tone,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 7,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _StatusPill(status: contribution.status),
                    if (contribution.officialPriority)
                      const GranMapStatusPill(
                        icon: Icons.admin_panel_settings_rounded,
                        label: 'Revisão oficial',
                        color: GranMapColors.mint,
                      ),
                    if (contribution.pendingSync)
                      const GranMapStatusPill(
                        icon: Icons.schedule_send_rounded,
                        label: 'Aguardando envio',
                        color: GranMapColors.coral,
                      ),
                  ],
                ),
                const SizedBox(height: 13),
                Text(
                  contribution.subject,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _RoomLabel(
                          icon: Icons.logout_rounded,
                          label: contribution.fromRoomName,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          color: tone,
                          size: 20,
                        ),
                      ),
                      Expanded(
                        child: _RoomLabel(
                          icon: Icons.login_rounded,
                          label: contribution.toRoomName,
                          alignEnd: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 11),
                Text(contribution.reason),
                const SizedBox(height: 9),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: tone.withValues(alpha: .12),
                      child: Text(
                        contribution.authorName.isEmpty
                            ? '?'
                            : contribution.authorName[0].toUpperCase(),
                        style: TextStyle(
                          color: tone,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${contribution.authorName} • '
                        '${contribution.authorReputation} de reputação',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                if (contribution.moderationNote.isNotEmpty) ...[
                  const SizedBox(height: 11),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: GranMapColors.mint.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'Nota da moderação: ${contribution.moderationNote}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
                const SizedBox(height: 15),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: contribution.totalVotes == 0
                        ? 0
                        : contribution.confidence,
                    color: tone,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        contribution.totalVotes == 0
                            ? 'Aguardando os primeiros votos'
                            : '$percentage% de confiança',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                    Text(
                      '${contribution.yesVotes} sim • '
                      '${contribution.noVotes} não',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: busy || !contribution.canVote
                          ? null
                          : () => onVote(true),
                      icon: Icon(
                        contribution.myVote == true
                            ? Icons.thumb_up_rounded
                            : Icons.thumb_up_outlined,
                      ),
                      label: Text(
                        contribution.myVote == true
                            ? 'Você confirmou'
                            : 'Está correto',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy || !contribution.canVote
                          ? null
                          : () => onVote(false),
                      icon: Icon(
                        contribution.myVote == false
                            ? Icons.thumb_down_rounded
                            : Icons.thumb_down_outlined,
                      ),
                      label: Text(
                        contribution.myVote == false
                            ? 'Você contestou'
                            : 'Contestar',
                      ),
                    ),
                    if (!loggedIn)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text('O voto solicitará seu login.'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool alignEnd;

  const _RoomLabel({
    required this.icon,
    required this.label,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final ContributionStatus status;

  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    return GranMapStatusPill(
      icon: _statusIcon(status),
      label: _statusLabel(status),
      color: _statusColor(status),
    );
  }
}

Color _statusColor(ContributionStatus status) {
  switch (status) {
    case ContributionStatus.confirmed:
      return GranMapColors.mint;
    case ContributionStatus.contested:
    case ContributionStatus.rejected:
      return GranMapColors.coral;
    case ContributionStatus.unverified:
      return GranMapColors.sky;
    case ContributionStatus.voting:
      return GranMapColors.violet;
  }
}

IconData _statusIcon(ContributionStatus status) {
  switch (status) {
    case ContributionStatus.confirmed:
      return Icons.verified_rounded;
    case ContributionStatus.contested:
      return Icons.report_problem_rounded;
    case ContributionStatus.rejected:
      return Icons.block_rounded;
    case ContributionStatus.unverified:
      return Icons.help_outline_rounded;
    case ContributionStatus.voting:
      return Icons.how_to_vote_rounded;
  }
}

String _statusLabel(ContributionStatus status) {
  switch (status) {
    case ContributionStatus.unverified:
      return 'Não verificada';
    case ContributionStatus.voting:
      return 'Em votação';
    case ContributionStatus.confirmed:
      return 'Confirmada';
    case ContributionStatus.contested:
      return 'Contestada';
    case ContributionStatus.rejected:
      return 'Rejeitada';
  }
}

class _ProposalDraft {
  final String subject;
  final String fromRoom;
  final String toRoom;
  final String reason;

  const _ProposalDraft({
    required this.subject,
    required this.fromRoom,
    required this.toRoom,
    required this.reason,
  });
}

class _ProposalDialog extends StatefulWidget {
  const _ProposalDialog();

  @override
  State<_ProposalDialog> createState() => _ProposalDialogState();
}

class _ProposalDialogState extends State<_ProposalDialog> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _fromRoom = TextEditingController();
  final _toRoom = TextEditingController();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _subject.dispose();
    _fromRoom.dispose();
    _toRoom.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _ProposalDraft(
        subject: _subject.text.trim(),
        fromRoom: _fromRoom.text.trim(),
        toRoom: _toRoom.text.trim(),
        reason: _reason.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const GranMapIconBadge(
        icon: Icons.campaign_rounded,
        color: GranMapColors.violet,
        size: 54,
      ),
      title: const Text('Informar uma mudança'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Sua contribuição será verificada pela comunidade.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                _field(_subject, 'Disciplina ou atividade'),
                _field(_fromRoom, 'Sala informada anteriormente'),
                _field(_toRoom, 'Nova sala'),
                _field(_reason, 'Como você soube?', maxLines: 3, minimum: 5),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.send_rounded),
          label: const Text('Enviar'),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    int minimum = 2,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: label),
        validator: (value) => (value ?? '').trim().length < minimum
            ? 'Preencha este campo.'
            : null,
      ),
    );
  }
}
