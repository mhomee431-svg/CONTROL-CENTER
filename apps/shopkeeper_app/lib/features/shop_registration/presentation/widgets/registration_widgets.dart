import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/document_picker_service.dart';
import '../../domain/shop_registration_state.dart';
import '../../../shops/domain/shop_models.dart';

// ── Design tokens (centralized — never hardcode in sub-widgets) ──────────────

/// Page background / section backgrounds / borders for the wizard.
class RegistrationColors {
  RegistrationColors._();

  static const Color pageBg = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF6F7F9);
  static const Color border = Color(0xFFE5E7EB);
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color progressUpcoming = Color(0xFFE5E7EB);
  static const Color success = Color(0xFF16A34A);
  static const Color successSoft = Color(0xFFEAF7EF);
}

/// Shared spacing scale (generous, mobile-first).
class RegistrationSpacing {
  RegistrationSpacing._();

  static const double screenPadding = 20;
  static const double sectionGap = 24;
  static const double fieldGap = 14;
  static const double cardRadius = 16;
  static const double fieldRadius = 12;
  static const double buttonHeight = 52;
  static const double fieldHeight = 52;
}

// ── PrimaryButton ─────────────────────────────────────────────────────────────

/// Full-width green filled CTA (reference design: rounded, ~52dp, strong
/// contrast). Disabled while a network request is active.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.loadingLabel,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final String? loadingLabel;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      height: RegistrationSpacing.buttonHeight,
      child: FilledButton(
        onPressed: (onPressed == null || loading) ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: scheme.primary.withValues(alpha: 0.45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              RegistrationSpacing.buttonHeight / 2,
            ),
          ),
          elevation: 0,
        ),
        child: loading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      loadingLabel ?? 'Please wait…',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 19),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── StepProgressIndicator ─────────────────────────────────────────────────────

/// The labeled 4-step stepper (Business Info → Location → Documents → Submit).
/// Completed = green check, current = strong green, upcoming = light gray.
/// Animated on step transitions.
class StepProgressIndicator extends StatelessWidget {
  const StepProgressIndicator({super.key, required this.step});

  /// The step the wizard is ON (welcome = step 1 highlighted, etc.).
  final RegistrationStep step;

  static const List<String> labels = [
    'Business Info',
    'Location',
    'Documents',
    'Submit',
  ];

  int get _activeIndex => switch (step) {
    RegistrationStep.welcome => 0,
    RegistrationStep.businessInfo => 0,
    RegistrationStep.location => 1,
    RegistrationStep.documents => 2,
    RegistrationStep.success => 3,
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: RegistrationSpacing.screenPadding,
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            Expanded(
              child: _StepDot(
                index: i,
                label: labels[i],
                state: i < _activeIndex
                    ? _StepState.completed
                    : (i == _activeIndex
                          ? _StepState.active
                          : _StepState.upcoming),
              ),
            ),
            if (i < labels.length - 1) _Connector(active: i < _activeIndex),
          ],
        ],
      ),
    );
  }
}

enum _StepState { completed, active, upcoming }

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.index,
    required this.label,
    required this.state,
  });

  final int index;
  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (state) {
      _StepState.completed => scheme.primary,
      _StepState.active => scheme.primary,
      _StepState.upcoming => RegistrationColors.progressUpcoming,
    };
    final labelColor = switch (state) {
      _StepState.completed => scheme.primary,
      _StepState.active => RegistrationColors.textPrimary,
      _StepState.upcoming => RegistrationColors.textSecondary,
    };
    return Semantics(
      label: 'Step ${index + 1}: $label',
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: state == _StepState.upcoming
                  ? RegistrationColors.progressUpcoming
                  : color,
              shape: BoxShape.circle,
              boxShadow: state == _StepState.active
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.35),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: state == _StepState.completed
                  ? const Icon(Icons.check, size: 17, color: Colors.white)
                  : Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: state == _StepState.active
                            ? Colors.white
                            : RegistrationColors.textSecondary,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 300),
            style: TextStyle(
              fontSize: 11,
              fontWeight: state == _StepState.active
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: labelColor,
            ),
            child: Text(label, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class _Connector extends StatelessWidget {
  const _Connector({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 2.5,
      width: 18,
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: active ? scheme.primary : RegistrationColors.progressUpcoming,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

// ── RegisterStepHeader ────────────────────────────────────────────────────────

/// Top block of every form step: back button + title + subtitle.
class RegisterStepHeader extends StatelessWidget {
  const RegisterStepHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.onBack,
    this.showBack = true,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onBack;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showBack)
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: onBack,
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back),
              style: IconButton.styleFrom(
                backgroundColor: RegistrationColors.surface,
                foregroundColor: RegistrationColors.textPrimary,
              ),
            ),
          ),
        if (showBack)
          const SizedBox(height: RegistrationSpacing.sectionGap - 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 24,
            height: 1.2,
            fontWeight: FontWeight.w800,
            color: RegistrationColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 14.5,
            height: 1.45,
            color: RegistrationColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ── SectionHeader ─────────────────────────────────────────────────────────────

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w800,
              color: RegistrationColors.textPrimary,
            ),
          ),
        ),
        // ignore: use_null_aware_elements
        if (action case final widget?) widget,
      ],
    );
  }
}

