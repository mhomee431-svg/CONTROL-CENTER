import 'package:flutter/material.dart';

import '../../domain/models/business_profile_models.dart';
import '../../../../core/theme/app_theme.dart';

/// The service side of a transport / travel provider's profile
/// (Master Spec §87-§88).
///
/// Services + fleet, never products. Reference prices are shown per service as
/// the backend serves them (most are QUOTED per trip), but there is no cart, no
/// checkout, no delivery, and no booking here — only a request ENTRY POINT, and
/// only when the provider's capabilities include `quote_request` (i.e. the
/// backend contract behind the button exists). Without that capability this
/// widget shows the services and nothing more: a booking form with no provider
/// record behind it would be a faked booking.
class ServiceProfileSection extends StatelessWidget {
  final TransportServiceProfile service;
  final bool canRequestQuote;
  final VoidCallback? onRequestQuote;

  const ServiceProfileSection({
    super.key,
    required this.service,
    required this.canRequestQuote,
    this.onRequestQuote,
  });

  @override
  Widget build(BuildContext context) {
    final activeServices = service.services.where((s) => s.isActive).toList();
    final activeVehicles = service.vehicles.where((v) => v.isActive).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (activeServices.isNotEmpty) ...[
          // No 'Services' heading here: the profile screen already titles this
          // section, and two identical headings read as a rendering bug. The
          // fleet keeps its own, because it is a different kind of information.
          ...activeServices.map((s) => _ServiceRow(service: s)),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (activeVehicles.isNotEmpty) ...[
          _SubTitle('Fleet (${activeVehicles.length})'),
          ...activeVehicles.map((v) => _VehicleRow(vehicle: v)),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (activeServices.isEmpty && activeVehicles.isEmpty)
          const Text(
            'This provider has not published services or vehicles yet. '
            'Call them for the latest options.',
            style: TextStyle(color: AppColors.textMuted),
          ),
        if (canRequestQuote) ...[
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onRequestQuote,
              icon: const Icon(Icons.request_quote_outlined),
              label: const Text('Request a quote'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'The provider quotes the price; nothing is booked or charged here.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ],
    );
  }
}

class _SubTitle extends StatelessWidget {
  final String text;
  const _SubTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: 4),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// One bookable service with its reference price.
///
/// A price shown as "per trip/day/km" or "on quote" NEVER implies a fixed
/// charge — the final amount is what the provider quotes for the customer's
/// trip — so no service row has a buy/book action, only the single
/// request-a-quote entry point above it.
class _ServiceRow extends StatelessWidget {
  final TransportServiceOffering service;
  const _ServiceRow({required this.service});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.directions_car_outlined,
            size: 20,
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  _serviceTypeLabel(service.serviceType),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            _referencePrice(service),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// One vehicle, rendered as what it IS for the customer's decision: type,
/// make/model, seats and AC. Registration numbers and documents are operator
/// data and stay off the customer surface.
class _VehicleRow extends StatelessWidget {
  final ProviderVehicle vehicle;
  const _VehicleRow({required this.vehicle});

  @override
  Widget build(BuildContext context) {
    final model = [
      vehicle.make,
      vehicle.model,
    ].where((part) => part.isNotEmpty).join(' ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.commute_outlined,
            size: 20,
            color: AppColors.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  model.isEmpty ? vehicle.vehicleType : model,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  [
                    vehicle.vehicleType,
                    if (vehicle.capacityPassengers > 0)
                      '${vehicle.capacityPassengers} seats',
                    if (vehicle.acAvailable) 'AC',
                  ].join('  •  '),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "AIRPORT" reads as airport drops to a customer; the raw enum does not.
String _serviceTypeLabel(String raw) {
  final label = raw.trim().toLowerCase().replaceAll('_', ' ');
  if (label.isEmpty) return 'Trip service';
  return label[0].toUpperCase() + label.substring(1);
}

/// A reference figure, never a charge: "₹650 / trip" or "On quote".
/// `QUOTE` and `0` both mean the provider quotes this one entirely.
String _referencePrice(TransportServiceOffering service) {
  final unit = service.priceUnit.trim().toUpperCase();
  if (unit.isEmpty || unit == 'QUOTE' || service.basePrice <= 0) {
    return 'On quote';
  }
  final qualifier = switch (unit) {
    'PER_TRIP' => '/ trip',
    'PER_DAY' => '/ day',
    'PER_KM' => '/ km',
    'PER_HOUR' => '/ hour',
    _ => '',
  };
  return '₹${service.basePrice.toInt()} $qualifier'.trim();
}
