import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/ui/app_section_header.dart';
import '../../../../core/ui/numeric_input.dart';
import '../../domain/capability_fields.dart';
import '../../domain/shop_models.dart';

/// Renders the inputs a category's capabilities allow, in HyperLocal's own
/// visual language.
///
/// Consistency is the point: the spacing, the outlined field with its leading
/// icon, the dropdown and the error styling are exactly what every other screen
/// uses. Only the SET of fields changes. That is why this is one shared widget
/// rather than each screen composing its own form — a per-screen form is how the
/// same concept ends up looking like three different things.
///
/// A capability with no field spec simply contributes nothing, so a backend
/// capability this build has no input for renders nothing rather than an
/// invented one.
class CapabilityFieldsView extends StatelessWidget {
  const CapabilityFieldsView({
    super.key,
    required this.set,
    this.fields,
    required this.values,
    required this.onChanged,
    this.title,
    this.enabled = true,
    this.errors = const <String, String>{},
  });

  /// The field list to render, when the caller already has one.
  ///
  /// This is the server-declared list, and it WINS over [set]. Deriving the
  /// fields again from the local capability table would render a different set
  /// from the one that was loaded — so a field the backend added would not
  /// appear, and one it removed would still appear. Left null only by callers
  /// that genuinely have no server answer (the offline path).
  final List<CapabilityFieldSpec>? fields;

  /// Per-field errors from the backend, shown against the input.
  ///
  /// Kept separate from client-side validation so a server refusal is never
  /// overwritten by the local validator on the next rebuild — the two answer
  /// different questions ("did you fill it in" versus "the server said no").
  final Map<String, String> errors;

  final CategoryCapabilitySet set;

  /// Current values, keyed by [CapabilityFieldSpec.key].
  final Map<String, String> values;

  /// Called with `(key, value)` on every edit.
  final void Function(String key, String value) onChanged;

  /// Optional section heading, using the shared header component.
  final String? title;

  final bool enabled;

  /// The shared form gap, taken from the app's own spacing scale rather than
  /// hardcoded — a literal here is one more number that can drift away from the
  /// rest of the app without anything failing.
  static const double _gap = AppSpacing.md;

  @override
  Widget build(BuildContext context) {
    final specs = fields ?? capabilityFieldsFor(set);
    if (specs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          AppSectionHeader(title: title!, padding: const EdgeInsets.only(bottom: 10, top: 4)),
          const SizedBox(height: _gap),
        ],
        for (var i = 0; i < specs.length; i++) ...[
          if (i > 0) const SizedBox(height: _gap),
          _field(context, specs[i]),
        ],
      ],
    );
  }

  Widget _field(BuildContext context, CapabilityFieldSpec spec) {
    final value = values[spec.key] ?? '';

    switch (spec.kind) {
      case CapabilityFieldKind.choice:
        return DropdownButtonFormField<String>(
          key: Key('capability-field-${spec.key}'),
          initialValue: spec.options.contains(value) ? value : null,
          items: [
            for (final option in spec.options)
              DropdownMenuItem(value: option, child: Text(option)),
          ],
          onChanged: enabled
              ? (v) => onChanged(spec.key, v ?? '')
              : null,
          decoration: InputDecoration(
            labelText: spec.required ? '${spec.label} *' : spec.label,
            border: const OutlineInputBorder(),
            prefixIcon: Icon(_iconFor(spec.icon)),
// `errorText` carries the SERVER's objection so it shows the instant
            // it arrives; a validator alone waits for Form.validate(), leaving a
            // shopkeeper told "no" staring at a normal-looking input.
            errorText: errors[spec.key] ?? _localErrorFor(spec, values[spec.key]),
          ),
          validator: (v) => errors[spec.key] ?? spec.errorFor(v),
        );

      case CapabilityFieldKind.multiline:
        return TextFormField(
          key: Key('capability-field-${spec.key}'),
          initialValue: value,
          enabled: enabled,
          maxLines: 3,
          maxLength: spec.maxLength,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (v) => onChanged(spec.key, v),
          decoration: InputDecoration(
            labelText: spec.required ? '${spec.label} *' : spec.label,
            hintText: spec.hint,
            border: const OutlineInputBorder(),
            prefixIcon: Icon(_iconFor(spec.icon)),
            errorText: errors[spec.key] ?? _localErrorFor(spec, values[spec.key]),
          ),
          validator: (v) => errors[spec.key] ?? spec.errorFor(v),
        );

      case CapabilityFieldKind.number:
      case CapabilityFieldKind.text:
        return TextFormField(
          key: Key('capability-field-${spec.key}'),
          initialValue: value,
          enabled: enabled,
          maxLength: spec.maxLength,
          keyboardType: spec.kind == CapabilityFieldKind.number
              ? TextInputType.number
              : TextInputType.text,
          inputFormatters: spec.kind == CapabilityFieldKind.number
              // `whole`, not `decimal`: booking lead time and similar counts
              // are whole units, and the shared formatter already blocks a
              // stray minus sign.
              ? NumericInput.whole()
              : null,
          onChanged: (v) => onChanged(spec.key, v),
          decoration: InputDecoration(
            labelText: spec.required ? '${spec.label} *' : spec.label,
            hintText: spec.hint,
            border: const OutlineInputBorder(),
            prefixIcon: Icon(_iconFor(spec.icon)),
            errorText: errors[spec.key] ?? _localErrorFor(spec, values[spec.key]),
          ),
          validator: (v) => errors[spec.key] ?? spec.errorFor(v),
        );
    }
  }

  /// Icon names live as strings in the (Flutter-free) spec layer so that layer
  /// stays unit-testable. This is the single place they become real icons.
  /// The client-side verdict for [spec], shown before the form is submitted.
///
/// ONLY the required rule qualifies. Shape rules (a phone that is too short, a
/// negative quantity) are left to the validator, which runs on submit — showing
/// them on every rebuild would have a half-typed field flashing red at the
/// person still typing into it, which reads as an accusation rather than help.
///
/// The server's error, when there is one, always takes precedence.
String? _localErrorFor(CapabilityFieldSpec spec, String? value) {
  if (!spec.required) return null;
  return (value ?? '').trim().isEmpty ? '${spec.label} is required' : null;
}

/// Icon name → Material icon, kept local so the domain stays Flutter-free.
IconData _iconFor(String name) {
    const icons = <String, IconData>{
      'wb_sunny_outlined': Icons.wb_sunny_outlined,
      'bedtime_outlined': Icons.bedtime_outlined,
      'event_busy_outlined': Icons.event_busy_outlined,
      'spa_outlined': Icons.spa_outlined,
      'schedule_outlined': Icons.schedule_outlined,
      'receipt_long_outlined': Icons.receipt_long_outlined,
      'phone_outlined': Icons.phone_outlined,
      'auto_awesome_outlined': Icons.auto_awesome_outlined,
    };
    return icons[name] ?? Icons.help_outline;
  }
}