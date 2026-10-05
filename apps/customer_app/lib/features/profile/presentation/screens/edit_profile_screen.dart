import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/form_keyboard.dart';
import '../../../../core/security/input_validator.dart';
import '../../../../core/theme/app_theme.dart';
import '../controllers/profile_controller.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;

  /// Focus nodes, in VISUAL order.
  ///
  /// The order of this list IS the keyboard's next/done order and the tab
  /// order, so it is declared once rather than implied by which field happens to
  /// come next in the widget tree.
  late final List<FocusNode> _fields;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(profileControllerProvider).value;
    _nameController = TextEditingController(text: profile?.name ?? '');
    _emailController = TextEditingController(text: profile?.email ?? '');
    _phoneController = TextEditingController(text: profile?.phoneNumber ?? '');
    _fields = [
      FocusNode(debugLabel: 'name'),
      FocusNode(debugLabel: 'email'),
      FocusNode(debugLabel: 'phone'),
    ];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    for (final node in _fields) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // Guarded here as well as on the button: `onPressed: null` stops a tap, but
    // only the handler stops a second call that arrives before the first
    // await returns (keyboard submit, a11y action, a rapid double tap that
    // lands in the same frame the button became disabled). Without this the
    // customer could send two PUTs and watch the second overwrite the first.
    if (_isSaving) return;

    setState(() => _isSaving = true);
    final success = await ref
        .read(profileControllerProvider.notifier)
        .updateProfile(
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
        );
    if (!mounted) return;
    setState(() => _isSaving = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update your profile. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: FormKeyboard.dismissOnBackgroundTap(
        child: FormKeyboard.ordered(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                TextFormField(
                  key: const Key('nameField'),
                  controller: _nameController,
                  focusNode: _fields[0],
                  textCapitalization: TextCapitalization.words,
                  textInputAction: FormKeyboard.actionFor(0, _fields.length),
                  onEditingComplete: () =>
                      FormKeyboard.advance(nodes: _fields, from: 0),
                  scrollPadding: FormKeyboard.scrollPaddingFor(context),
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) return 'Name is required.';
                    if (trimmed.length < 2) return 'Name is too short.';
                    if (trimmed.length > 60) return 'Name is too long.';
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  key: const Key('emailField'),
                  controller: _emailController,
                  focusNode: _fields[1],
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: FormKeyboard.actionFor(1, _fields.length),
                  onEditingComplete: () =>
                      FormKeyboard.advance(nodes: _fields, from: 1),
                  scrollPadding: FormKeyboard.scrollPaddingFor(context),
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  validator: InputValidator.validateEmail,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  key: const Key('phoneField'),
                  controller: _phoneController,
                  focusNode: _fields[2],
                  keyboardType: TextInputType.phone,
                  // The LAST field: `done` closes the keyboard and does NOT submit.
                  // Submission stays the explicit Save press, so a stray done can
                  // never write a half-typed phone number.
                  textInputAction: FormKeyboard.actionFor(2, _fields.length),
                  onEditingComplete: () =>
                      FormKeyboard.advance(nodes: _fields, from: 2),
                  scrollPadding: FormKeyboard.scrollPaddingFor(context),
                  autofillHints: const [AutofillHints.telephoneNumber],
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    helperText: 'Contact number for delivery coordination.',
                    border: OutlineInputBorder(),
                  ),
                  validator: InputValidator.validatePhone,
                ),
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    key: const Key('saveProfileButton'),
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_isSaving ? 'Saving…' : 'Save Changes'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
