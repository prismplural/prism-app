import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/services/media/media_hydrator.dart';
import 'package:prism_plurality/core/services/media/media_providers.dart';

/// Surfaces [MediaHydrator]'s "a blob just landed" events to the Riverpod tree
/// so [mediaFileProvider] instances can invalidate themselves and repaint when
/// their image finishes downloading in the background.
///
/// Kept as a thin StreamProvider over the hydrator's broadcast stream; the
/// per-image filtering (does this event match *my* media id?) happens in
/// `mediaFileProvider` to avoid a family-keyed provider per media id here.
final mediaAvailableProvider = StreamProvider<MediaAvailableEvent>((ref) {
  return ref.watch(mediaHydratorProvider).events;
});
