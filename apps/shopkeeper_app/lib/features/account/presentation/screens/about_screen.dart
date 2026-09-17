import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_info.dart';
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
      appBar: AppBar(title: const Text('About')),
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
              title: 'Version',
              footnote: 'Update the app from the store to get the latest fixes.',
              children: [
                SettingsTile(
                  icon: Icons.numbers_outlined,
                  title: 'App version',
                  subtitle: AppInfo.versionLabel,
                ),
                const SettingsTile(
                  icon: Icons.storefront_outlined,
                  title: 'Product',
                  subtitle: 'Passly Business, for shopkeepers',
                ),
              ],
            ),
            SettingsSection(
              title: 'What you can do here',
              children: const [
                SettingsTile(
                  icon: Icons.inventory_2_outlined,
                  title: 'Catalogue and inventory',
                  subtitle: 'Products, barcode scanning, stock and freshness',
                ),
                SettingsTile(
                  icon: Icons.local_offer_outlined,
                  title: 'Offers and pricing',
                  subtitle: 'Price lists, discounts and price history',
                ),
                SettingsTile(
                  icon: Icons.upload_file_outlined,
                  title: 'Excel imports',
                  subtitle: 'Import a whole catalogue with a preview first',
                ),
                SettingsTile(
                  icon: Icons.point_of_sale_outlined,
                  title: 'POS sync',
                  subtitle: 'Connect your billing software and pull bill items',
                ),
                SettingsTile(
                  icon: Icons.insights_outlined,
                  title: 'Reports and insights',
                  subtitle: 'Views, clicks and what customers searched for',
                ),
              ],
            ),
            SettingsSection(
              title: 'More',
              children: [
                SettingsTile(
                  icon: Icons.help_outline,
                  title: 'Help centre',
                  onTap: () => context.push(Routes.faq),
                ),
                SettingsTile(
                  icon: Icons.chat_outlined,
                  title: 'Contact support',
                  subtitle: SupportContact.email,
                  onTap: () => context.push(Routes.contactSupport),
                ),
                SettingsTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy policy',
                  onTap: () => context.push(Routes.privacy),
                ),
                SettingsTile(
                  icon: Icons.description_outlined,
                  title: 'Terms of service',
                  onTap: () => context.push(Routes.terms),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                '${AppInfo.versionLabel} - Passly',
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }
}