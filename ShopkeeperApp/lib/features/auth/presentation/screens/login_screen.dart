import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../controllers/auth_controller.dart';

/// Phone entry — sends the login OTP.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phoneController = TextEditingController();
  // TEMP/DEV: hardcoded-login password field — remove with that feature.
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _phoneController.dispose();
    // TEMP/DEV: remove with the hardcoded-login feature.
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // ────────────────────────────────────────────────────────────────────
    // TEMP/DEV HARDCODED LOGIN — remove before release.
    // If a password is entered, try the local demo credentials first
    // (ID = phone field, password from EnvConfig). On success the router
    // redirect opens /dashboard automatically. Leave the password EMPTY
    // to use the normal OTP flow below (original code, untouched).
    // ────────────────────────────────────────────────────────────────────
    final password = _passwordController.text;
    if (password.isNotEmpty) {
      final ok = await ref
          .read(authControllerProvider.notifier)
          .loginWithCredentials(_phoneController.text.trim(), password);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ref.read(authControllerProvider).errorMessage ??
                'Invalid ID or password'),
          ),
        );
      }
      return;
    }

    // ORIGINAL OTP FLOW (unchanged).
    final ok = await ref
        .read(authControllerProvider.notifier)
        .sendOtp(_phoneController.text.trim());
    if (!mounted) return;
    if (ok) {
      context.push('/otp?phone=${Uri.encodeComponent(_phoneController.text.trim())}');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ref.read(authControllerProvider).errorMessage ??
              'Could not send code'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authControllerProvider.select((s) => s.isLoading));
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Welcome back',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text('Enter your business phone number to continue.'),
              // ────────────────────────────────────────────────────────────
              // TEMP/DEV HARDCODED LOGIN INFO — remove before release.
              // Shows the hardcoded demo credentials on screen so you don't
              // have to remember them.
              // ────────────────────────────────────────────────────────────
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .secondaryContainer
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .secondary
                        .withValues(alpha: 0.4),
                  ),
                ),
                child: const Text(
                  'DEV LOGIN (no OTP needed)\n'
                  'ID: 9999999999\n'
                  'Password: demo123\n\n'
                  'Dono fields bharo → "Send code" dabao.\n'
                  'Password KHALI chhoda to OTP flow chalega.',
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                decoration:
                    const InputDecoration(labelText: 'Phone number'),
                validator: (v) {
                  final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                  if (digits.length < 10) return 'Enter a valid phone number';
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
              ),
              // ────────────────────────────────────────────────────────────
              // TEMP/DEV HARDCODED LOGIN PASSWORD — remove before release.
              // Leave this EMPTY to use the normal OTP flow. Fill it to sign
              // in instantly with the hardcoded demo credentials.
              // ────────────────────────────────────────────────────────────
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password (dev only – optional)',
                  hintText: 'Leave empty for OTP login',
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: isLoading ? null : _submit,
                child: isLoading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    // TEMP/DEV: label switches based on whether the dev
                    // password field is filled (remove with the feature).
                    : ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _passwordController,
                        builder: (_, value, _) => Text(
                            value.text.isEmpty ? 'Send code' : 'Sign in'),
                      ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.push('/register'),
                child: const Text('New here? Create a business account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
