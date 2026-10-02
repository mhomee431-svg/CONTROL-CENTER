import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/l10n/app_text.dart';
import '../../../../core/state/system_state.dart';
import '../../../../core/state/system_state_view.dart';
import '../../../account/presentation/widgets/settings_widgets.dart';
import '../../domain/support_ticket.dart';
import '../controllers/support_tickets_controller.dart';
import '../widgets/ticket_status_chip.dart';

/// One tracked support ticket.
///
/// The status is RE-READ from the backend when the screen opens: opening a
/// ticket from a resolution notice must show what support has since done, not
/// the state the list happened to be holding. While that read is in flight the
/// cached row is shown, so the screen never flashes empty.
class TicketDetailScreen extends ConsumerStatefulWidget {
  const TicketDetailScreen({super.key, required this.ticketId});

  final int ticketId;

  @override
  ConsumerState<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends ConsumerState<TicketDetailScreen> {
  bool _refreshing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_refresh);
  }

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _error = null;
    });
    final ticket = await ref
        .read(supportTicketsProvider.notifier)
        .reloadTicket(widget.ticketId);
    if (!mounted) return;
    setState(() {
      _refreshing = false;
      _error = ticket == null
          ? 'This ticket could not be loaded. It may belong to another account.'
          : null;
    });
  }

  /// The freshest row for this id from the shared list.
  SupportTicket? get _ticket {
    for (final ticket in ref.watch(supportTicketsProvider).tickets) {
      if (ticket.id == widget.ticketId) return ticket;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ticket = _ticket;
    final error = _error;

    return Scaffold(
      appBar: AppBar(
        title: Text(ticket?.reference ?? 'Support ticket'),
        actions: [
          IconButton(
            key: const Key('ticket_detail_refresh'),
            tooltip: 'Refresh status',
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ticket != null
            ? RefreshIndicator(
                onRefresh: _refresh,
                child: _TicketBody(ticket: ticket, onRefresh: _refresh),
              )
            : error != null
            ? SystemStateView(
                spec: SystemStateSpec.resolve(
                  text: appText(context),
                  state: SystemState.genericRetry,
                  title: error,
                  message:
                      'Tickets are private to the account that filed them.',
                ),
                onRetry: _refresh,
              )
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _TicketBody extends StatelessWidget {
  const _TicketBody({required this.ticket, required this.onRefresh});

  final SupportTicket ticket;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final created = ticket.createdAt;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        ticket.reference,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    // The chip renders the backend's own status wording.
                    TicketStatusChip(ticket: ticket),
                  ],
                ),
                const SizedBox(height: 8),
                Text(ticket.subject, style: Theme.of(context).textTheme.titleSmall),
                if (ticket.shopName != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Shop: ${ticket.shopName}',
                    style: TextStyle(fontSize: 12, color: scheme.outline),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (ticket.hasResolution)
          SettingsNotice(
            icon: Icons.check_circle_outline,
            title: 'Support replied',
            message: ticket.resolutionNotes!,
          ),
        if (ticket.hasResolution) const SizedBox(height: 16),
        SettingsSection(
          title: 'Your report',
          footnote: created == null
              ? null
              : 'Filed ${DateFormat('d MMM yyyy, HH:mm').format(created.toLocal())}',
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: SelectableText(
                ticket.description,
                key: const Key('ticket_detail_description'),
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SettingsSection(
          title: 'Ticket details',
          children: [
            SettingsTile(
              icon: Icons.category_outlined,
              title: 'Category',
              subtitle: ticket.categoryLabel ?? ticket.category,
            ),
            if (ticket.priority != null)
              SettingsTile(
                icon: Icons.flag_outlined,
                title: 'Priority',
                subtitle: ticket.priority!,
              ),
            SettingsTile(
              icon: Icons.timelapse_outlined,
              title: 'Status',
              subtitle: ticket.statusLabel,
            ),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          key: const Key('ticket_detail_refresh_button'),
          onPressed: () => onRefresh(),
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh status'),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          key: const Key('ticket_detail_copy_reference'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: ticket.reference));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${ticket.reference} copied')),
            );
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copy ticket number'),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            key: const Key('ticket_detail_contact'),
            onPressed: () => context.push(Routes.contactSupport),
            child: const Text('Something else? Contact support'),
          ),
        ),
      ],
    );
  }
}

