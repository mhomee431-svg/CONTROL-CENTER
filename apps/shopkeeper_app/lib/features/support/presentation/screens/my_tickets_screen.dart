import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/state/system_state.dart';
import '../../../../core/state/system_state_view.dart';
import '../../../../core/ui/lazy_list.dart';
import '../../../../core/ui/load_more.dart';
import '../../domain/support_ticket.dart';
import '../controllers/support_tickets_controller.dart';
import '../widgets/ticket_status_chip.dart';

/// The shopkeeper's support tickets, as recorded by the backend.
///
/// Every row is server truth: the reference, the subject support triages from
/// and the CURRENT status value. There is no client-side "progression" — a
/// ticket an agent resolves straight away shows Resolved, not "in progress".
class MyTicketsScreen extends ConsumerStatefulWidget {
  const MyTicketsScreen({super.key});

  @override
  ConsumerState<MyTicketsScreen> createState() => _MyTicketsScreenState();
}

class _MyTicketsScreenState extends ConsumerState<MyTicketsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(supportTicketsProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(supportTicketsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My support tickets')),
      body: SafeArea(
        child: switch (state.status) {
          SupportTicketsStatus.loading => const Center(
            child: CircularProgressIndicator(),
          ),
          SupportTicketsStatus.error => SystemStateView(
            spec: SystemStateSpec.resolve(
              state: SystemState.genericRetry,
              title: state.message ?? 'Could not load your tickets.',
              message: 'Check your connection and try again.',
            ),
            onRetry: () => ref.read(supportTicketsProvider.notifier).load(),
          ),
          SupportTicketsStatus.ready => _readyBody(context, state),
        },
      ),
    );
  }

  Widget _readyBody(BuildContext context, SupportTicketsState state) {
    if (state.isEmpty) {
      // Nothing filed yet — an honest empty state, with the one action that
      // creates the first ticket.
      return SystemStateView.empty(
        title: 'No tickets yet',
        message:
            'Reports you send from Help & support are tracked here, with the '
            'status support has set on them.',
        icon: Icons.confirmation_number_outlined,
        action: FilledButton.icon(
          key: const Key('tickets_file_one'),
          onPressed: () => context.push(Routes.reportIssue),
          icon: const Icon(Icons.bug_report_outlined),
          label: const Text('Report an issue'),
        ),
      );
    }

    final theme = Theme.of(context);
    // The list is PAGED BY THE BACKEND (`limit`/`offset`): only the tickets
    // already fetched are rendered, and the footer reveals the next page of the
    // shopkeeper's own history. A failed page keeps the rows on screen and
    // reports why, so a dropped request never empties the list.
    return RefreshIndicator(
      onRefresh: () => ref.read(supportTicketsProvider.notifier).load(),
      child: LazyListView(
        itemCount: state.tickets.length,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemBuilder: (context, index) {
          final ticket = state.tickets[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _TicketCard(
              ticket: ticket,
              onTap: () => context.push(Routes.supportTicketDetail(ticket.id)),
            ),
          );
        },
        footer: [
          if (state.hasMore)
            LoadMoreTile(
              key: const Key('tickets-load-more'),
              hidden: state.hidden,
              onTap: state.loadingMore
                  ? () {}
                  : () => ref.read(supportTicketsProvider.notifier).loadMore(),
            ),
          if (state.loadingMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (state.message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
              child: Text(
                state.message!,
                key: const Key('tickets-page-error'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One ticket in the list: reference, status and the single line support reads.
class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket, required this.onTap});

  final SupportTicket ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filed = ticket.createdAt;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      ticket.reference,
                      key: Key('ticket_reference_${ticket.id}'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TicketStatusChip(ticket: ticket),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                ticket.subject,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 6),
              Text(
                [
                  if (ticket.categoryLabel != null) ticket.categoryLabel!,
                  if (filed != null)
                    'Filed ${DateFormat('d MMM yyyy, HH:mm').format(filed.toLocal())}',
                ].join(' · '),
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
              if (ticket.hasResolution) ...[
                const SizedBox(height: 8),
                Text(
                  'Support replied: ${ticket.resolutionNotes}',
                  key: Key('ticket_resolution_${ticket.id}'),
                  style: const TextStyle(fontSize: 12, height: 1.4),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
