import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/form_keyboard.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/widgets/auth_gate_sheet.dart';
import '../../domain/models/business_profile_models.dart';
import '../controllers/transport_quote_controller.dart';

/// The request/booking entry point for a transport / travel provider
/// (Master Spec §87-§88).
///
/// Shown ONLY when the provider's capabilities include `quote_request`, which
/// is granted only where the backend contract exists (`POST /transport/quotes`).
/// The sheet collects the fields `TransportQuoteCreate` accepts — purpose,
/// pickup, destination, date, days, seats, notes — and nothing the contract
/// cannot serve. The price is quoted BACK by the provider; this form never
/// computes, guesses or displays one.
class RequestQuoteSheet extends ConsumerStatefulWidget {
  final String providerId;
  final List<TransportServiceOffering> services;

  const RequestQuoteSheet({
    super.key,
    required this.providerId,
    this.services = const [],
  });

  @override
  ConsumerState<RequestQuoteSheet> createState() => _RequestQuoteSheetState();
}

/// Trip purposes the backend's `trip_purpose` enum accepts.
const List<String> _purposes = [
  'LOCAL_TRAVEL',
  'AIRPORT',
  'FAMILY_TOUR',
  'PERSONAL_TRAVEL',
  'MARRIAGE',
  'EVENT_TRAVEL',
  'OTHER',
];

String _purposeLabel(String value) {
  final label = value.trim().toLowerCase().replaceAll('_', ' ');
  if (label.isEmpty) return 'Trip';
  return label[0].toUpperCase() + label.substring(1);
}

class _RequestQuoteSheetState extends ConsumerState<RequestQuoteSheet> {
  final _formKey = GlobalKey<FormState>();
  final _pickupController = TextEditingController();
  final _destinationController = TextEditingController();
  final _notesController = TextEditingController();

  /// Focus nodes for the three IME text fields, in visual order: pickup,
  /// destination, notes.
  ///
  /// The dropdown, the date field and the steppers are deliberately NOT in this
  /// list. They are not text entry, so they have no IME action to advance from;
  /// including them would make `next` walk into a date picker.
  final _fields = <FocusNode>[FocusNode(), FocusNode(), FocusNode()];

  String _purpose = 'LOCAL_TRAVEL';
  DateTime _tripDate = DateTime.now().add(const Duration(days: 1));
  int _tripDays = 1;
  int _passengers = 1;

