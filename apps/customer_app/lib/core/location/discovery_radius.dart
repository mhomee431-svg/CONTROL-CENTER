/// The backend's own default radius, in km. `GET /home/feed` and
/// `GET /products/{id}` both declare `radius_km = Query(10.0, gt=0, le=100)`,
/// so an unset radius on the wire is a 10 km query.
///
/// WHY IT IS NAMED HERE
/// --------------------
/// This is the value an unset radius *means*, so the ladder measures from it
/// rather than from zero. Treating "unset" as "narrower than every step" made
/// the first widen a no-op: the empty state offered "Search within 10 km",
/// which re-issued the exact 10 km query that had just returned nothing, so
/// the button looked like it worked and changed nothing.
const double kBackendDefaultDiscoveryRadiusKm = 10;

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
/// The first step is 10 km because the backend default (above) is what rules
/// the FIRST load; the first *offered* step is therefore the next genuine step
/// up from it, never a restatement of the query that already came back empty.
/// Nothing here ever narrows the search, because narrowing an already-empty
/// result is how you stay empty.
const List<double> kDiscoveryRadiusSteps = [10, 25, 50, 100];

/// The next wider radius, or null when the ladder is exhausted (the backend's
/// maximum — asking above this is a request the server rejects, so the button
/// is not rendered at all rather than rendered dead).
double? nextDiscoveryRadius(double? current) {
  // A null radius is not "less than every step" — it is the backend default.
  // Measuring from it is what stops the first widen from repeating the load
  // that produced this very empty state.
  final from = current ?? kBackendDefaultDiscoveryRadiusKm;
  for (final step in kDiscoveryRadiusSteps) {
    if (from < step) return step;
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
