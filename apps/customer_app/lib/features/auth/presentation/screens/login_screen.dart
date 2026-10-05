import 'package:flutter/material.dart';
import 'package:hyperlocal_app/core/validation/validators.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/action_button.dart';
import '../../domain/phone_utils.dart';
import '../controllers/auth_controller.dart';

/// Passwordless customer login. The backend and native auth provider own OTP
/// delivery; this screen only collects the mobile number and starts that flow.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();

  Future<void> _handleContinue() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final phone = normalizeIndianPhone(_phoneController.text.trim());
    final sent = await ref.read(authControllerProvider.notifier).sendOtp(phone);

    if (sent && mounted) {
      context.pushReplacement(
        '/otp',
        extra: <String, dynamic>{
          'phone': phone,
          'name': null,
          'isNewUser': false,
        },
      );
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Welcome Back')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.storefront_outlined,
                      size: 72,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Welcome Back',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Enter your mobile number to continue. We will send a one-time verification code.',
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(color: AppColors.textMuted),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    TextFormField(
                      key: const Key('mobileNumberField'),
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      maxLength: 10,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      onFieldSubmitted: (_) => _handleContinue(),
                      decoration: const InputDecoration(
                        labelText: 'Mobile Number',
                        hintText: '10-digit mobile number',
                        prefixText: '+91 ',
                        prefixIcon: Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                      validator: (value) {
                        // Was an inline `RegExp(r'^[6-9]\d{9}$')` — the same rule
                        // as the shared validator, but a second copy that could
                        // drift. The copy also omitted the "required" case, so
                        // an empty field showed a format error.
                        return PhoneValidator.validate(value);
                      },
                    ),
                    if (authState.status == AuthStatus.error) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        authState.errorMessage ??
                            'Unable to send OTP. Please try again.',
                        key: const Key('loginErrorMessage'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    ActionButton(
                      key: const Key('continueButton'),
                      // `disabled` (not just `onPressed: null`) so the control
                      // reads as unavailable for assistive tech even before the
                      // first frame after the status flips.
                      disabled: authState.status == AuthStatus.loading,
                      onPressed: _handleContinue,
                      loadingLabel: const Text('Sending code...'),
                      child: const Text('Continue'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
