import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/form_keyboard.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/action_button.dart';
import '../../domain/phone_utils.dart';
import '../controllers/auth_controller.dart';

/// Registration screen for first-time users.
/// Combines name + phone number + OTP in a single flow.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  /// Focus nodes in visual order.
  ///
  /// Kept in one list rather than as two loose fields because [FormKeyboard]
  /// walks this list to implement next/done, and a list makes the order
  /// explicit and reviewable instead of emergent from widget order.
  final _fields = <FocusNode>[FocusNode(), FocusNode()];

  Future<void> _handleContinue() async {
    if (!_formKey.currentState!.validate()) return;

    final phone = normalizeIndianPhone(_phoneController.text.trim());
    final name = _nameController.text.trim();

    // First register the name, then proceed to OTP verification.
    final success = await ref
        .read(authControllerProvider.notifier)
        .sendOtp(phone);

    if (success && mounted) {
      context.push(
        '/otp',
        extra: {'phone': phone, 'name': name, 'isNewUser': true},
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    for (final node in _fields) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next.status == AuthStatus.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.errorMessage ?? 'Registration failed')),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SafeArea(
        // Tapping the space around a field closes the keyboard. Without it the
        // only exits are "done" and the system back gesture, so tapping what
        // looks like empty space appears to do nothing.
        child: FormKeyboard.dismissOnBackgroundTap(
          child: FormKeyboard.ordered(
            child: Form(
              key: _formKey,
              // Scrollable, and this is load-bearing rather than cosmetic.
              // scrollPadding only works if something can actually scroll: a
              // plain Column would let the keyboard push the lower fields past
              // the bottom edge with no way to reach them. The
              // ConstrainedBox/IntrinsicHeight pair keeps the form vertically
              // centred on a tall screen while still allowing a scroll on a
              // short one.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - AppSpacing.lg * 2,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Welcome! Tell us a bit about yourself.',
                              style: Theme.of(context).textTheme.titleLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            TextFormField(
                              key: const Key('nameField'),
                              controller: _nameController,
                              focusNode: _fields[0],
                              textCapitalization: TextCapitalization.words,
                              // `next`, never `submit`: this is field one of two, so
                              // submitting here would validate a form whose phone number
                              // is still empty and reject it for no visible reason.
                              textInputAction: FormKeyboard.actionFor(
                                0,
                                _fields.length,
                              ),
                              onEditingComplete: () =>
                                  FormKeyboard.advance(nodes: _fields, from: 0),
                              scrollPadding: FormKeyboard.scrollPaddingFor(
                                context,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Full Name',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? 'Please enter your name'
                                  : null,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              key: const Key('phoneField'),
                              controller: _phoneController,
                              focusNode: _fields[1],
                              keyboardType: TextInputType.phone,
                              autofillHints: const [
                                AutofillHints.telephoneNumber,
                              ],
                              // Last field: `done` closes the keyboard and does NOT submit.
                              // Submission stays the explicit Continue press, so a stray
                              // done can never send an OTP for a half-typed number.
                              textInputAction: FormKeyboard.actionFor(
                                1,
                                _fields.length,
                              ),
                              onEditingComplete: () =>
                                  FormKeyboard.advance(nodes: _fields, from: 1),
                              scrollPadding: FormKeyboard.scrollPaddingFor(
                                context,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Phone Number',
                                border: OutlineInputBorder(),
                                prefixText: '+91 ',
                                prefixIcon: Icon(Icons.phone_outlined),
                              ),
                              validator: (value) =>
                                  value != null && value.length >= 10
                                  ? null
                                  : 'Enter a valid 10-digit mobile number',
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            ActionButton(
                              onPressed: _handleContinue,
                              // A second tap must not send a second OTP to the
                              // same number: the first would be invalidated by
                              // the second, and the customer's first code stops
                              // working with no explanation.
                              disabled: authState.status == AuthStatus.loading,
                              loadingLabel: const Text('Sending code...'),
                              child: const Text('Continue'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
