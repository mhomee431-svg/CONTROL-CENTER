import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/router/route_names.dart';
import '../../domain/auth_methods.dart';
import '../../domain/auth_models.dart';
import '../controllers/auth_controller.dart';
import '../widgets/auth_widgets.dart';

/// Sign-in screen: phone/email + password, with Google and Phone OTP offered
/// as the alternative methods this build enables.
///
/// The router guard owns what happens after success — the controller reports
/// `authenticated` and the redirect takes over — so this screen never
/// navigates manually after a successful sign-in.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  static const identifierFieldKey = Key('login-identifier-field');
  static const passwordFieldKey = Key('login-password-field');
  static const submitKey = Key('login-submit');
  static const errorKey = Key('login-error');
  static const forgotKey = Key('login-forgot');
  static const googleKey = Key('login-google');

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _error = null);
    final ok = await ref.read(authControllerProvider.notifier).loginWithPassword(
          _identifierController.text.trim(),
          _passwordController.text,
        );
    if (!mounted || ok) return; // authenticated → the router redirects
    setState(() {
      _error = ref.read(authControllerProvider).errorMessage ??
          'Sign-in failed. Please check your details and try again.';
    });
  }

  /// The backend resolves phone OR email, so the identifier is passed through
  /// as typed — rewriting it client-side would only break one of the two.
  String? _validateIdentifier(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Enter your phone number or email';
    if (text.contains('@')) {
      return text.contains('.') ? null : 'Enter a valid email address';
    }
    final digits = text.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 10 ? null : 'Enter a valid phone number or email';
  }

  /// Google is an alternative METHOD for the same session, so its failure is
  /// reported in the same inline banner as a password failure — never a
  /// SnackBar that disappears with the reason.
  Future<void> _signInWithGoogle() async {
    setState(() => _error = null);
    final ok =
        await ref.read(authControllerProvider.notifier).signInWithGoogle();
    if (!mounted || ok) return;
    setState(() {
      _error = ref.read(authControllerProvider).errorMessage ??
          'Google sign-in failed. Please try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLoading =
        ref.watch(authControllerProvider.select((s) => s.isLoading));
    final googleEnabled =
        ref.watch(isAuthMethodEnabledProvider(AuthMethod.googleFirebase));
    final phoneEnabled =
        ref.watch(isAuthMethodEnabledProvider(AuthMethod.phoneOtp)) &&
            ref.read(authControllerProvider.notifier).isPhoneOtpSupported;
    final passwordEnabled =
        ref.watch(isAuthMethodEnabledProvider(AuthMethod.password));

    return Scaffold(
      appBar: AppBar(
        title: Text(appText(context).commonSignIn3),
        leading: IconButton(
          // Icon-only buttons carry no text, so `tooltip` supplies the
          // accessible name a screen reader announces.
          tooltip: appText(context).commonBack,
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.welcome),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(appText(context).commonWelcomeBack,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(appText(context).loginScreenSignInWithThePhone,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.outline)),
                const SizedBox(height: 24),
                // The password form is gated on the SAME switch as the
                // Welcome screen's link to this route. The route stays
                // registered (re-enabling is one line in the SSOT), so a
                // deep link must not land on a form the MVP does not
                // offer. Gating the LINK was not enough.
                if (passwordEnabled) ...[
                  TextFormField(
                    key: LoginScreen.identifierFieldKey,
                    controller: _identifierController,
                    enabled: !isLoading,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.username],
                    decoration: InputDecoration(
                      labelText: appText(context).commonPhoneNumberOrEmail,
                    ),
                    validator: _validateIdentifier,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: LoginScreen.passwordFieldKey,
                    controller: _passwordController,
                    enabled: !isLoading,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: appText(context).commonPassword,
                      suffixIcon: IconButton(
                        // Accessible name for the visibility toggle; it also
                        // states what the tap will do.
                        tooltip: _obscure ? 'Show password' : 'Hide password',
                        icon: Icon(
                            _obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Password is required' : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    AuthErrorBanner(
                      key: LoginScreen.errorKey,
                      message: _error!,
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    key: LoginScreen.submitKey,
                    onPressed: isLoading ? null : _submit,
                    child: isLoading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(appText(context).commonSignIn3),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      key: LoginScreen.forgotKey,
                      onPressed: isLoading
                          ? null
                          : () => context.push(Routes.forgotPassword),
                      child: Text(appText(context).commonForgotPassword2),
                    ),
                  ),
                ],
                if (googleEnabled || phoneEnabled) ...[
                  const SizedBox(height: 4),
                  const AuthMethodDivider(),
                  const SizedBox(height: 16),
                ],
                if (googleEnabled)
                  GoogleSignInButton(
                    key: LoginScreen.googleKey,
                    isLoading: isLoading,
                    onPressed: isLoading ? null : _signInWithGoogle,
                  ),
                if (phoneEnabled) ...[
                  const SizedBox(height: 12),
                  PhoneSignInButton(
                    onPressed: isLoading
                        ? null
                        : () => context.push(Routes.phoneOtp),
                  ),
                ],
                const SizedBox(height: 12),
                TextButton(
                  onPressed:
                      isLoading ? null : () => context.push(Routes.register),
                  child: Text(appText(context).loginScreenNewHereCreateAnAccount),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
