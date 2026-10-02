import 'package:flutter/material.dart';

import '../../../../core/l10n/app_text.dart';
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
      appBar: AppBar(title: Text(appText(context).commonPrivacyPolicy3)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            SettingsIntro(
              icon: Icons.privacy_tip_outlined,
              title: appText(context).privacyScreenYourDataInPasslyBusiness,
              subtitle: _updated,
            ),
            SizedBox(height: 24),
            LegalSection(
              heading: 'What we collect',
              body: appText(context).privacyScreenYourAccountIdentityNamePhone,
            ),
            LegalSection(
              heading: 'How we use it',
              body: appText(context).privacyScreenToShowYourShopProducts,
            ),
            LegalSection(
              heading: 'What customers can see',
              body: appText(context).privacyScreenOnlyYourPublicBusinessInformation,
            ),
            LegalSection(
              heading: 'Who we share it with',
              body: appText(context).privacyScreenPaymentAndBillingProvidersWhen,
            ),
            LegalSection(
              heading: 'Security',
              body: appText(context).privacyScreenSessionsUseShortLivedAccess,
            ),
            LegalSection(
              heading: 'Your choices',
              body: appText(context).privacyScreenDecideWhichAlertsYouReceive,
            ),
            LegalSection(
              heading: 'Retention',
              body: appText(context).privacyScreenBusinessDataIsKeptWhile,
            ),
            SettingsNotice(
              icon: Icons.mail_outline,
              title: appText(context).privacyScreenQuestionsAboutYourData,
              message: appText(context).privacyScreenWriteToEmailAndThe(SupportContact.email, SupportContact.hours),
            ),
          ],
        ),
      ),
    );
  }
}