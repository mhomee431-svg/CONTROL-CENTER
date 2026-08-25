import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    // Release-safe crash logging foundation (remote reporter pending).
    debugPrint('Uncaught framework error: ${details.exception}');
  };
  runApp(const ProviderScope(child: ShopkeeperApp()));
}
