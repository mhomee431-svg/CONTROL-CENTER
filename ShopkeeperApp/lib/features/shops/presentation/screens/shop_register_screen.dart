import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../data/location_service.dart';
import '../../data/pincode_lookup.dart';
import '../../data/pincode_api_service.dart';
import '../../data/gstin_decoder.dart';
import '../../domain/shop_models.dart';
import '../controllers/shops_controller.dart';
import 'map_picker_screen.dart';
import 'location_capture_screen.dart';
import '../../domain/location_capture_state.dart';

class ShopRegisterScreen extends ConsumerStatefulWidget {
  const ShopRegisterScreen({super.key});
  @override ConsumerState<ShopRegisterScreen> createState() => _ShopRegisterScreenState();
}

class _ShopRegisterScreenState extends ConsumerState<ShopRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _tagline = TextEditingController();
  final _description = TextEditingController();
  final _phone = TextEditingController();
  final _gstin = TextEditingController();
  final _addressLine = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _pincode = TextEditingController();
  String _category = 'GROCERY';
  bool _submitted = false;
  bool _pinLoading = false;
  bool _locating = false;
  LatLng? _coordinates;
  CapturedShopLocation? _capturedLocation;
  String? _detectedAddress;
  GstinDetails? _gstinDetails;
  PincodeApiResult? _pincodeResult;

  @override void initState() {
    super.initState();
    _pincode.addListener(_onPincode);
    _gstin.addListener(_onGstin);
    PincodeLookup.instance.ensureLoaded();
  }

  @override void dispose() {
    _pincode.removeListener(_onPincode);
    _gstin.removeListener(_onGstin);
    for (final c in [_name,_tagline,_description,_phone,_gstin,_addressLine,_city,_state,_pincode]) { c.dispose(); }
    super.dispose();
  }

  void _onPincode() {
    final code = _pincode.text.trim();
    if (code.length != 6) { setState(() => _pincodeResult = null); return; }
    final local = PincodeLookup.instance.lookupSync(code);
    if (local != null) {
      if (_city.text.trim().isEmpty) _city.text = local.city;
      if (_state.text.trim().isEmpty) _state.text = local.state;
    }
    _lookupPincodeApi(code);
    _revalidate();
  }

  // Re-runs form validation so stale Required errors clear after auto-fill.
  void _revalidate() {
    if (!_submitted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _formKey.currentState?.validate();
    });
  }

  Future<void> _lookupPincodeApi(String code) async {
    setState(() => _pinLoading = true);
    try {
      final result = await PincodeApiService.instance.lookup(code);
      if (!mounted || result == null) return;
      setState(() {
        _pincodeResult = result;
        if (_city.text.trim().isEmpty) _city.text = result.city;
        if (_state.text.trim().isEmpty) _state.text = result.state;
        if (_addressLine.text.trim().isEmpty && result.postOffices.isNotEmpty) {
          _addressLine.text = result.postOffices.first.name;
        }
      });
    } catch (_) {} finally { if (mounted) setState(() => _pinLoading = false); }
  }

  void _onGstin() {
    final raw = _gstin.text.trim();
    setState(() => _gstinDetails = raw.length == 15 ? GstinDecoder.instance.decode(raw) : null);
  }

  /// Opens the high-accuracy location capture flow and stores the result.
  Future<void> _detectLocation() async {
    setState(() => _locating = true);
    try {
      final result = await Navigator.of(context).push<CapturedShopLocation>(
        MaterialPageRoute(
          builder: (_) => LocationCaptureScreen(shopName: _name.text.trim()),
        ),
      );
      if (!mounted) return;
      if (result == null) return; // shopkeeper chose manual entry
      setState(() {
        _capturedLocation = result;
        _coordinates = LatLng(result.latitude, result.longitude);
        _detectedAddress = result.addressText;
        if (result.addressText != null && result.addressText!.isNotEmpty && _addressLine.text.trim().isEmpty) {
          _addressLine.text = result.addressText!;
        }
        if (result.city != null && result.city!.isNotEmpty && _city.text.trim().isEmpty) _city.text = result.city!;
        if (result.state != null && result.state!.isNotEmpty && _state.text.trim().isEmpty) _state.text = result.state!;
        if (result.pincode != null && result.pincode!.isNotEmpty && _pincode.text.trim().isEmpty) _pincode.text = result.pincode!;
      });
      _revalidate();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location captured — accuracy ${result.accuracyMeters.toStringAsFixed(0)} m'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Location error: $e')));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _pickOnMap() async {
    final result = await Navigator.of(context).push<PickedLocation>(MaterialPageRoute(builder: (_) => MapPickerScreen(initialLocation: _coordinates)));
    if (result != null && mounted) {
      setState(() {
        _coordinates = LatLng(result.latitude, result.longitude);
        _detectedAddress = result.addressLine;
        if (result.addressLine != null && result.addressLine!.isNotEmpty && _addressLine.text.trim().isEmpty) _addressLine.text = result.addressLine!;
        if (result.city != null && result.city!.isNotEmpty && _city.text.trim().isEmpty) _city.text = result.city!;
        if (result.state != null && result.state!.isNotEmpty && _state.text.trim().isEmpty) _state.text = result.state!;
        if (result.pincode != null && result.pincode!.isNotEmpty && _pincode.text.trim().isEmpty) _pincode.text = result.pincode!;
        _revalidate();
      });
    }
  }

  Future<void> _submit() async {
    _submitted = true;
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final payload = <String, dynamic>{
      'name': _name.text.trim(), 'category': _category,
      if (_tagline.text.trim().isNotEmpty) 'tagline': _tagline.text.trim(),
      if (_description.text.trim().isNotEmpty) 'description': _description.text.trim(),
      if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
      if (_gstin.text.trim().isNotEmpty) 'gstin': _gstin.text.trim(),
      'latitude': _coordinates?.latitude ?? 0.0,
      'longitude': _coordinates?.longitude ?? 0.0,
      'address': {
        'address_line1': _addressLine.text.trim(),
        'city': _city.text.trim(),
        'state': _state.text.trim(),
        'pincode': _pincode.text.trim(),
      },
      if (_capturedLocation != null) 'location': _capturedLocation!.toLocationMeta(),
    };
    final ok = await showDialog<bool>(context: context, builder: (_) => _confirmDialog(payload));
    if (ok != true) return;
    final done = await ref.read(shopsControllerProvider.notifier).registerShop(payload);
    if (!mounted) return;
    if (done) { context.go('/dashboard'); } else { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.read(shopsControllerProvider).errorMessage ?? 'Registration failed'))); }
  }

  AlertDialog _confirmDialog(Map<String, dynamic> p) {
    final a = p['address'] as Map<String, dynamic>;
    Widget row(String k, String? v) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [SizedBox(width: 90, child: Text('$k:', style: const TextStyle(fontWeight: FontWeight.bold))), Expanded(child: Text((v != null && v.isNotEmpty) ? v : '-'))]));
    return AlertDialog(title: const Text('Confirm shop details'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [row('Shop name', p['name']), row('Category', p['category']), if (p['tagline'] != null) row('Tagline', p['tagline']), if (p['phone'] != null) row('Phone', p['phone']), if (p['gstin'] != null) row('GSTIN', p['gstin']), const Divider(), row('Address', a['address_line1']), row('City', a['city']), row('State', a['state']), row('Pincode', a['pincode']), const Divider(), row('Latitude', (p['latitude'] as double).toStringAsFixed(6)), row('Longitude', (p['longitude'] as double).toStringAsFixed(6))])), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Close')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Register'))]);
  }

  @override Widget build(BuildContext context) {
    final s = ref.watch(shopsControllerProvider.select((st) => st.status == ShopsStatus.loading));
    return Scaffold(appBar: AppBar(title: const Text('Register a new shop')), body: SafeArea(child: Form(key: _formKey, child: ListView(padding: const EdgeInsets.all(16), children: _buildFormFields(s)))));
  }

  List<Widget> _buildFormFields(bool s) => [
    Text('Business details', style: Theme.of(context).textTheme.titleMedium), gap(12),
    field(_name, 'Shop name *', capitalization: TextCapitalization.words), gap(12),
    DropdownButtonFormField<String>(initialValue: _category, decoration: const InputDecoration(labelText: 'Category *'), items: [for (final cat in kShopCategories) DropdownMenuItem(value: cat, child: Text(cat))], onChanged: (v) => setState(() => _category = v ?? _category)), gap(12),
    field(_tagline, 'Tagline (optional)', hint: 'e.g. Fresh groceries'), gap(12),
    TextFormField(controller: _description, maxLines: 3, decoration: const InputDecoration(labelText: 'Description (optional)')), gap(12),
    field(_phone, 'Business phone (optional)', prefix: '+91 ', hint: '9999999999', keyboard: TextInputType.phone), gap(12),
    field(_gstin, 'GSTIN (optional)', hint: '22AAAAA0000A1Z5', capitalization: TextCapitalization.characters),
    if (_gstinDetails != null && _gstinDetails!.isValid) ...[gap(8), _gstinCard(_gstinDetails!)], gap(24),
    Text('Location & address', style: Theme.of(context).textTheme.titleMedium), gap(12),
    Row(children: [Expanded(child: ElevatedButton.icon(onPressed: _locating ? null : _detectLocation, icon: _locating ? spin() : const Icon(Icons.my_location), label: Text(_locating ? 'Detecting...' : 'Detect my location'))), gapw(12),
      Expanded(child: OutlinedButton.icon(onPressed: _pickOnMap, icon: const Icon(Icons.map), label: const Text('Pick on map')))]),
    if (_coordinates != null) ...[gap(8), _liveCoordinatesCard()], gap(12),
    field(_addressLine, 'Address line *', capitalization: TextCapitalization.words), gap(12),
    Row(children: [Expanded(child: field(_city, 'City *')), gapw(12), Expanded(child: field(_state, 'State *')), gapw(12),
      Expanded(child: TextFormField(controller: _pincode, keyboardType: TextInputType.number, maxLength: 6, decoration: InputDecoration(labelText: 'Pincode *', counterText: '', suffixIcon: _pinLoading ? spin() : (_pincodeResult != null ? const Icon(Icons.check_circle, color: Colors.green) : null)), validator: (v) { final code = (v ?? '').trim(); if (code.length != 6 || !RegExp(r'^\d{6}$').hasMatch(code)) return 'Enter a valid 6-digit pincode'; return null; }))]),
    if (_pincodeResult != null) ...[gap(8), _pincodeResultCard()], gap(24),
    FilledButton.icon(onPressed: s ? null : _submit, icon: s ? spin() : const Icon(Icons.storefront), label: const Text('Register shop')), gap(32),
  ];

  Widget _liveCoordinatesCard() => Container(width: double.infinity, padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.withValues(alpha: 0.3))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Live Coordinates', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), const SizedBox(height: 2),
      Text('Lat: ${_coordinates!.latitude.toStringAsFixed(6)}  Lng: ${_coordinates!.longitude.toStringAsFixed(6)}', style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
      if (_detectedAddress != null && _detectedAddress!.isNotEmpty) Text('📍 ', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
    ]));

  Widget _pincodeResultCard() { final r = _pincodeResult!; return Container(width: double.infinity, padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.withValues(alpha: 0.3))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Pincode: ${r.pincode}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), const SizedBox(height: 2),
      if (r.city.isNotEmpty) Text('City: ${r.city}', style: const TextStyle(fontSize: 13)),
      if (r.district.isNotEmpty) Text('District: ${r.district}', style: const TextStyle(fontSize: 13)),
      Text('State: ${r.state}', style: const TextStyle(fontSize: 13)),
    ])); }

  Widget field(TextEditingController ctl, String label, {String? hint, String? prefix, TextInputType? keyboard, TextCapitalization capitalization = TextCapitalization.none}) =>
    TextFormField(controller: ctl, keyboardType: keyboard, textCapitalization: capitalization, decoration: InputDecoration(labelText: label, hintText: hint, prefixText: prefix), validator: (v) => label.endsWith('*') && (v ?? '').trim().isEmpty ? 'Required' : null);

  Widget gap(double h) => SizedBox(height: h);
  Widget gapw(double w) => SizedBox(width: w);
  Widget spin() => const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)));

  Widget _gstinCard(GstinDetails d) => Container(width: double.infinity, padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8), border: Border.all(color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.4))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('GSTIN Owner Details', style: Theme.of(context).textTheme.titleSmall), const SizedBox(height: 4),
      Text('State: ${d.stateName ?? '-'} (Code: ${d.stateCode ?? '-'})'), Text('Owner PAN: ${d.pan ?? '-'}'), Text('Entity: ${d.entityName ?? '-'}'),
    ]));
}
