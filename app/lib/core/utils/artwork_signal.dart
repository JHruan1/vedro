import 'package:flutter/foundation.dart';

/// Canonical artwork cache refresh signal shared between `state/` (producer)
/// and `widgets/vedro_artwork.dart` (consumer), keeping the dependency graph
/// strictly acyclic (`state -> core`, `widgets -> core`).
class VedroArtworkSignal {
  VedroArtworkSignal._();

  /// Bumped whenever server session or proxy transport becomes ready so any
  /// posters that failed during cold start or proxy warm-up reload in-place.
  static final ValueNotifier<int> refreshEpoch = ValueNotifier<int>(0);

  static void notifyRefresh() {
    refreshEpoch.value = refreshEpoch.value + 1;
  }
}
