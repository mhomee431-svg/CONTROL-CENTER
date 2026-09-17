import 'package:flutter/material.dart';

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
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
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
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Text(
              footnote!,
              style: TextStyle(fontSize: 11, color: scheme.outline),
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
          : Text(subtitle!, style: const TextStyle(fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingLabel != null)
            Text(
              trailingLabel!,
              style: TextStyle(fontSize: 12, color: scheme.primary),
            ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
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
          : Text(subtitle!, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: enabled ? onChanged : null,
    );
  }
}

/// Explanatory card for a setting that needs context — why it exists, or what is
/// deliberately not wired yet. Copy like this lives in the page (never in a
/// tooltip) so the shopkeeper can actually read it.
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
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 12,
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
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: scheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
            ],
          ),
        ),
      ],
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
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: scheme.onSurface.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}