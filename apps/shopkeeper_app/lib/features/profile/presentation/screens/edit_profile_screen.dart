import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../features/auth/presentation/controllers/auth_controller.dart';
import '../controllers/profile_edit_controller.dart';

/// Edit Shopkeeper Profile — updates the signed-in user's own identity
/// (name, email) via `PUT /api/v1/profile` (phone is display-only: the
/// backend identity field is not editable here).
///
/// On success the refreshed name is pushed into the session snapshot
/// (single source of truth) and the screen pops.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;

  @override
  void initState() {
    super.initState();
    final state = ref.read(profileEditControllerProvider);
    _name = TextEditingController(text: state.name);
    _email = TextEditingController(text: state.email ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final err = await ref
        .read(profileEditControllerProvider.notifier)
        .save();
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    await ref.read(authControllerProvider.notifier).refreshUserName();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(profileEditControllerProvider);

    // Seed the fields when the async profile load lands (initState runs
    // before the fetch, so the controllers start empty).
    ref.listen<ProfileEditState>(profileEditControllerProvider, (prev, next) {
      if (prev?.status != ProfileEditStatus.ready &&
          next.status == ProfileEditStatus.ready) {
        if (_name.text.isEmpty && next.name.isNotEmpty) {
          _name.text = next.name;
        }
        if (_email.text.isEmpty && (next.email?.isNotEmpty ?? false)) {
          _email.text = next.email!;
        }
      }
    });

    if (state.status == ProfileEditStatus.loading) {
      return Scaffold(
        appBar: AppBar(title: Text(appText(context).commonEditProfile)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (state.status == ProfileEditStatus.error) {
      return Scaffold(
        appBar: AppBar(title: Text(appText(context).commonEditProfile)),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off, size: 44),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  state.error ?? 'Could not load your profile.',
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  ref.read(profileEditControllerProvider.notifier).retry();
                },
                icon: const Icon(Icons.refresh),
                label: Text(appText(context).commonRetry8),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(appText(context).commonEditProfile)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: InputDecoration(
                labelText: appText(context).commonFullName2,
                prefixIcon: Icon(Icons.person_outline),
              ),
              textCapitalization: TextCapitalization.words,
              maxLength: 120,
              onChanged: (v) =>
                  ref.read(profileEditControllerProvider.notifier).setName(v),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _email,
              decoration: InputDecoration(
                labelText: appText(context).commonEmailOptional,
                prefixIcon: Icon(Icons.alternate_email),
              ),
              keyboardType: TextInputType.emailAddress,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              onChanged: (v) =>
                  ref.read(profileEditControllerProvider.notifier).setEmail(v),
              validator: (v) {
                final value = v?.trim() ?? '';
                if (value.isEmpty) return null;
                return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)
                    ? null
                    : 'Enter a valid email address';
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: state.phoneNumber,
              decoration: InputDecoration(
                labelText: appText(context).commonPhoneNumber,
                prefixIcon: Icon(Icons.phone_outlined),
                helperText: appText(context).editProfileScreenContactSupportToChangeYour,
              ),
              enabled: false,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed:
                  state.status == ProfileEditStatus.saving ? null : _save,
              icon: state.status == ProfileEditStatus.saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(
                  state.status == ProfileEditStatus.saving ? 'Saving…' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}
