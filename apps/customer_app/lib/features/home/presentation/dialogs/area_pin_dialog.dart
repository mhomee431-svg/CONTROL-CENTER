import 'package:flutter/material.dart';

import '../../../../core/layout/form_keyboard.dart';

/// The validated 6-digit pin dialog the empty "no nearby shops" states share.
///
/// WHY ONE SHARED DIALOG
/// ---------------------
/// The home `ComingSoonScreen` used to own a private pin dialog while
/// `NearbyShopsSection` linked nowhere — two places with the same job, one of
/// them stranded. A customer typing a pin in one empty state must get the same
/// validation, the same validation error, and the same destination as in every
/// other one, or the app teaches a different rule on each screen.
///
/// Destination is the CALLER's (`/search-results-by-pin/:pin` from home): the
/// dialog only validates, never navigates, so it cannot strand the customer on
/// a route its screen does not expect.
Future<void> showAreaPinDialog(
  BuildContext context, {
  required ValueChanged<String> onPin,
}) async {
  final pinController = TextEditingController();

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      // Defined inside the builder so it can close over `dialogContext`. The IME
      // `done` key and the Check button share ONE implementation of the
      // validation: duplicating it lets the two paths drift, and a dialog that
      // accepts a pin from the keyboard but rejects the same pin from the button
      // reads as a bug to the customer.
      void checkPin() {
        final pin = pinController.text.trim();
        // Six digits or nothing leaves the dialog: the pin route resolves
        // `GET /shops/nearby?pincode=...`, and a short pin is a request the
        // backend rejects — so the error is shown HERE, before it leaves.
        if (pin.length == 6 && int.tryParse(pin) != null) {
          Navigator.of(dialogContext).pop();
          onPin(pin);
        } else {
          ScaffoldMessenger.of(dialogContext).showSnackBar(
            const SnackBar(
              content: Text('Please enter a valid 6-digit pin code'),
            ),
          );
        }
      }

      return AlertDialog(
        title: const Text('Enter Area Pin Code'),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter your 6-digit area pin code to see shops near you.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pinController,
                keyboardType: const TextInputType.numberWithOptions(),
                maxLength: 6,
                textCapitalization: TextCapitalization.none,
                // A dialog with a single field has no "next" to offer, so the key
                // performs the action the customer can already see: Check. Left
                // unset it would show a bare return key that only closes the
                // keyboard and leaves the dialog open having done nothing.
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => checkPin(),
                scrollPadding: FormKeyboard.scrollPaddingFor(context),
                decoration: const InputDecoration(
                  hintText: 'e.g. 560001',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('areaPinCheck'),
            onPressed: checkPin,
            child: const Text('Check'),
          ),
        ],
      );
    },
  );
}
