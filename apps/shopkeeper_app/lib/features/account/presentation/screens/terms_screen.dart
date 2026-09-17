import 'package:flutter/material.dart';

import '../../../support/domain/support_models.dart';
import '../widgets/settings_widgets.dart';

/// Terms of service shown inside the app.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const String _updated = 'Last updated 16 September 2026';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms of service')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: const [
            SettingsIntro(
              icon: Icons.description_outlined,
              title: 'Terms of use',
              subtitle: _updated,
            ),
            SizedBox(height: 24),
            LegalSection(
              heading: 'Using Passly Business',
              body: 'The app is for owners and managers of registered shops. '
                  'You may use it only for the shop you are authorised to '
                  'manage, and you are responsible for keeping your sign-in '
                  'device secure.',
            ),
            LegalSection(
              heading: 'Your content is your responsibility',
              body: 'You own the products, prices, stock figures and images you '
                  'publish. Customers rely on them, so keep them accurate and '
                  'up to date, and make sure you have the right to sell the '
                  'products you list.',
            ),
            LegalSection(
              heading: 'Accurate business details',
              body: 'Shop name, address, category, hours and verification '
                  'documents must be truthful. Shops with misleading details, '
                  'or documents that do not belong to the business, can be '
                  'suspended.',
            ),
            LegalSection(
              heading: 'Acceptable use',
              body: 'Do not upload unlawful products, attempt to access another '
                  'shop\'s data, scrape the platform, or use the app to send '
                  'spam. Barcode, import and POS tools are provided so you can '
                  'manage your own catalogue.',
            ),
            LegalSection(
              heading: 'Availability',
              body: 'We work to keep the app and the sync services available, '
                  'but there will be maintenance windows and outages. Offline '
                  'work is not lost — changes are sent when the connection '
                  'returns.',
            ),
            LegalSection(
              heading: 'Subscriptions and payments',
              body: 'Paid plans are billed through the provider shown at '
                  'checkout, renew until cancelled, and are refundable only '
                  'where the law or the plan terms allow. Cancelling stops '
                  'future renewals.',
            ),
            LegalSection(
              heading: 'Suspension',
              body: 'An account that breaks these terms, or that is involved in '
                  'fraud, can be suspended or closed. If that happens you will '
                  'see the reason the next time you open the app.',
            ),
            LegalSection(
              heading: 'Changes to these terms',
              body: 'These terms may be updated as the app gains features. '
                  'Continuing to use the app after an update means you accept '
                  'the current version.',
            ),
            SettingsNotice(
              icon: Icons.mail_outline,
              title: 'Need clarification?',
              message: 'Contact ${SupportContact.email} for any question about '
                  'these terms.',
            ),
          ],
        ),
      ),
    );
  }
}