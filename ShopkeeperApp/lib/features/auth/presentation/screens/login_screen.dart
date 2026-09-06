import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../controllers/auth_controller.dart';
import '../../data/auth_repository.dart';
import '../../data/mock_auth_repository.dart';
import '../../data/phone_utils.dart';

/// Login screen with password and OTP options.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _usePasswordLogin = true;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitPasswordLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final ok = await ref
        .read(authControllerProvider.notifier)
        .loginWithPassword(
          _identifierController.text.trim(),
          _passwordController.text,
        );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ref.read(authControllerProvider).errorMessage ??
              'Login failed'),
        ),
      );
    }
  }

  Future<void> _submitOtpLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final phone = normalizeIndianPhone(_identifierController.text);
    final ok = await ref
        .read(authControllerProvider.notifier)
        .sendOtp(phone);
    if (!mounted) return;
    if (ok) {
      // In mock mode, show the OTP in a very visible banner so the user
      // can sign in without a real SMS.
      if (kUseMockAuth) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Your OTP is: ${MockAuthRepository.mockOtp}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            duration: const Duration(seconds: 8),
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            action: SnackBarAction(label: 'OK', onPressed: () {}),
          ),
        );
      }
      context.push('/otp?phone=${Uri.encodeComponent(phone)}');
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
              const Text('Sign in to your business account.'),
              const SizedBox(height: 24),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Password')),
                  ButtonSegment(value: false, label: Text('OTP')),
                ],
                selected: {_usePasswordLogin},
                onSelectionChanged: (v) {
                  setState(() => _usePasswordLogin = v.first);
                },
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _identifierController,
                keyboardType: _usePasswordLogin
                    ? TextInputType.emailAddress
                    : TextInputType.phone,
                autofillHints: _usePasswordLogin
                    ? const [AutofillHints.email]
                    : const [AutofillHints.telephoneNumber],
                decoration: InputDecoration(
                  labelText: _usePasswordLogin
                      ? 'Email or phone number'
                      : 'Phone number',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'This field is required';
                  }
                  if (!_usePasswordLogin) {
                    final digits = v.replaceAll(RegExp(r'\D'), '');
                    if (digits.length < 10) {
                      return 'Enter a valid phone number';
                    }
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _usePasswordLogin
                    ? _submitPasswordLogin()
                    : _submitOtpLogin(),
              ),
              if (_usePasswordLogin) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Enter your password';
                    if (v.length < 8) return 'Password must be at least 8 characters';
                    return null;
                  },
                  onFieldSubmitted: (_) => _submitPasswordLogin(),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => context.push('/forgot-password'),
                    child: const Text('Forgot password?'),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: isLoading
                    ? null
                    : (_usePasswordLogin
                        ? _submitPasswordLogin
                        : _submitOtpLogin),
                child: isLoading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_usePasswordLogin ? 'Sign in' : 'Send code'),
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
