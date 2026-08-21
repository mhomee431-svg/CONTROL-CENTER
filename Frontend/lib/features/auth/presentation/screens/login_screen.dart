import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../controllers/auth_controller.dart';
import '../../../../core/theme/app_theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  void _handleSendOtp() async {
    if (_formKey.currentState!.validate()) {
      final success = await ref.read(authControllerProvider.notifier).sendOtp(_phoneController.text);
      if (success && mounted) {
        context.push('/otp', extra: _phoneController.text);
      }
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

    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next.status == AuthStatus.error) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.errorMessage!)));
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Welcome to Hyperlocal',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppSpacing.xl),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    border: OutlineInputBorder(),
                    prefixText: '+91 ',
                  ),
                  validator: (value) => value != null && value.length >= 10 ? null : 'Enter a valid phone number',
                ),
                const SizedBox(height: AppSpacing.md),
                ElevatedButton(
                  onPressed: authState.status == AuthStatus.loading ? null : _handleSendOtp,
                  child: authState.status == AuthStatus.loading
                      ? const CircularProgressIndicator.adaptive()
                      : const Text('Send OTP'),
                ),
                TextButton(
                  onPressed: authState.status == AuthStatus.loading
                      ? null
                      : () => ref.read(authControllerProvider.notifier).continueAsGuest(),
                  child: const Text('Continue as Guest'),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}