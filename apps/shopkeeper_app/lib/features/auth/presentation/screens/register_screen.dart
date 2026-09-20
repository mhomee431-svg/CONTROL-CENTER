import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/ui/numeric_input.dart';
import '../controllers/auth_controller.dart';
import '../../data/phone_utils.dart';

/// Business-account registration: name + phone number + password.
///
/// Registration creates the account with the chosen password — it does NOT
/// depend on SMS. Phone-OTP sign-in is a separate method (`/phone-otp`) for
/// accounts that would rather not keep a password.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final phone = normalizeIndianPhone(_phoneController.text);
    final ok = await ref
        .read(authControllerProvider.notifier)
        .registerWithPassword(
          name: _nameController.text.trim(),
          phoneNumber: phone,
          password: _passwordController.text,
        );
    if (!mounted) return;
    if (ok) {
      // Router guard routes to /shops (or /dashboard) automatically.
      return;
    }
    final error = ref.read(authControllerProvider);
    if ((error.errorCode ?? '').contains('PHONE_ALREADY_REGISTERED') ||
        (error.errorMessage ?? '').contains('already registered')) {
      // Phone is taken → guide the user to the Login screen.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Phone number already registered. Please login instead.'),
          duration: Duration(seconds: 4),
        ),
      );
      context.go(Routes.login);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.errorMessage ?? 'Registration failed'),
        ),
      );
    }
  }

  /// Google OAuth sign-in (web login flow).
  ///
  /// The consent screen opens in a new browser tab; the backend polls the
  /// one-shot handoff endpoint and completes the session when Google returns
  /// the token payload (max 3 minutes). A hint snackbar tells the user to
  /// complete sign-in in the opened Google window.
  Future<void> _signInWithGoogle() async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Complete sign-in in the opened Google window…'),
    ));
    final ok = await ref.read(authControllerProvider.notifier).signInWithGoogle();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ref.read(authControllerProvider).errorMessage ??
            'Google sign-in failed. Please try again.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authControllerProvider.select((s) => s.isLoading));
    return Scaffold(
      appBar: AppBar(title: const Text('Create business account')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Tell us about your business',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text(
                  'Create your account with your phone number and a password.'),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration:
                    const InputDecoration(labelText: 'Your name'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                // Digits plus the separators a pasted number may carry; the
                // validator below still normalises before the API call.
                inputFormatters: NumericInput.phone(),
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Business phone number',
                  hintText: '9999999999',
                  prefixText: '+91 ',
                ),
                validator: (v) {
                  final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                  if (digits.length < 10) return 'Enter a valid 10-digit number';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    // Tooltips are the accessible name for icon-only actions;
                    // they also describe the password field's current state.
                    tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Password is required';
                  if (v.length < 8) return 'At least 8 characters';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirm password',
                  suffixIcon: IconButton(
                    // Accessible name for the visibility toggle.
                    tooltip: _obscureConfirm ? 'Show password' : 'Hide password',
                    icon: Icon(_obscureConfirm
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                validator: (v) {
                  if (v != _passwordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: isLoading ? null : _submit,
                child: isLoading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create account'),
              ),
              const SizedBox(height: 16),
              Row(
                children: const [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or', style: TextStyle(color: AppColors.textMuted)),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: isLoading ? null : _signInWithGoogle,
                icon: const Icon(Icons.account_circle, size: 20),
                label: const Text('Continue with Google'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.go(Routes.login),
                child: const Text('Already have an account? Sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}