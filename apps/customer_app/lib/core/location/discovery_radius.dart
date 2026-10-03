/// The widening ladder for a "no nearby result" recovery.
///
/// WHY A SHARED LADDER
/// -------------------
/// The home feed (`/home/feed?radius_km=`) and a product's offers
/// (`/products/{id}?radius_km=`) are two different queries over the same idea
/// of "nearby", and both end at the server's `le=100` cap. Two screens each
/// inventing their own steps would end up offering "Search within 30 km" in one
/// place and "Search within 50 km" in the other for the same customer — and
/// one of them would eventually exceed 100 and be rejected with a 422.
///
/// Starting at null (not 10) is deliberate: the backend's own default rules
/// the FIRST load, and the first step is only ever offered when the customer
/// explicitly asks to look further. Nothing here ever narrows the search,
/// because narrowing an already-empty result is how you stay empty.
const List<double> kDiscoveryRadiusSteps = [10, 25, 50, 100];

/// The next wider radius, or null when the ladder is exhausted (the backend's
/// maximum — asking above this is a request the server rejects, so the button
/// is not rendered at all rather than rendered dead).
double? nextDiscoveryRadius(double? current) {
  for (final step in kDiscoveryRadiusSteps) {
    if (current == null || current < step) return step;
  }
  return null;
}

/// Whether a wider request is still possible.
bool canWidenDiscoveryRadius(double? current) =>
    nextDiscoveryRadius(current) != null;

/// The customer-facing label for the next step: the number they are about to
/// ask for, never a bare "search wider" that says nothing about what leaves the
/// device. Once the ladder is exhausted this reads as the ceiling it is, and
/// the button is hidden anyway.
String nextDiscoveryRadiusLabel(double? current) {
  final next = nextDiscoveryRadius(current);
  if (next == null) return 'Searching up to 100 km';
  return 'Search within ${next.toStringAsFixed(0)} km';
}
