import 'package:flutter/material.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';

/// Shared building blocks for the Account / Settings screens.
///
/// WHY SHARED: nine screens (`AccountSettingsScreen`, `SecurityScreen`,
/// `AppSettingsScreen`, `NotificationSettingsScreen`, `PrivacyScreen`,
/// `TermsScreen`, `AboutScreen`, `LogoutConfirmationScreen`, plus the Account
/// tab) render the same shapes — a titled card of tiles, a switch row, an
/// explanatory notice. Declaring them once means every settings surface has
/// identical spacing, radii and tap targets, which is exactly the kind of thing
/// that drifts when each screen rolls its own `ListTile`.

/// A titled group of setting rows.
///
/// Renders the section label above a single clipped [Card] so consecutive
/// tiles share one surface (the pattern used by the Account tab).
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.footnote,
  });

  final String title;
  final List<Widget> children;

  /// Optional helper text under the card (e.g. "Syncing is not available yet").
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.xs,
            AppSpacing.xl,
            AppSpacing.xs,
            AppSpacing.sm,
          ),
          child: Text(
            title.toUpperCase(),
            style: AppTypography.caption.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: scheme.outline,
            ),
          ),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                children[i],
              ],
            ],
          ),
        ),
        if (footnote != null)
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.xs,
              AppSpacing.xs,
              AppSpacing.xs,
              0,
            ),
            child: Text(
              footnote!,
              style: AppTypography.caption,
            ),
          ),
      ],
    );
  }
}

/// One navigable setting row.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailingLabel,
    this.isDestructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  /// Small status word shown before the chevron (e.g. `System`, `Off`).
  final String? trailingLabel;

  /// Paints the row in the error colour (used by *Log out*).
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isDestructive ? scheme.error : null;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(
          color: color,
          fontWeight: isDestructive ? FontWeight.w600 : null,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: AppTypography.bodySmall),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingLabel != null)
            Text(
              trailingLabel!,
              style: TextStyle(
                fontSize: 12,
                color: scheme.primary,
              ),
            ),
          if (onTap != null) ...[
            const SizedBox(width: AppSpacing.xs),
            const Icon(Icons.chevron_right),
          ],
        ],
      ),
      onTap: onTap,
    );
  }
}

/// One boolean setting row.
class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;

  /// `null` when the row is locked (see [enabled]).
  final ValueChanged<bool>? onChanged;

  /// `false` dims the row and blocks tapping — used for alerts that cannot be
  /// switched off (account-safety notices).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SwitchListTile(
      secondary: Icon(icon, color: enabled ? null : scheme.outline),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          color: enabled ? null : scheme.outline,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: AppTypography.bodySmall),
      value: value,
      onChanged: enabled ? onChanged : null,
    );
  }
}

/// Explanatory card for a setting that needs context — why it exists, or what
/// is deliberately not wired yet.
class SettingsNotice extends StatelessWidget {
  const SettingsNotice({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.color,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.primary;
    return Card(
      margin: EdgeInsets.zero,
      color: accent.withValues(alpha: 0.08),
      elevation: AppShadows.elevationNone,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: accent),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.labelMedium.copyWith(
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    message,
                    style: AppTypography.bodySmall.copyWith(
                      height: 1.4,
                      color: scheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Header for a secondary settings page: what the page is about, in one line.
class SettingsIntro extends StatelessWidget {
  const SettingsIntro({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: AppRadius.mdBorder,
          ),
          child: Icon(icon, color: scheme.primary),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.labelLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                subtitle,
                style: AppTypography.caption.copyWith(
                  color: scheme.outline,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Human label for a theme choice.
///
/// Shared by *App settings* and *Data & storage* so the same choice can never
/// be described two different ways. Localized here rather than in the controller
/// because it is presentation copy, not app state.
String themeModeLabel(AppLocalizations l10n, ThemeMode mode) => switch (mode) {
      ThemeMode.system => l10n.themeFollowDevice,
      ThemeMode.light => l10n.themeLight,
      ThemeMode.dark => l10n.themeDark,
    };

/// One selectable row in a single-choice settings list (theme, language).
///
/// Renders the check/empty circle both pickers share, so a "selected" state
/// looks identical everywhere instead of drifting per screen.
class SettingsChoiceTile extends StatelessWidget {
  const SettingsChoiceTile({
    super.key,
    required this.icon,
    required this.label,
    required this.description,
    required this.selected,
    required this.onSelect,
  });

  final IconData icon;
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon),
      title: Text(label, style: AppTypography.bodyLarge),
      subtitle: Text(description, style: AppTypography.bodySmall),
      trailing: Icon(
        selected ? Icons.check_circle : Icons.circle_outlined,
        color: selected ? scheme.primary : scheme.outline,
      ),
      onTap: onSelect,
    );
  }
}

/// Heading + body block for the legal documents (privacy policy, terms).
class LegalSection extends StatelessWidget {
  const LegalSection({super.key, required this.heading, required this.body});

  final String heading;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          style: AppTypography.labelLarge.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          body,
          style: AppTypography.bodyMedium.copyWith(
            height: 1.5,
            color: scheme.onSurface.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}
