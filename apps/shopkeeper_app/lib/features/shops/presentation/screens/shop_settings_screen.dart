import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/errors/app_message_code.dart';
import '../../../../core/l10n/app_text.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/token_store.dart';
import '../../../../core/ui/numeric_input.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../data/shop_repository.dart';
import '../../domain/shop_models.dart';
import '../widgets/holidays_section.dart';

/// Operational shop settings — order acceptance, delivery & pickup.
class ShopSettingsScreen extends ConsumerStatefulWidget {
  const ShopSettingsScreen({super.key});

  @override
  ConsumerState<ShopSettingsScreen> createState() =>
      _ShopSettingsScreenState();
}

class _ShopSettingsScreenState extends ConsumerState<ShopSettingsScreen> {
  ShopDetail? _detail;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  late bool _accepting, _delivery, _pickup, _open24x7;
  late final TextEditingController _minOrder = TextEditingController();
  late final TextEditingController _radius = TextEditingController();
  late final TextEditingController _fee = TextEditingController();
  late final TextEditingController _freeAbove = TextEditingController();

  bool get _canEdit =>
      ref.read(selectedShopProvider)?.canManageSettings ?? false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _minOrder.dispose();
    _radius.dispose();
    _fee.dispose();
    _freeAbove.dispose();
    super.dispose();
  }

  void _bind(ShopDetail d) {
    _accepting = d.isAcceptingOrders;
    _delivery = d.isDeliveryAvailable;
    _pickup = d.isPickupAvailable;
    _open24x7 = d.isOpen24x7;
    _minOrder.text = d.minOrderAmount.toStringAsFixed(0);
    _radius.text = d.deliveryRadiusKm.toStringAsFixed(1);
    _fee.text = d.deliveryFee.toStringAsFixed(0);
    _freeAbove.text = d.freeDeliveryAbove.toStringAsFixed(0);
  }

  Future<void> _load() async {
    final shop = ref.read(selectedShopProvider);
    if (shop == null) return;
    setState(() => _loading = true);
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw ApiException.localized(AppMessageCode.notSignedIn);
      final detail =
          await ref.read(shopRepositoryProvider).getShopDetail(shop.id, token);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _bind(detail);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load settings.';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final detail = _detail;
    final shop = ref.read(selectedShopProvider);
    if (detail == null || shop == null) return;
    final fields = <String, dynamic>{
      'is_accepting_orders': _accepting,
      'is_delivery_available': _delivery,
      'is_pickup_available': _pickup,
      'is_open_24x7': _open24x7,
      if (double.tryParse(_minOrder.text) != null)
        'min_order_amount': double.parse(_minOrder.text),
      if (double.tryParse(_radius.text) != null)
        'delivery_radius_km': double.parse(_radius.text),
      if (double.tryParse(_fee.text) != null)
        'delivery_fee': double.parse(_fee.text),
      if (double.tryParse(_freeAbove.text) != null)
        'free_delivery_above': double.parse(_freeAbove.text),
    };
    setState(() => _saving = true);
    try {
      await ref
          .read(shopRepositoryProvider)
          .updateSettings(
            shop.id,
            fields,
            (await ref.read(tokenStoreProvider).readAccessToken())!,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(appText(context).commonSettingsSaved)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(appText(context).shopSettingsScreenCouldNotSavePleaseRetry)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(appText(context).commonShopSettings3), actions: [
        IconButton(
          // Accessible name for the icon-only refresh action.
          tooltip: appText(context).commonRefresh9,
          onPressed: _load,
          icon: const Icon(Icons.refresh),
        ),
      ]),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (!_canEdit)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              appText(context).shopSettingsScreenManagersCannotChangeShopSettings,
                              style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.error),
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        title: Text(appText(context).commonAcceptingOrders),
                        subtitle: Text(
                            appText(context).shopSettingsScreenCustomersCanPlaceNewOrders),
                        value: _accepting,
                        onChanged: _canEdit
                            ? (v) => setState(() => _accepting = v)
                            : null,
                      ),
                      SwitchListTile(
                        title: Text(appText(context).commonDeliveryAvailable),
                        value: _delivery,
                        onChanged: _canEdit
                            ? (v) => setState(() => _delivery = v)
                            : null,
                      ),
                      SwitchListTile(
                        title: Text(appText(context).commonPickupAvailable),
                        value: _pickup,
                        onChanged: _canEdit
                            ? (v) => setState(() => _pickup = v)
                            : null,
                      ),
                      SwitchListTile(
                        title: Text(appText(context).shopSettingsScreenOpen247),
                        value: _open24x7,
                        onChanged: _canEdit
                            ? (v) => setState(() => _open24x7 = v)
                            : null,
                      ),
                      const Divider(height: 32),
                      Text(appText(context).commonFulfilment,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: TextFormField(
                            controller: _minOrder,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: NumericInput.decimal(),
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                                labelText: appText(context).commonMinOrderAmount),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _radius,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: NumericInput.decimal(),
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                                labelText: appText(context).commonDeliveryRadiusKm),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: TextFormField(
                            controller: _fee,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: NumericInput.decimal(),
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                                labelText: appText(context).commonDeliveryFee),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _freeAbove,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: NumericInput.decimal(),
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) =>
                                FocusScope.of(context).unfocus(),
                            decoration: InputDecoration(
                                labelText: appText(context).commonFreeDeliveryAbove),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 24),
                      HolidaysSection(canEdit: _canEdit),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed:
                            (_canEdit && !_saving) ? _save : null,
                        icon: _saving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : const Icon(Icons.save_outlined),
                        label: Text(appText(context).commonSaveSettings2),
                      ),
                    ],
                  ),
      ),
    );
  }
}

