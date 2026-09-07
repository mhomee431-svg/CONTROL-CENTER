import 'package:flutter/material.dart';

void main() => runApp(const HyperlocalAdminApp());

/// Minimal admin-panel shell.
///
/// Scaffold for the web admin console: verification queues, merchant
/// moderation, platform analytics. The admin REST surface already exists in
/// the backend (`backend/app/api/routes/admin*.py`); UI flows land here.
class HyperlocalAdminApp extends StatelessWidget {
  const HyperlocalAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hyperlocal Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A73E8)),
        useMaterial3: true,
      ),
      home: const AdminHomePage(),
    );
  }
}

class AdminHomePage extends StatelessWidget {
  const AdminHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hyperlocal Admin')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.admin_panel_settings_outlined, size: 64),
            const SizedBox(height: 16),
            Text(
              'Admin Panel',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Backend admin APIs are live under /admin/*.\n'
                'Wire auth + moderation/verification/analytics screens here.',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}