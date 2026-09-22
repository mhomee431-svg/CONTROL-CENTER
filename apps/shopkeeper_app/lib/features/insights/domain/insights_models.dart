// Reports & Insights domain models.
//
// Mirrors the backend contract
// `GET /api/v1/shopkeeper/shops/{id}/analytics/full`
// (`backend/app/services/shopkeeper_analytics.py`). Every value is computed
// server-side from REAL customer activity — shop views, product clicks,
// customer interactions and inventory freshness.
//
// The app never fabricates a metric: an absent / unknown section parses to an
// empty or zero-valued model so the UI can render an honest empty state
// instead of an invented number.

int _asInt(Object? value) => switch (value) {
  num n => n.toInt(),
  String s => int.tryParse(s) ?? 0,
  _ => 0,
};

double _asDouble(Object? value) => switch (value) {
  num n => n.toDouble(),
  String s => double.tryParse(s) ?? 0,
  _ => 0,
};

Map<String, dynamic> _asMap(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : const <String, dynamic>{};

List<Map<String, dynamic>> _asMapList(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((entry) => entry.cast<String, dynamic>())
          .toList(growable: false)
    : const <Map<String, dynamic>>[];

/// Reporting windows offered by the Reports / Insights screen. The backend
/// clamps `days` to 1..365 (and the hour-of-day distribution to the trailing
/// 30 days), so these are always safe client-side values.
const List<int> kInsightsRanges = <int>[7, 30, 90];

/// Default reporting window (in days) for a fresh screen load.
const int kInsightsDefaultRange = 30;

/// Top-products rows a drill-down may request (the full report ships the
/// backend default of 10; the backend caps `limit` at 50).
const int kInsightsMaxTopProducts = 50;

/// Focused views of the existing analytics payload (not sales transactions).
enum FocusedReport {
  sales,
  products,
  inventory;

  String get title => switch (this) {
    sales => 'Sales report',
    products => 'Product report',
    inventory => 'Inventory report',
  };
}


/// KPI cards on the Reports screen that support a drill-down detail view.
///
/// Each metric owns its own granular endpoints and a wider parameter space
/// than the single combined report call allows.
enum DrillDownMetric { views, clicks }

extension DrillDownMetricX on DrillDownMetric {
  /// Route segment for `go_router` (`/insights/drill-down/:metric`).
  String get routeSegment => this == DrillDownMetric.views ? 'views' : 'clicks';

  /// Parses the route segment; falls back to [DrillDownMetric.views] for any
  /// unknown value so a bad deep link never crashes.
  static DrillDownMetric fromRoute(String? segment) =>
      segment == 'clicks' ? DrillDownMetric.clicks : DrillDownMetric.views;

  /// Detail-screen title.
  String get title =>
      this == DrillDownMetric.views ? 'Shop views' : 'Product clicks';

  /// What the daily series rows count.
  String get unitLabel => this == DrillDownMetric.views ? 'views' : 'clicks';
}

/// A today-vs-yesterday KPI plus its weekly context.
class TrendMetric {
  const TrendMetric({
    required this.today,
    this.yesterday = 0,
    this.changePct = 0,
    this.thisWeek = 0,
    this.lastWeek = 0,
    this.weekChangePct = 0,
  });

  final int today;
  final int yesterday;

  /// Percentage change of [today] against [yesterday] (backend-computed).
  final double changePct;
  final int thisWeek;
  final int lastWeek;

  /// Percentage change of [thisWeek] against [lastWeek] (backend-computed).
  final double weekChangePct;

  factory TrendMetric.fromJson(Map<String, dynamic> json) => TrendMetric(
    today: _asInt(json['today']),
    yesterday: _asInt(json['yesterday']),
    changePct: _asDouble(json['change_pct']),
    thisWeek: _asInt(json['this_week']),
    lastWeek: _asInt(json['last_week']),
    weekChangePct: _asDouble(json['week_change_pct']),
  );

  bool get isGrowing => changePct > 0;
  bool get isDeclining => changePct < 0;
  bool get isFlat => changePct == 0;

  /// Display-ready delta vs yesterday: `+40.0%` / `-12.5%` / `0%`.
  String get changeLabel => _pctLabel(changePct);

  /// Display-ready delta vs last week: `+16.7%` / `-4.0%` / `0%`.
  String get weekChangeLabel => _pctLabel(weekChangePct);

  static String _pctLabel(double pct) {
    if (pct == 0) return '0%';
    final sign = pct > 0 ? '+' : '-';
    return '$sign${pct.abs().toStringAsFixed(1)}%';
  }
}

/// Headline KPI cards: views / clicks / interactions.
class InsightsOverview {
  const InsightsOverview({
    required this.views,
    required this.clicks,
    required this.interactions,
    this.generatedAt,
  });

  final TrendMetric views;
  final TrendMetric clicks;
  final TrendMetric interactions;

  /// ISO timestamp of the backend computation (null when absent).
  final String? generatedAt;

  factory InsightsOverview.fromJson(Map<String, dynamic> json) =>
      InsightsOverview(
        views: TrendMetric.fromJson(_asMap(json['views'])),
        clicks: TrendMetric.fromJson(_asMap(json['clicks'])),
        interactions: TrendMetric.fromJson(_asMap(json['interactions'])),
        generatedAt: json['generated_at'] as String?,
      );

  /// True when the shop has had ANY recorded activity in the window.
  bool get hasActivity =>
      views.today > 0 ||
      views.thisWeek > 0 ||
      clicks.thisWeek > 0 ||
      interactions.thisWeek > 0;
}

/// One point of a daily time series (shop views or product clicks).
class InsightsPoint {
  const InsightsPoint({required this.date, required this.value});

  final String date;
  final int value;

  /// [valueKey] is the backend's metric key for that series — `views` for the
  /// shop-view series, `clicks` for the product-click series.
  factory InsightsPoint.fromJson(Map<String, dynamic> json, String valueKey) =>
      InsightsPoint(
        date: json['date'] as String? ?? '',
        value: _asInt(json[valueKey]),
      );
}

/// A product driving customer interest in the window.
class TopProduct {
  const TopProduct({
    required this.shopProductId,
    required this.sku,
    required this.views,
  });

  final int shopProductId;
  final String sku;
  final int views;

  factory TopProduct.fromJson(Map<String, dynamic> json) => TopProduct(
    shopProductId: _asInt(json['shop_product_id']),
    sku: json['sku'] as String? ?? '',
    views: _asInt(json['views']),
  );

  /// Falls back to the id when the catalog row has no SKU — never invents one.
  String get label => sku.trim().isEmpty ? 'Product #$shopProductId' : sku;
}

/// What customers typed before landing on this shop.
class SearchTerm {
  const SearchTerm({required this.query, required this.count});

  final String query;
  final int count;

  factory SearchTerm.fromJson(Map<String, dynamic> json) => SearchTerm(
    query: json['query'] as String? ?? '',
    count: _asInt(json['count']),
  );
}

/// Customer interactions by type.
class InteractionBreakdown {
  const InteractionBreakdown({
    this.callViews = 0,
    this.messages = 0,
    this.ratings = 0,
    this.periodDays = 0,
  });

  final int callViews;
  final int messages;
  final int ratings;
  final int periodDays;

  factory InteractionBreakdown.fromJson(Map<String, dynamic> json) =>
      InteractionBreakdown(
        callViews: _asInt(json['call_views']),
        messages: _asInt(json['messages']),
        ratings: _asInt(json['ratings']),
        periodDays: _asInt(json['period_days']),
      );

  int get total => callViews + messages + ratings;
  bool get isEmpty => total == 0;
}

/// One device class share of the shop's views.
class DeviceShare {
  const DeviceShare({
    required this.label,
    required this.count,
    required this.share,
  });

  final String label;
  final int count;

  /// Fraction of total views for this device class (0..1).
  final double share;

  /// Display-ready percentage: `75%` / `12.5%`.
  String get shareLabel => share == 0
      ? '0%'
      : '${(share * 100).toStringAsFixed((share * 100) % 1 == 0 ? 0 : 1)}%';
}

/// Which devices customers use to discover the shop.
class DeviceBreakdown {
  const DeviceBreakdown({this.counts = const <String, int>{}});

  /// Raw backend map: `android` / `ios` / `web` / `unknown` → view count.
  final Map<String, int> counts;

  factory DeviceBreakdown.fromJson(Map<String, dynamic> json) =>
      DeviceBreakdown(
        counts: {
          for (final entry in json.entries) entry.key: _asInt(entry.value),
        },
      );

  int get total => counts.values.fold(0, (sum, value) => sum + value);
  bool get isEmpty => total == 0;

  /// Shares sorted by volume (highest first) for a stable list order.
  List<DeviceShare> get shares {
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sum = total;
    return [
      for (final entry in entries)
        DeviceShare(
          label: deviceLabel(entry.key),
          count: entry.value,
          share: sum == 0 ? 0 : entry.value / sum,
        ),
    ];
  }

  /// Human-readable device label; unknown keys fall back to the raw value.
  static String deviceLabel(String key) => switch (key.toLowerCase()) {
    'android' => 'Android',
    'ios' => 'iOS',
    'web' => 'Web',
    'unknown' => 'Unknown',
    _ => key,
  };
}

/// Shop-view volume for one hour of the day (peak-hours intelligence).
class HourlyPoint {
  const HourlyPoint({required this.hour, required this.views});

  final int hour;
  final int views;

  factory HourlyPoint.fromJson(Map<String, dynamic> json) => HourlyPoint(
    hour: _asInt(json['hour']),
    views: _asInt(json['views']),
  );

  /// `09:00` — zero-padded 24h label.
  String get label => '${hour.toString().padLeft(2, '0')}:00';
}

/// How recently the shop's stock was updated.
class InventoryFreshness {
  const InventoryFreshness({
    this.score = 0,
    this.totalProducts = 0,
    this.fresh = 0,
    this.stale = 0,
  });

  /// Percentage of products synced in the last 24h (0..100).
  final double score;
  final int totalProducts;
  final int fresh;
  final int stale;

  factory InventoryFreshness.fromJson(Map<String, dynamic> json) =>
      InventoryFreshness(
        score: _asDouble(json['score']),
        totalProducts: _asInt(json['total_products']),
        fresh: _asInt(json['fresh']),
        stale: _asInt(json['stale']),
      );

  bool get hasProducts => totalProducts > 0;

  /// 0..1 progress fraction for a progress indicator.
  double get scoreFraction => (score / 100).clamp(0.0, 1.0);

  /// `75%` / `62.5%` — trailing zeros dropped.
  String get scoreLabel => '${score.toStringAsFixed(score % 1 == 0 ? 0 : 1)}%';
}

/// The complete Reports / Insights payload (one backend call).
class InsightsBundle {
  const InsightsBundle({
    required this.overview,
    this.viewSeries = const <InsightsPoint>[],
    this.clickSeries = const <InsightsPoint>[],
    this.topProducts = const <TopProduct>[],
    this.topSearches = const <SearchTerm>[],
    this.interactions = const InteractionBreakdown(),
    this.devices = const DeviceBreakdown(),
    this.hourly = const <HourlyPoint>[],
    this.freshness = const InventoryFreshness(),
  });

  final InsightsOverview overview;
  final List<InsightsPoint> viewSeries;
  final List<InsightsPoint> clickSeries;
  final List<TopProduct> topProducts;
  final List<SearchTerm> topSearches;
  final InteractionBreakdown interactions;
  final DeviceBreakdown devices;
  final List<HourlyPoint> hourly;
  final InventoryFreshness freshness;

  factory InsightsBundle.fromJson(Map<String, dynamic> json) => InsightsBundle(
    overview: InsightsOverview.fromJson(_asMap(json['overview'])),
    viewSeries: _asMapList(json['views_timeseries'])
        .map((row) => InsightsPoint.fromJson(row, 'views'))
        .toList(growable: false),
    clickSeries: _asMapList(json['clicks_timeseries'])
        .map((row) => InsightsPoint.fromJson(row, 'clicks'))
        .toList(growable: false),
    topProducts: _asMapList(
      json['top_products'],
    ).map(TopProduct.fromJson).toList(growable: false),
    topSearches: _asMapList(
      json['top_searches'],
    ).map(SearchTerm.fromJson).toList(growable: false),
    interactions: InteractionBreakdown.fromJson(_asMap(json['interactions'])),
    devices: DeviceBreakdown.fromJson(_asMap(json['devices'])),
    hourly: _asMapList(
      json['hourly'],
    ).map(HourlyPoint.fromJson).toList(growable: false),
    freshness: InventoryFreshness.fromJson(_asMap(json['freshness'])),
  );

  /// True when the shop has any customer activity to report. Drives the
  /// honest "no customer activity yet" empty state.
  bool get hasActivity =>
      overview.hasActivity ||
      topProducts.isNotEmpty ||
      topSearches.isNotEmpty ||
      devices.total > 0;

  /// The busiest hour of the day, or null when there is nothing to show.
  HourlyPoint? get peakHour {
    HourlyPoint? peak;
    for (final point in hourly) {
      if (point.views <= 0) continue;
      if (peak == null || point.views > peak.views) peak = point;
    }
    return peak;
  }

  /// Highest per-day view count (used to scale the trend bars).
  int get peakDailyViews => viewSeries.fold(
    0,
    (max, point) => point.value > max ? point.value : max,
  );
}

// ── Business insights (live shop snapshot) ───────────────────────────────────
// Contract: `GET /api/v1/shopkeeper/shops/{id}/insights`
// (`backend/app/api/routes/shopkeeper_portal.py` ->
// `shopkeeper_service.business_insights`). Unlike the analytics sections above,
// these cards describe the shop's CURRENT state — listings, inventory, offers
// and profile — computed server-side from the live database rather than from
// the trailing window. Nothing is fabricated here either: a card the backend
// did not send is simply absent, and a card with nothing to report is skipped
// instead of rendering a meaningless zero.

/// How urgent one insight card is, as classified by the backend.
enum BusinessInsightStatus {
  healthy,
  warning,
  critical,
  info;

  /// Parses the backend classification; an unknown value falls back to [info]
  /// so a future server-side status never breaks an older client.
  static BusinessInsightStatus fromName(Object? raw) =>
      switch (raw?.toString().toLowerCase()) {
        'healthy' => BusinessInsightStatus.healthy,
        'warning' => BusinessInsightStatus.warning,
        'critical' => BusinessInsightStatus.critical,
        _ => BusinessInsightStatus.info,
      };

  String get label => switch (this) {
    BusinessInsightStatus.healthy => 'Healthy',
    BusinessInsightStatus.warning => 'Needs attention',
    BusinessInsightStatus.critical => 'Action needed',
    BusinessInsightStatus.info => 'For review',
  };
}

/// One data-driven insight card.
///
/// Stable ids: `top_products`, `low_stock`, `stale_inventory`,
/// `search_visibility`, `offers_performance`, `profile_completeness`.
class BusinessInsightCard {
  const BusinessInsightCard({
    required this.id,
    required this.title,
    this.description = '',
    this.status = BusinessInsightStatus.info,
    this.metrics = const <String, dynamic>{},
    this.items = const <Map<String, dynamic>>[],
    this.suggestion,
  });

  final String id;
  final String title;
  final String description;
  final BusinessInsightStatus status;

  /// Card-specific metric map, exactly as the backend computed it.
  final Map<String, dynamic> metrics;

  /// The rows that triggered the card (products / offers / missing fields).
  final List<Map<String, dynamic>> items;

  /// The backend's next-step copy; null when there is nothing to act on.
  final String? suggestion;

  factory BusinessInsightCard.fromJson(Map<String, dynamic> json) =>
      BusinessInsightCard(
        id: (json['id'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        status: BusinessInsightStatus.fromName(json['status']),
        metrics: _asMap(json['metrics']),
        items: _asMapList(json['items']),
        suggestion: json['suggestion']?.toString(),
      );

  int metricInt(String key) => _asInt(metrics[key]);

  double metricDouble(String key) => _asDouble(metrics[key]);

  /// True when the card has something worth rendering. The backend sends every
  /// card on every call, so a quiet shop would otherwise show a wall of zeros.
  bool get hasData =>
      items.isNotEmpty ||
      suggestion != null ||
      status == BusinessInsightStatus.warning ||
      status == BusinessInsightStatus.critical;
}

/// Display mapping for [BusinessInsightCard]: keeps the model a plain parse of
/// the backend payload while giving the UI the card-specific lines it renders.
/// Every number below is read from the backend-sent [BusinessInsightCard
/// .metrics] — none is derived or estimated on the client.
extension BusinessInsightCardPresentation on BusinessInsightCard {
  /// The line the card leads with, or null when the backend sent no number
  /// worth stating (e.g. a visibility percentage for an empty catalog).
  String? get headline => switch (id) {
    'top_products' => metricInt('total_products') == 0
        ? null
        : '${metricInt('ranked_count')} of ${metricInt('active_products')} '
              'active listings',
    'low_stock' => metricInt('count') == 0
        ? null
        : '${metricInt('count')} at or below threshold',
    'stale_inventory' => metricInt('count') == 0
        ? null
        : '${metricInt('count')} untouched for '
              '${metricInt('oldest_stale_days')}+ days',
    'search_visibility' => metricInt('total_products') == 0
        ? null
        : '${_percentLabel(metricDouble('visibility_percentage'))} of '
              'listings visible in search',
    'offers_performance' => metricInt('total_offers') == 0
        ? null
        : '${metricInt('active_offers')} active of '
              '${metricInt('total_offers')} offers',
    'profile_completeness' => metricInt('total_fields') == 0
        ? null
        : '${_percentLabel(metricDouble('completeness_percentage'))} complete '
              '(${metricInt('completed_fields')}/'
              '${metricInt('total_fields')} fields)',
    _ => null,
  };

  /// Compact supporting numbers, card-specific and backend-derived.
  List<String> get summaryLines => switch (id) {
    'top_products' => <String>[
      '${metricInt('total_products')} listings · '
          '${metricInt('active_products')} active',
    ],
    'low_stock' => <String>[
      '${_percentLabel(metricDouble('percentage'))} of your catalog · '
          '${metricInt('total_gap_units')} units to restock',
    ],
    'stale_inventory' => <String>[
      '${_percentLabel(metricDouble('percentage'))} of in-stock listings · '
          'oldest ${metricInt('oldest_stale_days')} days',
    ],
    'search_visibility' => <String>[
      '${metricInt('visible_products')} of ${metricInt('total_products')} '
          'visible · ${metricInt('products_without_images')} without an image',
    ],
    'offers_performance' => <String>[
      '${metricInt('draft_offers')} drafts · '
          '${metricInt('expiring_soon')} expiring soon · '
          '${_percentLabel(metricDouble('offer_coverage_percentage'))} '
          'catalog coverage',
    ],
    'profile_completeness' => <String>[
      '${metricInt('missing_fields_count')} fields still missing',
    ],
    _ => const <String>[],
  };

  /// Short lines for the rows the card flagged (max 5, in the backend's order).
  List<String> get itemLines {
    final lines = <String>[];
    for (final row in items) {
      if (lines.length == 5) break;
      final label =
          (row['name'] ?? row['title'] ?? row['label'] ?? row['field'] ?? '')
              .toString();
      final detail = _itemDetail(row);
      final line = detail.isEmpty ? label : '$label · $detail';
      if (line.trim().isNotEmpty) lines.add(line);
    }
    return List<String>.unmodifiable(lines);
  }

  String _itemDetail(Map<String, dynamic> row) => switch (id) {
    'low_stock' =>
      '${_asInt(row['quantity'])} left, restock ${_asInt(row['gap'])}',
    'stale_inventory' => '${_asInt(row['days_since_update'])} days untouched',
    'top_products' => '${_asInt(row['quantity'])} units in stock',
    'offers_performance' => '${_asInt(row['product_count'])} products',
    _ => '',
  };
}

/// `75%` / `62.5%` — trailing zeros dropped.
String _percentLabel(double value) =>
    '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}%';

/// The complete business-insights payload (`GET .../shops/{id}/insights`).
class BusinessInsightsBundle {
  const BusinessInsightsBundle({
    this.shopName = '',
    this.generatedAt,
    this.insights = const <BusinessInsightCard>[],
  });

  final String shopName;
  final DateTime? generatedAt;
  final List<BusinessInsightCard> insights;

  factory BusinessInsightsBundle.fromJson(Map<String, dynamic> json) =>
      BusinessInsightsBundle(
        shopName: (_asMap(json['shop'])['name'] ?? '').toString(),
        generatedAt: DateTime.tryParse((json['generated_at'] ?? '').toString()),
        insights: _asMapList(
          json['insights'],
        ).map(BusinessInsightCard.fromJson).toList(growable: false),
      );

  /// The card with [id], or null when the backend did not send it.
  BusinessInsightCard? byId(String id) {
    for (final card in insights) {
      if (card.id == id) return card;
    }
    return null;
  }

  /// Only the cards with something to report, in the backend's order.
  List<BusinessInsightCard> get actionable =>
      insights.where((card) => card.hasData).toList(growable: false);

  bool get isEmpty => insights.isEmpty;
}