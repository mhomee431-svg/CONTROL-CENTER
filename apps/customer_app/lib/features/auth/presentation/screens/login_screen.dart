import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/phone_utils.dart';
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
                        final phone = value?.trim() ?? '';
                        if (!RegExp(r'^[6-9]\d{9}$').hasMatch(phone)) {
                          return 'Enter a valid 10-digit Indian mobile number';
                        }
                        return null;
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
                    ElevatedButton(
                      key: const Key('continueButton'),
                      onPressed: authState.status == AuthStatus.loading
                          ? null
                          : _handleContinue,
                      child: authState.status == AuthStatus.loading
                          ? const CircularProgressIndicator.adaptive()
                          : const Text('Continue'),
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
