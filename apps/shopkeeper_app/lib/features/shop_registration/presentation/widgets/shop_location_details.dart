import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/ui/numeric_input.dart';
import '../../domain/shop_registration_state.dart';
import '../../../shops/data/location_accuracy_config.dart';

/// Editable coordinates are independent of address text and GPS estimates.
class ShopLocationDetails extends StatefulWidget {
  const ShopLocationDetails({
    super.key,
    required this.state,
    required this.onAdjust,
    required this.onConfirmDrift,
  });

  final ShopRegistrationState state;
  final ValueChanged<LatLng> onAdjust;

  /// "Are you sure this is your shop?" → Confirm a far-moved pin.
  final VoidCallback onConfirmDrift;

  @override
  State<ShopLocationDetails> createState() => _ShopLocationDetailsState();
}

class _ShopLocationDetailsState extends State<ShopLocationDetails> {
  final _form = GlobalKey<FormState>();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();

  @override
  void initState() {
    super.initState();
    _syncPin();
  }

  @override
  void didUpdateWidget(covariant ShopLocationDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.pin != widget.state.pin) _syncPin();
  }

  void _syncPin() {
    _latitude.text = widget.state.pin?.latitude.toStringAsFixed(6) ?? '';
    _longitude.text = widget.state.pin?.longitude.toStringAsFixed(6) ?? '';
  }

  @override
  void dispose() {
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  String? _validate(String? text, double limit) {
    final value = double.tryParse(text?.trim() ?? '');
    if (value == null || !value.isFinite || value.abs() > limit) {
      return 'Enter a number from -$limit to $limit';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final busy = state.locationStatus == RegistrationLocationStatus.locating ||
        state.locationStatus ==
            RegistrationLocationStatus.requestingPermission ||
        state.locationStatus == RegistrationLocationStatus.adjustingAccuracy ||
        state.reverseGeocoding;
    final status = switch (state.locationStatus) {
      RegistrationLocationStatus.requestingPermission ||
      RegistrationLocationStatus.locating =>
        'Getting location...',
      RegistrationLocationStatus.adjustingAccuracy =>
        'Getting location... Improving accuracy',
      RegistrationLocationStatus.permissionDenied => 'Permission denied',
      RegistrationLocationStatus.permissionBlocked =>
        'Permission blocked — allow it in phone settings',
      RegistrationLocationStatus.serviceDisabled ||
      RegistrationLocationStatus.error =>
        'Unable to get location',
      RegistrationLocationStatus.ready =>
        state.pinAdjusted ? 'Manual pin' : 'Location found',
      RegistrationLocationStatus.idle => 'Choose your shop location',
    };
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(liveRegion: true, child: Text(status)),
          const SizedBox(height: 8),
          Text(
            state.pinAdjusted
                ? 'Location accuracy: unknown for the adjusted pin'
                : 'Location accuracy — '
                    '${LocationAccuracyConfig.accuracyLabel(state.accuracyMeters)}',
          ),
          if (state.pinAdjusted && state.reading != null)
            Text(
              appText(context).shopLocationDetailsOriginalGPSEstimateValue(LocationAccuracyConfig.accuracyLabel(state.reading!.accuracy)),
            ),
          const SizedBox(height: 8),
          Text(
            appText(context).shopLocationDetailsGPSAccuracyIsAnEstimate,
          ),
          if (state.needsPinDriftConfirmation) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    appText(context).shopLocationDetailsThisPinIsAboutValue((state.pinDriftMeters ?? 0).round()),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: widget.onConfirmDrift,
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(appText(context).shopLocationDetailsYesThisIsMyShop),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _latitude,
            enabled: !busy,
            decoration: InputDecoration(labelText: appText(context).commonLatitude),
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            // Manual corrections are signed decimals; the formatter keeps
            // `-`, digits and a single dot reachable.
            inputFormatters: NumericInput.signedDecimal(),
            textInputAction: TextInputAction.next,
            validator: (value) => _validate(value, 90),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _longitude,
            enabled: !busy,
            decoration: InputDecoration(labelText: appText(context).commonLongitude),
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            inputFormatters: NumericInput.signedDecimal(),
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
            validator: (value) => _validate(value, 180),
          ),
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () {
                    if (!_form.currentState!.validate()) return;
                    widget.onAdjust(
                      LatLng(
                        double.parse(_latitude.text.trim()),
                        double.parse(_longitude.text.trim()),
                      ),
                    );
                    FocusScope.of(context).unfocus();
                  },
            icon: const Icon(Icons.edit_location_alt_outlined),
            label: Text(appText(context).commonApplyManualCorrection),
          ),
        ],
      ),
    );
  }
}
