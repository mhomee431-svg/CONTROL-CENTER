import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_info.dart';
import '../../../../core/l10n/app_text.dart';
import '../../../../core/router/route_names.dart';
import '../../../account/presentation/widgets/settings_widgets.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../data/support_screenshot_picker.dart';
import '../../domain/support_models.dart';
import '../../domain/support_ticket.dart';
import '../controllers/support_tickets_controller.dart';
import '../widgets/ticket_status_chip.dart';

/// Structured issue report — filed with support and TRACKED.
///
/// Category, severity, what happened and the steps to reproduce are sent to the
/// backend, which stores the report in the platform's support queue and returns
/// a ticket with a reference (`HL-42`) and the real triage status. That
/// reference is what the shopkeeper quotes when support replies, and the ticket
/// (with its current status) stays visible under *My support tickets*.
///
/// The body is composed server-side from these fields: `complaints` has one
/// description column, so the reproduction steps and the app version travel
/// inside it rather than in a parallel store.
///
/// A clipboard fallback is kept for shopkeepers who prefer e-mail — it copies
/// exactly the same content the ticket would carry.
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

  /// The prepared screenshot, or null when nothing will be attached.
  PickedScreenshot? _screenshot;

  /// True while the picker is reading, downscaling and re-encoding an image.
  bool _attaching = false;

  /// Why the last attach attempt failed; shown under the picker buttons.
  String? _attachmentError;

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
          appText(context).reportIssueScreenReportCopiedPasteItInto(SupportContact.email),
        ),
      ),
    );
  }

  /// Picks and prepares ONE screenshot for this report.
  ///
  /// Nothing is uploaded here: the image is validated, downscaled and
  /// re-encoded as WebP by the picker (see [SupportScreenshotPicker]), so the
  /// bytes that travel with the report on submit already satisfy the backend's
  /// type and size rules. A screenshot that is never sent is never stored.
  Future<void> _pickAttachment(ScreenshotSource source) async {
    if (_attaching) return;
    setState(() {
      _attaching = true;
      _attachmentError = null;
    });
    try {
      final picked = await ref
          .read(supportScreenshotPickerProvider)
          .pick(source);
      if (!mounted) return;
      setState(() {
        _attaching = false;
        if (picked != null) _screenshot = picked;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _attaching = false;
        _attachmentError = 'Could not prepare that image. Try another one.';
      });
    }
  }

  /// Files the report and keeps the ticket the backend created.
  ///
  /// On success the form is cleared and the screen switches to a confirmation
  /// carrying the server's reference and status. On failure the text stays
  /// exactly where the shopkeeper left it — losing a written bug report because
  /// the network dropped would be worse than the failure itself.
  Future<void> _submitReport() async {
    if (_whatHappened.text.trim().isEmpty) {
      setState(() => _error = 'Tell us what happened');
      return;
    }
    setState(() => _error = null);
    final ticket = await ref
        .read(supportTicketsProvider.notifier)
        .submit(
          category: _category,
          severity: _severity,
          description: _whatHappened.text.trim(),
          steps: _steps.text,
          appVersion: AppInfo.versionLabel,
          // The prepared screenshot travels with the report: the controller
          // uploads it (grant -> upload -> confirm) before filing the ticket,
          // so only a confirmed object can ever be attached.
          screenshot: _screenshot,
        );
    if (ticket == null || !mounted) return;
    _whatHappened.clear();
    _steps.clear();
    setState(() => _screenshot = null);
  }

  /// Returns to the form so another issue can be reported.
  void _fileAnother() {
    ref.read(supportTicketsProvider.notifier).acknowledgeFiled();
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final support = ref.watch(supportTicketsProvider);
    final filed = support.lastFiled;

    return Scaffold(
      appBar: AppBar(
        title: Text(appText(context).commonReportAnIssue2),
        actions: [
          IconButton(
            key: const Key('report_my_tickets'),
            tooltip: appText(context).commonMySupportTickets2,
            onPressed: () => context.push(Routes.myTickets),
            icon: const Icon(Icons.confirmation_number_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: filed != null
            ? _TicketFiled(ticket: filed, onFileAnother: _fileAnother)
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  SettingsIntro(
                    icon: Icons.bug_report_outlined,
                    title: appText(context).commonTellUsWhatBroke,
                    subtitle: appText(context).reportIssueScreenAPreciseReportIsUsually,
                  ),
                  const SizedBox(height: 16),
                  _ReportForm(
                    category: _category,
                    onCategoryChanged: (value) =>
                        setState(() => _category = value),
                    severity: _severity,
                    onSeverityChanged: (value) =>
                        setState(() => _severity = value),
                    whatHappened: _whatHappened,
                    steps: _steps,
                    error: _error,
                  ),
                  const SizedBox(height: 16),
                  _AttachmentField(
                    screenshot: _screenshot,
                    attaching: _attaching,
                    error: _attachmentError,
                    onPick: _pickAttachment,
                    onRemove: () => setState(() {
                      _screenshot = null;
                      _attachmentError = null;
                    }),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('report_submit_button'),
                      // Disabled while a screenshot is being prepared so the
                      // report can never leave without the image it shows.
                      onPressed: (support.submitting || _attaching)
                          ? null
                          : _submitReport,
                      icon: support.submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      label: Text(
                        support.submitting
                            ? 'Sending...'
                            : 'Send report to support',
                      ),
                    ),
                  ),
                  if (support.submitError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      support.submitError!,
                      key: const Key('report_submit_error'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('report_copy_button'),
                    onPressed: support.submitting ? null : _copyReport,
                    icon: const Icon(Icons.copy),
                    label: Text(appText(context).commonCopyReportInstead),
                  ),
                  const SizedBox(height: 16),
                  SettingsNotice(
                    icon: Icons.info_outline,
                    title: appText(context).reportIssueScreenEveryReportBecomesATracked,
                    message: appText(context).reportIssueScreenSendingFilesASupportTicket,
                  ),
                ],
              ),
      ),
    );
  }
}


