import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/utils/remote_image_fetcher.dart';

/// Maps a [RemoteImageFetchError] to a user-facing toast message. [fallback]
/// covers reasons without a dedicated message (unparseable / non-https URL), so
/// each call site keeps its own generic wording.
String remoteImageFetchMessage(
  AppLocalizations l10n,
  RemoteImageFetchError? error, {
  required String fallback,
}) {
  switch (error) {
    case RemoteImageFetchError.notAnImage:
      return l10n.mediaFetchNotAnImage;
    case RemoteImageFetchError.tooLarge:
      return l10n.mediaFetchTooLarge;
    case RemoteImageFetchError.unreachable:
    case RemoteImageFetchError.blockedHost:
      return l10n.mediaFetchUnreachable;
    case RemoteImageFetchError.invalidUrl:
    case null:
      return fallback;
  }
}
