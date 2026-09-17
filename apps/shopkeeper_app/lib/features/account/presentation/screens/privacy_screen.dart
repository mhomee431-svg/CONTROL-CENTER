import 'package:flutter/material.dart';

import '../../../support/domain/support_models.dart';
import '../widgets/settings_widgets.dart';

/// Privacy policy shown inside the app.
///
/// Scope note: this is the SHOPKEEPER-app summary (the data the business tools
/// touch), not the customer-app policy. Every statement here matches something
/// the app actually does — no aspirational clauses.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const String _updated = 'Last updated 16 September 2026';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy policy')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: const [
            SettingsIntro(
              icon: Icons.privacy_tip_outlined,
              title: 'Your data in Passly Business',
              subtitle: _updated,
            ),
            SizedBox(height: 24),
            LegalSection(
              heading: 'What we collect',
              body: 'Your account identity (name, phone number and e-mail from '
                  'your Google sign-in), your business details (shop name, '
                  'category, address, operating hours and licence documents), '
                  'your catalogue (products, stock levels and prices) and the '
                  'notifications you receive. Shop location is captured only '
                  'when you place or update your shop on the map.',
            ),
            LegalSection(
              heading: 'How we use it',
              body: 'To show your shop, products and prices to nearby '
                  'customers, to sync your stock and prices, to send you '
                  'operational alerts (low stock, POS sync results, '
                  'verification), and to keep your account secure. Analytics '
                  'are aggregated — we never sell your data.',
            ),
            LegalSection(
              heading: 'What customers can see',
              body: 'Only your public business information: shop name, '
                  'category, address, hours, contact details and the products '
                  'you publish. Stock quantities, costs, documents and your '
                  'personal contact details stay private.',
            ),
            LegalSection(
              heading: 'Who we share it with',
              body: 'Payment and billing providers when you subscribe to a '
                  'paid plan, providers you connect yourself (for example your '
                  'POS vendor), and authorities when legally required. Nothing '
                  'else is shared.',
            ),
            LegalSection(
              heading: 'Security',
              body: 'Sessions use short-lived access tokens that are revocable '
                  'from the server, and tokens are stored in the device keychain '
                  'or keystore. Logging out revokes the session and erases the '
                  'stored tokens from this device.',
            ),
            LegalSection(
              heading: 'Your choices',
              body: 'Decide which alerts you receive in Notification '
                  'preferences, keep your catalogue accurate from the Products '
                  'and Inventory screens, and contact support to correct your '
                  'account details or ask for your data to be deleted.',
            ),
            LegalSection(
              heading: 'Retention',
              body: 'Business data is kept while your shop is active. When an '
                  'account is closed, operational data is removed or anonymised '
                  'except where a record must be kept for accounting or legal '
                  'reasons.',
            ),
            SettingsNotice(
              icon: Icons.mail_outline,
              title: 'Questions about your data?',
              message: 'Write to ${SupportContact.email} and the team will '
                  'respond during ${SupportContact.hours}.',
            ),
          ],
        ),
      ),
    );
  }
}