import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_info.dart';
import '../../../../core/l10n/app_text.dart';
import '../../../../core/router/route_names.dart';
import '../../../support/domain/support_models.dart';
import '../widgets/settings_widgets.dart';

/// What this app is, what it can do, and where to find help.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(appText(context).commonAbout)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.storefront, color: scheme.primary),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      AppInfo.name,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppInfo.tagline,
                      style: TextStyle(fontSize: 12, color: scheme.outline),
                    ),
                  ],
                ),
              ],
            ),
            SettingsSection(
              title: appText(context).commonVersion,
              footnote: 'Update the app from the store to get the latest fixes.',
              children: [
                SettingsTile(
                  icon: Icons.numbers_outlined,
                  title: appText(context).commonAppVersion,
                  subtitle: AppInfo.versionLabel,
                ),
                SettingsTile(
                  icon: Icons.storefront_outlined,
                  title: appText(context).commonProduct,
                  subtitle: appText(context).aboutScreenPasslyBusinessForShopkeepers,
                ),
              ],
            ),
            SettingsSection(
              title: appText(context).commonWhatYouCanDoHere,
              children: [
                SettingsTile(
                  icon: Icons.inventory_2_outlined,
                  title: appText(context).commonCatalogueAndInventory,
                  subtitle: appText(context).aboutScreenProductsBarcodeScanningStockAnd,
                ),
                SettingsTile(
                  icon: Icons.local_offer_outlined,
                  title: appText(context).commonOffersAndPricing,
                  subtitle: appText(context).aboutScreenPriceListsDiscountsAndPrice,
                ),
                SettingsTile(
                  icon: Icons.upload_file_outlined,
                  title: appText(context).commonExcelImports,
                  subtitle: appText(context).aboutScreenImportAWholeCatalogueWith,
                ),
                SettingsTile(
                  icon: Icons.point_of_sale_outlined,
                  title: appText(context).commonPOSSync,
                  subtitle: appText(context).aboutScreenConnectYourBillingSoftwareAnd,
                ),
                SettingsTile(
                  icon: Icons.insights_outlined,
                  title: appText(context).commonReportsAndInsights,
                  subtitle: appText(context).aboutScreenViewsClicksAndWhatCustomers,
                ),
              ],
            ),
            SettingsSection(
              title: appText(context).commonMore,
              children: [
                SettingsTile(
                  icon: Icons.help_outline,
                  title: appText(context).commonHelpCentre,
                  onTap: () => context.push(Routes.faq),
                ),
                SettingsTile(
                  icon: Icons.chat_outlined,
                  title: appText(context).commonContactSupport,
                  subtitle: SupportContact.email,
                  onTap: () => context.push(Routes.contactSupport),
                ),
                SettingsTile(
                  icon: Icons.privacy_tip_outlined,
                  title: appText(context).commonPrivacyPolicy,
                  onTap: () => context.push(Routes.privacy),
                ),
                SettingsTile(
                  icon: Icons.description_outlined,
                  title: appText(context).commonTermsOfService,
                  onTap: () => context.push(Routes.terms),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                appText(context).aboutScreenVersionLabelPassly(AppInfo.versionLabel),
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }
}