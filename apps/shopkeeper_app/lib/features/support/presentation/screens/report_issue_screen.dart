import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_info.dart';
import '../../../account/presentation/widgets/settings_widgets.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../domain/support_models.dart';

/// Structured issue report.
///
/// Category, severity, what happened and the steps to reproduce are composed
/// into ONE report and copied to the clipboard (see `ContactSupportScreen` for
/// why there is no direct send). Asking for category and severity up front is
/// what makes a report actionable in the first reply instead of the third.
class ReportIssueScreen extends ConsumerStatefulWidget {
  const ReportIssueScreen({super.key});

  @override
  ConsumerState<ReportIssueScreen> createState() => _ReportIssueScreenState();
}

class _ReportIssueScreenState extends ConsumerState<ReportIssueScreen> {
  final TextEditingController _whatHappened = TextEditingController();
  final TextEditingController _steps = TextEditingController();
  IssueCategory _category = IssueCategory.products;
  IssueSeverity _severity = IssueSeverity.medium;
  String? _error;

  @override
  void dispose() {
    _whatHappened.dispose();
    _steps.dispose();
    super.dispose();
  }

  /// The report body: what it is, how bad it is, and the app context.
  String _composeReport() {
    final user = ref.read(authControllerProvider).user;
    final shop = ref.read(selectedShopProvider);
    final buffer = StringBuffer()
      ..writeln('${AppInfo.name} - issue report')
      ..writeln('Category: ${_category.label}')
      ..writeln('Severity: ${_severity.label}')
      ..writeln()
      ..writeln('What happened:')
      ..writeln(_whatHappened.text.trim());
    final steps = _steps.text.trim();
    if (steps.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Steps to reproduce:')
        ..writeln(steps);
    }
    buffer
      ..writeln()
      ..writeln('----')
      ..writeln('Account: ${user?.email ?? user?.phoneNumber ?? 'unknown'}')
      ..writeln('Shop: ${shop?.name ?? 'not set up yet'}')
      ..writeln('App: ${AppInfo.versionLabel}');
    return buffer.toString();
  }

  Future<void> _copyReport() async {
    if (_whatHappened.text.trim().isEmpty) {
      setState(() => _error = 'Tell us what happened');
      return;
    }
    setState(() => _error = null);
    await Clipboard.setData(ClipboardData(text: _composeReport()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Report copied - paste it into an e-mail to ${SupportContact.email}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report an issue')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const SettingsIntro(
              icon: Icons.bug_report_outlined,
              title: 'Tell us what broke',
              subtitle: 'A precise report is usually fixed in one release',
            ),
            const SizedBox(height: 16),
            _ReportForm(
              category: _category,
              onCategoryChanged: (value) => setState(() => _category = value),
              severity: _severity,
              onSeverityChanged: (value) => setState(() => _severity = value),
              whatHappened: _whatHappened,
              steps: _steps,
              error: _error,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('report_copy_button'),
                onPressed: _copyReport,
                icon: const Icon(Icons.copy),
                label: const Text('Copy report'),
              ),
            ),
            const SizedBox(height: 16),
            const SettingsNotice(
              icon: Icons.info_outline,
              title: 'Sending from the app is not connected yet',
              message: 'The report is copied with your category, severity, '
                  'account, shop and app version attached. Paste it into an '
                  'e-mail to support and it will be triaged as-is.',
            ),
          ],
        ),
      ),
    );
  }
}

/// The report fields: category, severity, description and reproduction steps.
class _ReportForm extends StatelessWidget {
  const _ReportForm({
    required this.category,
    required this.onCategoryChanged,
    required this.severity,
    required this.onSeverityChanged,
    required this.whatHappened,
    required this.steps,
    required this.error,
  });

  final IssueCategory category;
  final ValueChanged<IssueCategory> onCategoryChanged;
  final IssueSeverity severity;
  final ValueChanged<IssueSeverity> onSeverityChanged;
  final TextEditingController whatHappened;
  final TextEditingController steps;

  /// Validation message shown under the description field.
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<IssueCategory>(
              key: const Key('report_category'),
              initialValue: category,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'What is affected?',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final value in IssueCategory.values)
                  DropdownMenuItem(
                    value: value,
                    child: Text(
                      value.label,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) onCategoryChanged(value);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<IssueSeverity>(
              key: const Key('report_severity'),
              initialValue: severity,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'How much does it block you?',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final value in IssueSeverity.values)
                  DropdownMenuItem(
                    value: value,
                    child: Text(
                      value.label,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) onSeverityChanged(value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('report_what_happened'),
              controller: whatHappened,
              minLines: 4,
              maxLines: 8,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                labelText: 'What happened?',
                hintText: 'A price saved as the old value after I tapped Save',
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
                errorText: error,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('report_steps'),
              controller: steps,
              minLines: 3,
              maxLines: 6,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                labelText: 'Steps to reproduce (optional)',
                hintText: '1. Open Products\n2. Tap a product',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}