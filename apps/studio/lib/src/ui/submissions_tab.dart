import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../editor/flow_editor_controller.dart';
import '../sessions/sessions_provider.dart';
import '../sessions/submission_models.dart';

/// "Gönderimler" tab: every Player session and what it sent, newest first.
class SubmissionsTab extends ConsumerWidget {
  const SubmissionsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(sessionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: const Color(0xFFF8FAFC),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  sessionsAsync.maybeWhen(
                    data: (s) => 'GET /sessions • ${s.length} oturum '
                        '(${s.where((x) => x.status == StudioSessionStatus.completed).length} tamamlandı)',
                    orElse: () => 'GET /sessions',
                  ),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
              IconButton(
                key: const Key('clear_sessions_button'),
                tooltip: 'Gönderimleri temizle',
                iconSize: 16,
                onPressed: () async {
                  await ref.read(studioApiClientProvider).clearSessions();
                  ref.invalidate(sessionsProvider);
                },
                icon: const Icon(Icons.delete_sweep_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: sessionsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Gönderimler alınamadı: $e'),
              ),
            ),
            data: (sessions) => sessions.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Henüz kimse akışa başlamadı.\n'
                        'Player açıldığında oturum burada belirir.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: sessions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _SessionCard(session: sessions[i]),
                  ),
          ),
        ),
      ],
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session});

  final StudioSession session;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (session.status) {
      StudioSessionStatus.completed => (
          const Color(0xFFDCFCE7),
          const Color(0xFF166534)
        ),
      StudioSessionStatus.inProgress => (
          const Color(0xFFDBEAFE),
          const Color(0xFF1D4ED8)
        ),
      StudioSessionStatus.restarted => (
          const Color(0xFFF1F5F9),
          const Color(0xFF475569)
        ),
    };
    final name = session.latestAnswers['full_name'];
    final title = name is String && name.trim().isNotEmpty
        ? name
        : 'Anonim kullanıcı';

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                session.status.label,
                style: TextStyle(
                  color: fg,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${session.id} • ${_time(session.startedAt)} • '
          '${session.acceptedStepCount} adım'
          '${session.rejectedCount > 0 ? " • ${session.rejectedCount} hatalı deneme" : ""}',
          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
        ),
        children: [
          for (final e in session.events) _EventRow(event: e),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final StudioSubmissionEvent event;

  @override
  Widget build(BuildContext context) {
    final isError = event.type == StudioEventType.rejected;
    final color = switch (event.type) {
      StudioEventType.rejected => const Color(0xFFDC2626),
      StudioEventType.completed => const Color(0xFF16A34A),
      _ => const Color(0xFF334155),
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isError ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_time(event.at)}  ${event.type.label}'
            '${event.stepId != null ? " • ${event.stepId}" : ""} • v${event.flowVersion}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          if (event.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                event.error!,
                style: const TextStyle(fontSize: 11, color: Color(0xFFB91C1C)),
              ),
            ),
          if (event.answers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(event.answers),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _time(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:'
    '${t.second.toString().padLeft(2, '0')}';