  @override
  void dispose() {
    _pickupController.dispose();
    _destinationController.dispose();
    _notesController.dispose();
    for (final node in _fields) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _tripDate.isBefore(now) ? now : _tripDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _tripDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // A request books nothing and charges nothing, but it DOES identify the
    // customer to the provider — so it stays behind the sign-in gate, like a
    // call or a direction.
    final allowed = await requireAuthentication(
      context,
      ref,
      actionLabel: 'request a quote from this provider',
    );
    if (!allowed || !mounted) return;

    await ref
        .read(transportQuoteViewModelProvider.notifier)
        .submit(
          providerId: widget.providerId,
          tripPurpose: _purpose,
          pickupAddress: _pickupController.text,
          destinationAddress: _destinationController.text,
          tripDate: _tripDate,
          tripDays: _tripDays,
          passengerCount: _passengers,
          notes: _notesController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final quote = ref.watch(transportQuoteViewModelProvider);
    final submitting = quote.isSubmitting;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: FormKeyboard.dismissOnBackgroundTap(
        child: FormKeyboard.ordered(
          child: SingleChildScrollView(
            child: quote.isSubmitted
                ? _QuoteSuccess(receipt: quote.receipt!)
                : Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Request a quote',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'The provider replies with a price. Nothing is booked '
                          'or charged here.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _PurposeField(
                          purpose: _purpose,
                          onChanged: (value) =>
                              setState(() => _purpose = value ?? _purpose),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _AddressField(
                          controller: _pickupController,
                          focusNode: _fields[0],
                          index: 0,
                          total: _fields.length,
                          nodes: _fields,
                          label: 'Pickup',
                          hint: 'Where should the trip start?',
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _AddressField(
                          controller: _destinationController,
                          focusNode: _fields[1],
                          index: 1,
                          total: _fields.length,
                          nodes: _fields,
                          label: 'Destination',
                          hint: 'Where are you going?',
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: _DateField(
                                tripDate: _tripDate,
                                onTap: _pickDate,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: _CounterField(
                                label: 'Days',
                                value: _tripDays,
                                min: 1,
                                onChanged: (value) =>
                                    setState(() => _tripDays = value),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: _CounterField(
                                label: 'Seats',
                                value: _passengers,
                                min: 1,
                                onChanged: (value) =>
                                    setState(() => _passengers = value),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextFormField(
                          controller: _notesController,
                          focusNode: _fields[2],
                          maxLines: 2,
                          // Last text field: `done` closes the keyboard and does
                          // NOT submit. A quote request has a real cost and a real
                          // consequence, so it stays behind the explicit button —
                          // a stray done must never send one.
                          textInputAction: FormKeyboard.actionFor(
                            2,
                            _fields.length,
                          ),
                          onEditingComplete: () =>
                              FormKeyboard.advance(nodes: _fields, from: 2),
                          scrollPadding: FormKeyboard.scrollPaddingFor(context),
                          decoration: const InputDecoration(
                            labelText: 'Notes (optional)',
                            hintText: 'Anything the driver should know',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        if (quote.errorMessage != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            quote.errorMessage!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.md),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: submitting ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                            ),
                            child: submitting
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Send request'),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Purpose, as the backend's enum — the labels are customer words.
class _PurposeField extends StatelessWidget {
  final String purpose;
  final ValueChanged<String?> onChanged;
  const _PurposeField({required this.purpose, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: purpose,
      decoration: const InputDecoration(
        labelText: 'Trip purpose',
        border: OutlineInputBorder(),
      ),
      items: _purposes
          .map(
            (value) => DropdownMenuItem(
              value: value,
              child: Text(_purposeLabel(value)),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}

/// A required non-empty address line.
class _AddressField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;

  /// Position of this field in the sheet's IME chain, so `next` moves to the
  /// field the customer actually sees next rather than a hard-coded index.
  final int index;
  final int total;
  final List<FocusNode> nodes;
  final FocusNode focusNode;

  const _AddressField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.index,
    required this.total,
    required this.nodes,
    required this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      // `next` on every field but the last. Never `submit`: submitting from the
      // pickup field would validate a form whose destination is still empty and
      // fail for a reason the customer cannot see.
      textInputAction: FormKeyboard.actionFor(index, total),
      onEditingComplete: () => FormKeyboard.advance(nodes: nodes, from: index),
      scrollPadding: FormKeyboard.scrollPaddingFor(context),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
      validator: (value) =>
          (value == null || value.trim().isEmpty) ? 'Required' : null,
    );
  }
}

/// The trip date, as text: a tappable field is enough, and it keeps the date
/// arithmetic out of the customer's way.
class _DateField extends StatelessWidget {
  final DateTime tripDate;
  final VoidCallback onTap;
  const _DateField({required this.tripDate, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Trip date',
          border: OutlineInputBorder(),
        ),
        child: Text(
          '${tripDate.day}/${tripDate.month}/${tripDate.year}',
          style: const TextStyle(fontSize: 15),
        ),
      ),
    );
  }
}

/// A small stepper for a bounded count (days, seats), clamped so the request
/// can never carry a value the backend would reject.
class _CounterField extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final ValueChanged<int> onChanged;
  const _CounterField({
    required this.label,
    required this.value,
    required this.min,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.remove, size: 18),
            visualDensity: VisualDensity.compact,
            // Disabled rather than hidden at the floor, so the control's
            // purpose stays obvious.
            onPressed: value <= min ? null : () => onChanged(value - 1),
          ),
          Text('$value', style: const TextStyle(fontSize: 15)),
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }
}

/// The acknowledged request.
///
/// Shown ONLY after [MutationSucceeded], and it deliberately shows the
/// reference and the status rather than a price: the amount is what the
/// provider quotes, and displaying one here would be inventing it.
class _QuoteSuccess extends StatelessWidget {
  final TransportQuoteReceipt receipt;
  const _QuoteSuccess({required this.receipt});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle, color: AppColors.secondary, size: 40),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Request sent',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Reference ${receipt.quoteId}',
          style: const TextStyle(color: AppColors.textMuted),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'The provider will contact you with a price. Nothing is booked or '
          'charged until you accept their quote.',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: AppSpacing.md),
        // The request is only half the flow: the price comes back through the
        // trips list, where it can be accepted. Without this the sheet is a dead
        // end and the customer has no way to learn what it cost.
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              GoRouter.of(context).push('/trips');
            },
            icon: const Icon(Icons.directions_car_outlined),
            label: const Text('View my trips'),
          ),
        ),
      ],
    );
  }
}
