import 'package:flutter/material.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../support/domain/support_models.dart';
import '../widgets/settings_widgets.dart';

/// Terms of service shown inside the app.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const String _updated = 'Last updated 16 September 2026';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(appText(context).commonTermsOfService2)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            SettingsIntro(
              icon: Icons.description_outlined,
              title: appText(context).commonTermsOfUse,
              subtitle: _updated,
            ),
            SizedBox(height: 24),
            LegalSection(
              heading: 'Using Passly Business',
              body: appText(context).termsScreenTheAppIsForOwners,
            ),
            LegalSection(
              heading: 'Your content is your responsibility',
              body: appText(context).termsScreenYouOwnTheProductsPrices,
            ),
            LegalSection(
              heading: 'Accurate business details',
              body: appText(context).termsScreenShopNameAddressCategoryHours,
            ),
            LegalSection(
              heading: 'Acceptable use',
              body: appText(context).termsScreenDoNotUploadUnlawfulProducts,
            ),
            LegalSection(
              heading: 'Availability',
              body: appText(context).termsScreenWeWorkToKeepThe,
            ),
            LegalSection(
              heading: 'Subscriptions and payments',
              body: appText(context).termsScreenPaidPlansAreBilledThrough,
            ),
            LegalSection(
              heading: 'Suspension',
              body: appText(context).termsScreenAnAccountThatBreaksThese,
            ),
            LegalSection(
              heading: 'Changes to these terms',
              body: appText(context).termsScreenTheseTermsMayBeUpdated,
            ),
            SettingsNotice(
              icon: Icons.mail_outline,
              title: appText(context).commonNeedClarification,
              message: appText(context).termsScreenContactEmailForAnyQuestion(SupportContact.email),
            ),
          ],
        ),
      ),
    );
  }
}