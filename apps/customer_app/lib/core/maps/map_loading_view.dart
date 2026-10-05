import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_theme.dart';
import '../widgets/skeletons.dart';
import '../widgets/slow_load_notice.dart';

/// The map loading state, shared by every [MapAdapter] implementation.
///
/// WHY A SKELETON AND NOT A SPINNER
/// --------------------------------
/// A map's load is the one wait where a bare spinner is actively misleading:
/// the customer cannot tell "the map is coming" from "the map failed and this
/// tile is all you get". The shimmer blocks outline the map's frame and the
/// controls that land on top of it, and [SlowLoadNotice] bounds the wait so a
/// slow SDK init is explained rather than merely endured.
///
/// Defined once and used by BOTH GoogleMapAdapter and StubMapAdapter: a build
/// with a MAPS_API_KEY and one without must not produce two different loading
/// experiences, or a bug hunt starts by wondering which adapter was in play.
class MapLoadingView extends StatelessWidget {
  final String message;

  const MapLoadingView({super.key, this.message = 'Loading map...'});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Semantics(
              // Decoration, not content: a screen reader must not announce the
              // placeholder blocks as if they were the map.
              label: message,
              excludeSemantics: true,
              child: Shimmer.fromColors(
                baseColor: Colors.grey.shade300,
                highlightColor: Colors.grey.shade100,
                child: const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SkeletonBox(height: 44, radius: 10),
                      SizedBox(height: AppSpacing.md),
                      Expanded(child: SkeletonBox(height: 0, radius: 12)),
                      SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(child: SkeletonBox(height: 40, radius: 8)),
                          SizedBox(width: AppSpacing.sm),
                          Expanded(child: SkeletonBox(height: 40, radius: 8)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.md),
            child: Center(
              // No retry: re-initialising the map SDK belongs to the view, and
              // a button here that could not do it would be a dead control.
              child: SlowLoadNotice(
                message: 'The map is taking longer to load.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
