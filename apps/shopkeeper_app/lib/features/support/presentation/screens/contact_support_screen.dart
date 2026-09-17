import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../account/presentation/widgets/settings_widgets.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../domain/support_models.dart';

/// Ways to reach the support team.
///
/// WHY THERE IS NO "SEND" BUTTON: the shopkeeper backend exposes no
/// support-intake endpoint, so a submit button here would either do nothing or
/// lie. The screen instead composes the request (already tagged with the account
/// and shop it belongs to), copies it to the clipboard and shows the support
/// address, so it can be sent from a mail app. That composed text is exactly
/// what an intake endpoint would receive later.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contact support')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            SettingsSection(
              title: 'Reach us',
              children: [
                ListTile(
                  leading: const Icon(Icons.mail_outline),
                  title: const Text('E-mail', style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    SupportContact.email,
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: IconButton(
                    key: const Key('contact_copy_email'),
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: 'Copy e-mail address',
                    onPressed: () => _copyToClipboard(
                      SupportContact.email,
                      'E-mail address copied',
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.phone_outlined),
                  title: const Text('Phone', style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    SupportContact.phone,
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: IconButton(
                    key: const Key('contact_copy_phone'),
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: 'Copy phone number',
                    onPressed: () => _copyToClipboard(
                      SupportContact.phone,
                      'Phone number copied',
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.schedule_outlined),
                  title:
                      const Text('Support hours', style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    SupportContact.hours,
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
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
            const SettingsNotice(
              icon: Icons.info_outline,
              title: 'How this works',
              message: 'Writing from inside the app is not connected to the '
                  'support inbox yet. Fill the form in, tap "Copy request" and '
                  'paste it into an e-mail - your account and shop details are '
                  'already included, which is what support needs to answer '
                  'quickly.',
            ),
          ],
        ),
      ),
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
            const Text(
              'Write to us',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<IssueCategory>(
              key: const Key('contact_topic'),
              initialValue: topic,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'What is this about?',
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
                labelText: 'How can we help?',
                hintText: 'Describe the problem in your own words',
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
              title: const Text(
                'Include my account and shop',
                style: TextStyle(fontSize: 14),
              ),
              subtitle: const Text(
                'Saves a round-trip - support can look up the right shop',
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
                label: const Text('Copy request'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Paste the copied text into an e-mail to ${SupportContact.email}.',
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}