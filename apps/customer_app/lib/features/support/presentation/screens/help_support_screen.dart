import 'package:flutter/material.dart';
import 'package:hyperlocal_app/core/validation/validators.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/layout/form_keyboard.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/support_form_view_model.dart';

/// Help & Support screen — covers Master Prompt §58:
///   - FAQ (expandable tiles)
///   - Contact Support (email intent)
///   - Report Issue (category + description form)
///   - Terms & Conditions / Privacy links
class HelpSupportScreen extends ConsumerStatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  ConsumerState<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends ConsumerState<HelpSupportScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Support'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'FAQ'),
            Tab(text: 'Contact'),
            Tab(text: 'Report Issue'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [_FaqTab(), _ContactTab(), _ReportIssueTab()],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAQ TAB
// ─────────────────────────────────────────────────────────────────────────────

const List<_FaqItem> _faqs = [
  _FaqItem(
    question: 'How do I find a product near me?',
    answer:
        'Use the Search tab at the bottom and type the product name or brand (e.g. "Dove Shampoo 650ml"). '
        'The app will show nearby shops that have it in stock, along with price, distance, and availability.',
  ),
  _FaqItem(
    question: 'How accurate is the stock availability?',
    answer:
        'Availability data is updated by shop owners regularly. Each result shows a freshness timestamp '
        '(e.g. "Updated 2 hours ago"). If data is stale (older than 24 hours), the app clearly marks it. '
        'Always check the timestamp and call ahead if stock is critical.',
  ),
  _FaqItem(
    question: 'Can I order products through the app?',
    answer:
        'No. Hyperlocal is a discovery platform. The app helps you find where to buy a product nearby '
        'so you can visit the shop in person. There is no delivery or checkout feature.',
  ),
  _FaqItem(
    question: 'How do I save a product or shop?',
    answer:
        'Open any product details page and tap the bookmark icon at the top right to save it. '
        'For shops, open the shop profile and tap the heart icon. '
        'All saved items appear in the Saved & History tab.',
  ),
  _FaqItem(
    question: 'How do I get directions to a shop?',
    answer:
        'Open a shop profile or click "Directions" on any search result. The app will show a map with '
        'your current location and the shop location, with a route. You can also open in Google Maps.',
  ),
  _FaqItem(
    question: 'Why do I not see any shops near me?',
    answer:
        'The app depends on your location to show nearby shops. Make sure location permission is granted '
        'in your device settings. If the area has limited coverage, you will see a "Coming Soon" message '
        'as we are expanding our shop network.',
  ),
  _FaqItem(
    question: 'How do I manage my saved addresses?',
    answer:
        'Go to Profile → My Addresses. You can add, edit, delete, and set a default address there. '
        'Your default address is used when GPS is unavailable.',
  ),
  _FaqItem(
    question: 'How do I turn off notifications?',
    answer:
        'Go to Profile → App Settings → Notifications. You can toggle individual notification types '
        '(price drops, offers, availability) or turn them all off at once.',
  ),
  _FaqItem(
    question: 'How do I delete my account?',
    answer:
        'Go to Profile → App Settings → Delete account. This will permanently remove your account and '
        'all associated data from our servers. This action cannot be undone.',
  ),
  _FaqItem(
    question: 'Which product categories are supported?',
    answer:
        'Pharmacy & Healthcare, Beauty & Personal Care, Furniture & Home Care, Household Goods, '
        'Sports & Fitness, Books & Stationery, Automotive Parts, Hardware, Restaurants, and Transport.',
  ),
];

class _FaqItem {
  final String question;
  final String answer;
  const _FaqItem({required this.question, required this.answer});
}

class _FaqTab extends StatelessWidget {
  const _FaqTab();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: _faqs.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, indent: AppSpacing.md),
      itemBuilder: (context, index) {
        final faq = _faqs[index];
        return ExpansionTile(
          key: Key('faq_$index'),
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          title: Text(
            faq.question,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Text(
                faq.answer,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textMuted,
                  height: 1.5,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CONTACT TAB
// ─────────────────────────────────────────────────────────────────────────────

class _ContactTab extends StatelessWidget {
  const _ContactTab();

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        const SizedBox(height: AppSpacing.md),
        // Header illustration
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.support_agent,
              size: 44,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const Center(
          child: Text(
            'We are here to help!',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Center(
          child: Text(
            'Reach us through any of the channels below.\n'
            'We typically respond within 24 hours.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        // Email support
        _ContactCard(
          key: const Key('contactEmail'),
          icon: Icons.email_outlined,
          label: 'Email Support',
          value: 'support@hyperlocal.app',
          onTap: () =>
              _launch('mailto:support@hyperlocal.app?subject=App Support'),
        ),
        const SizedBox(height: AppSpacing.md),

        // The READ half of the Report Issue form, next to the way to reach a
        // human. Without an entry point here the ticket history had a route but
        // nothing pointing at it, which is the same dead end as not having one:
        // a customer could only ever file a report, never check it.
        _ContactCard(
          key: const Key('myReportsEntry'),
          icon: Icons.receipt_long_outlined,
          label: 'My Reports',
          value: 'Follow the issues you have reported',
          onTap: () => context.push('/support/issues'),
        ),
        const SizedBox(height: AppSpacing.md),

        // Legal links
        const Divider(),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'LEGAL',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _LegalTile(
          key: const Key('termsLink'),
          icon: Icons.description_outlined,
          label: 'Terms & Conditions',
          onTap: () => _launch('https://hyperlocal.app/terms'),
        ),
        _LegalTile(
          key: const Key('privacyLink'),
          icon: Icons.privacy_tip_outlined,
          label: 'Privacy Policy',
          onTap: () => _launch('https://hyperlocal.app/privacy'),
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

class _ContactCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _ContactCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          child: Icon(icon, color: AppColors.primary, size: 22),
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(value, style: const TextStyle(color: AppColors.primary)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _LegalTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _LegalTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textMuted),
      title: Text(label),
      trailing: const Icon(
        Icons.open_in_new,
        size: 18,
        color: AppColors.textMuted,
      ),
      onTap: onTap,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REPORT ISSUE TAB
// ─────────────────────────────────────────────────────────────────────────────

class _ReportIssueTab extends ConsumerStatefulWidget {
  const _ReportIssueTab();

  @override
  ConsumerState<_ReportIssueTab> createState() => _ReportIssueTabState();
}

class _ReportIssueTabState extends ConsumerState<_ReportIssueTab> {
  final _formKey = GlobalKey<FormState>();
  final _descController = TextEditingController();
  final _emailController = TextEditingController();

  /// Focus nodes in visual order: description, then optional email.
  ///
  /// One list rather than two loose nodes, because [FormKeyboard] walks this
  /// list to implement next/done and the order should be declared, not emergent.
  final _fields = <FocusNode>[FocusNode(), FocusNode()];

  @override
  void dispose() {
    _descController.dispose();
    _emailController.dispose();
    for (final node in _fields) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    // Form validation is a VIEW concern: it needs the FormState to know which
    // field is invalid, so it stays here rather than in the ViewModel.
    if (!(_formKey.currentState?.validate() ?? false)) return;

    await ref
        .read(supportFormViewModelProvider.notifier)
        .submit(
          description: _descController.text,
          contactEmail: _emailController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final form = ref.watch(supportFormViewModelProvider);

    if (form.isSubmitted) return const _SuccessView();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Report an Issue',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Found something wrong? Tell us about it and we will look into it.',
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            // Category
            const Text(
              'Issue Category',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<SupportIssueCategory>(
              key: const Key('issueCategoryDropdown'),
              initialValue: form.category,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 12,
                ),
              ),
              items: SupportIssueCategory.values
                  .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                ref
                    .read(supportFormViewModelProvider.notifier)
                    .selectCategory(v);
              },
            ),
            const SizedBox(height: AppSpacing.md),

            // Description
            const Text(
              'Description',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              key: const Key('issueDescriptionField'),
              controller: _descController,
              focusNode: _fields[0],
              maxLines: 5,
              maxLength: 500,
              // `next`, not the multiline default of `newline`. The description
              // really is multiline — Enter must still insert a line break — but
              // the IME key should say "next" so a customer who has finished
              // describing the problem can jump to the optional email instead of
              // hunting for the field with the keyboard up.
              textInputAction: FormKeyboard.actionFor(0, _fields.length),
              onEditingComplete: () =>
                  FormKeyboard.advance(nodes: _fields, from: 0),
              scrollPadding: FormKeyboard.scrollPaddingFor(context),
              decoration: const InputDecoration(
                hintText: 'Describe the issue in detail...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              validator: (v) {
                if (v == null || v.trim().length < 20) {
                  return 'Please provide at least 20 characters of detail.';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),

            // Optional email
            const Text(
              'Your email (optional)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              key: const Key('issueEmailField'),
              controller: _emailController,
              focusNode: _fields[1],
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              // Last field: `done` closes the keyboard and does NOT submit.
              // Submission stays the explicit Send press, so a stray done can
              // never post a half-written support ticket.
              textInputAction: FormKeyboard.actionFor(1, _fields.length),
              onEditingComplete: () =>
                  FormKeyboard.advance(nodes: _fields, from: 1),
              scrollPadding: FormKeyboard.scrollPaddingFor(context),
              decoration: const InputDecoration(
                hintText: 'so we can follow up with you',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                // Was an inline `RegExp(r'^[^@]+@[^@]+\.[^@]+')`. That pattern
                // accepts `a@b..c` and `@no-local.com`; the shared one does not.
                return EmailValidator.validateOptional(
                  v,
                  message: 'Enter a valid email or leave empty.',
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),

            // A failed submission must be visible and must NOT look like a
            // success. The report text is deliberately preserved above.
            if (form.errorMessage != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                key: const Key('issueSubmitError'),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: AppColors.error,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        form.errorMessage!,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            ElevatedButton.icon(
              key: const Key('submitIssueButton'),
              // Disabled while in flight, so a double tap cannot file two
              // tickets. The ViewModel also guards this; the disabled button is
              // what the customer SEES.
              onPressed: form.isSubmitting ? null : _submit,
              icon: form.isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: Text(
                form.isSubmitting ? 'Submitting...' : 'Submit Report',
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline,
                size: 48,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Report Submitted!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Thank you for letting us know.\n'
              'Our team will review your report and follow up if needed.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.xl),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to App'),
            ),
          ],
        ),
      ),
    );
  }
}
