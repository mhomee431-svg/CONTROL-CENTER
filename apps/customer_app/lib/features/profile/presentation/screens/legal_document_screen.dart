import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Which legal document to display.
enum LegalDocument {
  privacy,
  terms;

  String get title => switch (this) {
    LegalDocument.privacy => 'Privacy Policy',
    LegalDocument.terms => 'Terms of Service',
  };
}

/// Read-only legal document screen (Privacy Policy / Terms of Service).
///
/// The text lives with the app so it is reachable offline and can never be
/// broken by a dead link. It deliberately describes only what the app actually
/// does today — no aspirational clauses.
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final sections = _sectionsFor(document);

    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          const Text(
            'Last updated: 1 September 2026',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final section in sections) ...[
            Text(
              section.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              section.body,
              style: const TextStyle(height: 1.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Questions about this document? Use Help & Support to reach us.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _Section {
  final String title;
  final String body;

  const _Section(this.title, this.body);
}

List<_Section> _sectionsFor(LegalDocument document) => switch (document) {
  LegalDocument.privacy => const [
    _Section(
      'What we collect',
      'Your name, mobile number and email address (if you provide one), the '
          'shop or area you search from, and the products and shops you view, '
          'save or search for.',
    ),
    _Section(
      'Location',
      'We ask for location access only when you tap a control that needs it, '
          'such as detecting your location or finding shops near you. Declining '
          'never blocks the app — you can always choose your area manually.',
    ),
    _Section(
      'How we use it',
      'To show nearby shops, compare prices and availability, keep your saved '
          'items and addresses, and deliver notifications you have switched on. '
          'We do not sell your personal data.',
    ),
    _Section(
      'Analytics',
      'Usage analytics and crash reporting are off by default. If you turn '
          'them on, only anonymous usage events are collected — never your '
          'name, phone number or address.',
    ),
    _Section(
      'Photos and documents',
      'Photos and shop documents you upload are stored privately and are only '
          'shared with the shopkeeper or administrator who needs to review '
          'them.',
    ),
    _Section(
      'Your choices',
      'You can clear your browsing history, saved items and preferences at any '
          'time from Settings, and you can delete your account entirely from '
          'your profile.',
    ),
    _Section(
      'Data retention',
      'Clearing history removes data from this device immediately. Deleting '
          'your account removes your profile and synced data from our servers.',
    ),
  ],
  LegalDocument.terms => const [
    _Section(
      'Using Hyperlocal',
      'Hyperlocal helps you discover products sold by shops near you. You may '
          'use the app for personal, non-commercial purposes and must not '
          'misuse it to interfere with other users or the service.',
    ),
    _Section(
      'Product information',
      'Prices, availability and offers shown in the app come from individual '
          'shopkeepers. They can change without notice, so always confirm the '
          'price and stock with the shop before you travel or pay.',
    ),
    _Section(
      'Your account',
      'You are responsible for keeping access to your mobile number secure. '
          'One account is for one person; sharing it may lead to suspension.',
    ),
    _Section(
      'Content you submit',
      'You keep ownership of photos and listings you submit, and grant us the '
          'permission needed to display them to customers. You must only submit '
          'content you are allowed to share.',
    ),
    _Section(
      'Availability',
      'We work to keep the service reliable but cannot guarantee that it will '
          'always be available or error-free. Features may change as the '
          'service develops.',
    ),
    _Section(
      'Ending use',
      'You can stop using the app or delete your account at any time. We may '
          'suspend accounts used to share false information or to harass '
          'others.',
    ),
    _Section(
      'Limitation of liability',
      'To the extent permitted by law, Hyperlocal is not responsible for the '
          'goods or services sold by independent shopkeepers, or for any '
          'indirect loss arising from using the app.',
    ),
  ],
};