/// Confirmation shown once the backend has created the ticket.
///
/// Everything here comes from the server response — the reference, the status
/// wording and the subject. The app does not guess a ticket number, and it does
/// not claim a status the backend has not set.
class _TicketFiled extends StatelessWidget {
  const _TicketFiled({required this.ticket, required this.onFileAnother});

  final SupportTicket ticket;
  final VoidCallback onFileAnother;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        const SizedBox(height: 8),
        Icon(
          Icons.check_circle_outline,
          size: 56,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            appText(context).commonReportSent,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            appText(context).reportIssueScreenSupportHasItInThe,
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        ticket.reference,
                        key: const Key('report_filed_reference'),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TicketStatusChip(ticket: ticket),
                  ],
                ),
                const SizedBox(height: 8),
                Text(ticket.subject, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('report_filed_view_tickets'),
          onPressed: () => context.push(Routes.myTickets),
          icon: const Icon(Icons.confirmation_number_outlined),
          label: Text(appText(context).commonViewMySupportTickets2),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('report_filed_another'),
          onPressed: onFileAnother,
          icon: const Icon(Icons.add),
          label: Text(appText(context).commonReportSomethingElse),
        ),
      ],
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
              decoration: InputDecoration(
                labelText: appText(context).commonWhatIsAffected,
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
              decoration: InputDecoration(
                labelText: appText(context).reportIssueScreenHowMuchDoesItBlock,
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
                labelText: appText(context).commonWhatHappened,
                hintText: appText(context).reportIssueScreenAPriceSavedAsThe,
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
              decoration: InputDecoration(
                labelText: appText(context).reportIssueScreenStepsToReproduceOptional,
                hintText: appText(context).reportIssueScreen1OpenProducts2Tap,
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


/// The optional screenshot field: pick an image, review it, or drop it.
///
/// The picked image arrives already validated and re-encoded (see
/// [SupportScreenshotPicker]), so the name and size shown here are exactly the
/// payload that will be uploaded with the report on submit.
class _AttachmentField extends StatelessWidget {
  const _AttachmentField({
    required this.screenshot,
    required this.attaching,
    required this.error,
    required this.onPick,
    required this.onRemove,
  });

  /// The image that will be attached, or null when none is chosen yet.
  final PickedScreenshot? screenshot;

  /// True while an image is being read, downscaled and re-encoded.
  final bool attaching;

  /// Failure message from the last pick attempt, if any.
  final String? error;

  final ValueChanged<ScreenshotSource> onPick;
  final VoidCallback onRemove;

  /// Human-readable size, so the shopkeeper sees what will be uploaded.
  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final picked = screenshot;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText(context).commonScreenshotOptional,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              appText(context).reportIssueScreenAPictureOfTheScreen,
              style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 12),
            if (attaching)
              Row(
                key: const Key('report_attachment_preparing'),
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    appText(context).commonPreparingScreenshot,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              )
            else if (picked != null)
              Row(
                children: [
                  const Icon(Icons.image_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      appText(context).reportIssueScreenFilenameValue(picked.filename, _size(picked.sizeBytes)),
                      key: const Key('report_attachment_name'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  IconButton(
                    key: const Key('report_attachment_remove'),
                    tooltip: appText(context).commonRemoveScreenshot,
                    onPressed: onRemove,
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('report_attachment_camera'),
                    onPressed: () => onPick(ScreenshotSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(appText(context).commonTakePhoto),
                  ),
                  OutlinedButton.icon(
                    key: const Key('report_attachment_gallery'),
                    onPressed: () => onPick(ScreenshotSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(appText(context).commonChooseScreenshot),
                  ),
                ],
              ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error!,
                key: const Key('report_attachment_error'),
                style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