// ── FormFieldCard ─────────────────────────────────────────────────────────────

/// A wizard form field: rounded white field, leading icon, clear label and
/// placeholder, inline validation state + error message.
class FormFieldCard extends StatelessWidget {
  const FormFieldCard({
    super.key,
    required this.controller,
    required this.label,
    this.placeholder,
    this.icon,
    this.validator,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.maxLength,
    this.suffix,
    this.enabled = true,
    this.onChanged,
    this.onFieldSubmitted,
    this.focusNode,
  });

  final TextEditingController controller;
  final String label;
  final String? placeholder;
  final IconData? icon;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int? maxLength;
  final Widget? suffix;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(RegistrationSpacing.fieldRadius);
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      onChanged: onChanged,
      onFieldSubmitted: onFieldSubmitted,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      maxLength: maxLength,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      style: const TextStyle(
        fontSize: 15,
        color: RegistrationColors.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: placeholder,
        counterText: '',
        prefixIcon: icon == null
            ? null
            : Icon(icon, size: 20, color: RegistrationColors.textSecondary),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: RegistrationSpacing.fieldGap,
        ),
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: RegistrationColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: RegistrationColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.error, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
        suffixIcon: suffix,
      ),
    );
  }
}

// ── Error banner (network / location / upload failures) ───────────────────────

/// Clear production-quality error state: explanation + Retry.
class RegistrationErrorCard extends StatelessWidget {
  const RegistrationErrorCard({
    super.key,
    required this.message,
    this.onRetry,
    this.icon = Icons.cloud_off_outlined,
  });

  final String message;
  final VoidCallback? onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(RegistrationSpacing.fieldRadius),
        border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: RegistrationColors.textPrimary,
              ),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onRetry,
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Retry',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Location accuracy chip (never claims 100% GPS accuracy) ───────────────────

/// Shows the REAL accuracy radius, e.g. "Location accuracy: ±12 m".
class RegistrationAccuracyChip extends StatelessWidget {
  const RegistrationAccuracyChip({super.key, this.accuracyMeters});

  final double? accuracyMeters;

  Color get _color => switch (accuracyMeters) {
    null => Colors.blueGrey,
    final a when a <= 10 => RegistrationColors.success,
    final a when a <= 25 => Colors.orange,
    _ => Colors.deepOrange,
  };

