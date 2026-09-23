import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/order_repository.dart';

/// Placeholder order detail screen. Wires the [OrderRepository] provider
/// (via [orderRepositoryProvider]) and lays the foundation for the real
/// tracking UI. The full screen will be fleshed out with status-stepper +
/// item list once the repository is validated in production.
class OrderDetailScreen extends ConsumerStatefulWidget {
  final String orderId;

  const OrderDetailScreen({super.key, required this.orderId});

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Order #${widget.orderId}')),
      body: const Center(
        child: Text(
          'Order detail screen — UI to follow',
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}
