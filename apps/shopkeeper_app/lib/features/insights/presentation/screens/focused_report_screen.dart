import 'package:flutter/material.dart';

import '../../domain/insights_models.dart';
import 'insights_screen.dart';

/// Reuses the report's loading, retry, range and selected-shop handling.
class FocusedReportScreen extends StatelessWidget {
  const FocusedReportScreen({super.key, required this.report});

  final FocusedReport report;

  @override
  Widget build(BuildContext context) => InsightsScreen(report: report);
}
