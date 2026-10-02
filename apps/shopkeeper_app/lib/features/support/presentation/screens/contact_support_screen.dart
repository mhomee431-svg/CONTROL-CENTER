import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/router/route_names.dart';
import '../../../account/presentation/widgets/settings_widgets.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../domain/support_models.dart';
import '../controllers/support_tickets_controller.dart';

/// Ways to reach the support team.
///
/// "Write to us" now files a REAL support ticket: the message goes to the
/// backend's support queue and comes back with a reference (`HL-42`) and the
/// status support has set, so the shopkeeper has a record instead of a copied
/// paragraph. The composed e-mail text is kept as a secondary action for anyone
/// who prefers to follow up by mail — it carries the same content the ticket
/// does.
///
/// The subject line is derived server-side from the first line of the message
/// together with the topic, and the shop context is attached by the backend (it
/// re-authorizes the shop id before accepting the ticket).
class ContactSupportScreen extends ConsumerStatefulWidget {
  const ContactSupportScreen({super.key});

  @override
  ConsumerState<ContactSupportScreen> createState() =>
      _ContactSupportScreenState();
}

class _ContactSupportScreenState extends ConsumerState<ContactSupportScreen> {
  final TextEditingController _message = TextEditingController();
  IssueCategory _topic = IssueCategory.account;
  bool _includeDetails = true;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _copyToClipboard(String value, String confirmation) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(confirmation)));
  }

  /// The request body, pre-filled with the context support asks for first.
  String _composeRequest() {
    final user = ref.read(authControllerProvider).user;
    final shop = ref.read(selectedShopProvider);
    final buffer = StringBuffer()
      ..writeln('Topic: ${_topic.label}')
      ..writeln()
      ..writeln(_message.text.trim());
    if (_includeDetails) {
      buffer
        ..writeln()
        ..writeln('----')
        ..writeln('Account: ${user?.email ?? user?.phoneNumber ?? 'unknown'}')
        ..writeln('Shop: ${shop?.name ?? 'not set up yet'}');
    }
    return buffer.toString();
  }

  Future<void> _copyRequest() async {
    if (_message.text.trim().isEmpty) {
      setState(() => _error = 'Describe what you need help with');
      return;
    }
    setState(() => _error = null);
    await _copyToClipboard(
      _composeRequest(),
      'Request copied - paste it into an e-mail to ${SupportContact.email}',
    );
  }

  /// Sends the message as a support ticket.
  ///
  /// On success the form is cleared and the ticket — with the reference and
  /// status the backend assigned — is shown. On failure the message stays in
  /// the box: a shopkeeper should never have to retype a support request
  /// because a request timed out.
  Future<void> _sendRequest() async {
    if (_message.text.trim().isEmpty) {
      setState(() => _error = 'Describe what you need help with');
      return;
    }
    setState(() => _error = null);
    final ticket = await ref
        .read(supportTicketsProvider.notifier)
        .submit(
          category: _topic,
          // A free-form question carries no severity signal; MEDIUM is what the
          // backend defaults to and matches how support triages these.
          severity: IssueSeverity.medium,
          description: _message.text.trim(),
        );
    if (ticket == null || !mounted) return;
    _message.clear();
  }

  /// Returns to the form after the confirmation has been acknowledged.
  void _writeAnother() {
    ref.read(supportTicketsProvider.notifier).acknowledgeFiled();
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final support = ref.watch(supportTicketsProvider);
    final filed = support.lastFiled;

    return Scaffold(
      appBar: AppBar(title: Text(appText(context).commonContactSupport3)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            SettingsSection(
              title: appText(context).commonReachUs,
              children: [
                ListTile(
                  leading: const Icon(Icons.mail_outline),
                  title: Text(appText(context).commonEMail2, style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    SupportContact.email,
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: IconButton(
                    key: const Key('contact_copy_email'),
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: appText(context).commonCopyEMailAddress,
                    onPressed: () => _copyToClipboard(
                      SupportContact.email,
                      'E-mail address copied',
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.phone_outlined),
                  title: Text(appText(context).commonPhone2, style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    SupportContact.phone,
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: IconButton(
                    key: const Key('contact_copy_phone'),
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: appText(context).commonCopyPhoneNumber,
                    onPressed: () => _copyToClipboard(
                      SupportContact.phone,
                      'Phone number copied',
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.schedule_outlined),
                  title:
                      Text(appText(context).commonSupportHours, style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    SupportContact.hours,
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (filed != null)
              _TicketConfirmation(
                reference: filed.reference,
                statusLabel: filed.statusLabel,
                onWriteAnother: _writeAnother,
              )
            else ...[
              _ComposeCard(
                topic: _topic,
                onTopicChanged: (value) => setState(() => _topic = value),
                message: _message,
                includeDetails: _includeDetails,
                onIncludeDetailsChanged: (value) =>
                    setState(() => _includeDetails = value),
                error: _error,
                onCopyRequest: _copyRequest,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('contact_send_request'),
                  onPressed: support.submitting ? null : _sendRequest,
                  icon: support.submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(support.submitting ? 'Sending...' : 'Send to support'),
                ),
              ),
              if (support.submitError != null) ...[
                const SizedBox(height: 8),
                Text(
                  support.submitError!,
                  key: const Key('contact_submit_error'),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SettingsNotice(
                icon: Icons.info_outline,
                title: appText(context).contactSupportScreenYourMessageBecomesATracked,
                message: appText(context).contactSupportScreenSendingFilesASupportTicket,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Confirmation shown once the backend has created the ticket.
///
/// The reference and status wording are the SERVER's values, not a locally
/// invented ticket number — quoting this to support actually identifies the
/// row support sees.
class _TicketConfirmation extends StatelessWidget {
  const _TicketConfirmation({
    required this.reference,
    required this.statusLabel,
    required this.onWriteAnother,
  });

  final String reference;
  final String statusLabel;
  final VoidCallback onWriteAnother;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 56,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            appText(context).commonMessageSent,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            appText(context).contactSupportScreenYourMessageIsInThe,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reference,
                  key: const Key('contact_filed_reference'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(appText(context).contactSupportScreenStatusStatusLabel(statusLabel), style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('contact_filed_view_tickets'),
          onPressed: () => context.push(Routes.myTickets),
          icon: const Icon(Icons.confirmation_number_outlined),
          label: Text(appText(context).commonViewMySupportTickets),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('contact_filed_another'),
          onPressed: onWriteAnother,
          icon: const Icon(Icons.add),
          label: Text(appText(context).commonWriteAnotherMessage),
        ),
      ],
    );
  }
}

/// The message form: topic, body and the account-context switch.
class _ComposeCard extends StatelessWidget {
  const _ComposeCard({
    required this.topic,
    required this.onTopicChanged,
    required this.message,
    required this.includeDetails,
    required this.onIncludeDetailsChanged,
    required this.error,
    required this.onCopyRequest,
  });

  final IssueCategory topic;
  final ValueChanged<IssueCategory> onTopicChanged;
  final TextEditingController message;
  final bool includeDetails;
  final ValueChanged<bool> onIncludeDetailsChanged;

  /// Validation message shown under the body field.
  final String? error;
  final Future<void> Function() onCopyRequest;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText(context).commonWriteToUs,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<IssueCategory>(
              key: const Key('contact_topic'),
              initialValue: topic,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: appText(context).commonWhatIsThisAbout,
                border: OutlineInputBorder(),
              ),
              items: [
                for (final category in IssueCategory.values)
                  DropdownMenuItem(
                    value: category,
                    child: Text(
                      category.label,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) onTopicChanged(value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('contact_message'),
              controller: message,
              minLines: 4,
              maxLines: 8,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                labelText: appText(context).commonHowCanWeHelp,
                hintText: appText(context).contactSupportScreenDescribeTheProblemInYour,
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
                errorText: error,
              ),
            ),
            SwitchListTile(
              key: const Key('contact_include_details'),
              contentPadding: EdgeInsets.zero,
              value: includeDetails,
              onChanged: onIncludeDetailsChanged,
              title: Text(
                appText(context).contactSupportScreenIncludeMyAccountAndShop,
                style: TextStyle(fontSize: 14),
              ),
              subtitle: Text(
                appText(context).contactSupportScreenSavesARoundTripSupport,
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('contact_copy_request'),
                onPressed: () => onCopyRequest(),
                icon: const Icon(Icons.copy),
                label: Text(appText(context).commonCopyRequest),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              appText(context).contactSupportScreenPasteTheCopiedTextInto(SupportContact.email),
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}