  @override
  Widget build(BuildContext context) {
    final label = accuracyMeters == null
        ? 'Accuracy unknown'
        : 'Location accuracy: ±${accuracyMeters!.round()} m';
    final color = _color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.gps_fixed, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.requirement});

  final DocumentRequirement requirement;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                requirement.label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: RegistrationColors.textPrimary,
                ),
              ),
            ),
            if (requirement.required) ...[
              const SizedBox(width: 4),
              Text(
                '*',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: scheme.error,
                ),
              ),
            ] else ...[
              const SizedBox(width: 6),
              Text(
                'Optional',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: RegistrationColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
        if (requirement.hint case final hint?) ...[
          const SizedBox(height: 2),
          Text(
            hint,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              color: RegistrationColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

// ── DocumentUploadCard ────────────────────────────────────────────────────────

/// One verification-document card: label, hint, pick action with a
/// Camera/Gallery/Files bottom sheet (photos), upload progress, and
/// uploaded state with file name / type / replace / remove.
class DocumentUploadCard extends ConsumerStatefulWidget {
  const DocumentUploadCard({
    super.key,
    required this.slot,
    required this.onPick,
    required this.onRemove,
  });

  final DocumentSlot slot;
  final ValueChanged<PickSource> onPick;
  final VoidCallback onRemove;

  @override
  ConsumerState<DocumentUploadCard> createState() => _DocumentUploadCardState();
}

class _DocumentUploadCardState extends ConsumerState<DocumentUploadCard> {
  bool get _isImage =>
      widget.slot.requirement.mediaCategory == DocumentMediaCategory.shopImage;

  Future<void> _chooseSource() async {
    final slot = widget.slot;
    if (_isImage) {
      final source = await showModalBottomSheet<PickSource>(
        context: context,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(RegistrationSpacing.cardRadius),
          ),
        ),
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  slot.requirement.label,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Camera'),
                subtitle: const Text('Take a photo with your camera'),
                onTap: () => Navigator.of(context).pop(PickSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('Gallery'),
                subtitle: const Text('Choose an existing photo'),
                onTap: () => Navigator.of(context).pop(PickSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (source != null && mounted) widget.onPick(source);
      return;
    }
    // PDF documents always go through the file picker.
    widget.onPick(PickSource.files);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final slot = widget.slot;
    final requirement = slot.requirement;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(RegistrationSpacing.cardRadius),
        border: Border.all(
          color: slot.status == DocumentUploadStatus.error
              ? scheme.error.withValues(alpha: 0.5)
              : RegistrationColors.border,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(
                    RegistrationSpacing.fieldRadius,
                  ),
                ),
                child: Icon(
                  requirement.icon ?? Icons.upload_file_outlined,
                  size: 21,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _TitleBlock(requirement: requirement)),
            ],
          ),
          const SizedBox(height: 12),
          _SlotBody(
            slot: slot,
            isImage: _isImage,
            onPick: _chooseSource,
            onRemove: widget.onRemove,
          ),
        ],
      ),
    );
  }
}

class _SlotBody extends StatelessWidget {
  const _SlotBody({
    required this.slot,
    required this.isImage,
    required this.onPick,
    required this.onRemove,
  });

  final DocumentSlot slot;
  final bool isImage;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (slot.status) {
      DocumentUploadStatus.uploading => Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Uploading ${slot.pickedName ?? ''}…',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: RegistrationColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
      DocumentUploadStatus.uploaded => Row(
        children: [
          const Icon(
            Icons.check_circle,
            size: 18,
            color: RegistrationColors.success,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${slot.pickedName ?? 'Uploaded'} · ${isImage ? 'Photo' : 'PDF'}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: RegistrationColors.success,
              ),
            ),
          ),
          TextButton(
            onPressed: onPick,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: const Text('Replace'),
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline, size: 19),
            color: RegistrationColors.textSecondary,
          ),
        ],
      ),
      DocumentUploadStatus.error => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            slot.error ?? 'Upload failed',
            style: TextStyle(fontSize: 12.5, color: scheme.error),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.refresh, size: 17),
            label: const Text('Choose another file'),
          ),
        ],
      ),
      DocumentUploadStatus.idle =>
        slot.hasFile
            ? Row(
                children: [
                  Icon(
                    isImage ? Icons.image_outlined : Icons.picture_as_pdf,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${slot.pickedName ?? ''} · ready to upload',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: RegistrationColors.textPrimary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onPick,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Replace'),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline, size: 19),
                    color: RegistrationColors.textSecondary,
                  ),
                ],
              )
            : OutlinedButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: Text(isImage ? 'Upload photo' : 'Upload file'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: scheme.primary,
                  side: BorderSide(
                    color: scheme.primary.withValues(alpha: 0.5),
                  ),
                  minimumSize: const Size(0, 40),
                ),
              ),
    };
  }
}
