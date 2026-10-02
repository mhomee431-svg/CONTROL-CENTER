import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/router/route_names.dart';
import '../../domain/support_models.dart';

/// Help & support hub: the ways to reach the team, plus the most-asked
/// questions.
///
/// Every action here opens a REAL screen (`Routes.faq`,
/// `Routes.contactSupport`, `Routes.reportIssue`, `Routes.myTickets`,
/// `Routes.accountSettings`). The previous inline dialogs were replaced by
/// them, so the hub and the detail screens cannot drift apart — and the
/// questions below come from [supportFaqs], the same list the help centre
/// searches.
class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  /// A taste of the help centre; the complete, searchable list is one tap away.
  static List<FaqEntry> get _previewFaqs =>
      supportFaqs.take(4).toList(growable: false);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final preview = _previewFaqs;

    return Scaffold(
      appBar: AppBar(title: Text(appText(context).commonHelpSupport2)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: _ActionCard(
                    icon: Icons.chat_outlined,
                    label: appText(context).commonContactUs,
                    onTap: () => context.push(Routes.contactSupport),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionCard(
                    icon: Icons.bug_report_outlined,
                    label: appText(context).commonReportIssue2,
                    onTap: () => context.push(Routes.reportIssue),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ActionCard(
                    icon: Icons.confirmation_number_outlined,
                    label: appText(context).commonMyTickets2,
                    onTap: () => context.push(Routes.myTickets),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionCard(
                    icon: Icons.menu_book_outlined,
                    label: appText(context).commonHelpCentre3,
                    onTap: () => context.push(Routes.faq),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              appText(context).supportScreenFrequentlyAskedQuestions,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < preview.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _FaqTile(
                      question: preview[i].question,
                      answer: preview[i].answer,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('support_view_all_faqs'),
              onPressed: () => context.push(Routes.faq),
              icon: const Icon(Icons.help_outline),
              label: Text(appText(context).commonViewAllQuestions),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appText(context).commonStillStuck,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      appText(context).supportScreenWriteToEmailOrCall(SupportContact.email, SupportContact.phone, SupportContact.hours),
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: scheme.onSurface.withValues(alpha: 0.8),
                      ),
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

/// One square shortcut on the support hub.
class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(icon, size: 32, color: scheme.primary),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One question on the hub. The answer stays collapsed so four of them fit on a
/// single screen.
class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(question, style: const TextStyle(fontSize: 14)),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            answer,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
      ],
    );
  }
}