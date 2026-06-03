import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/database/database_providers.dart';

final memberAvatarImageDataProvider = StreamProvider.autoDispose
    .family<Uint8List?, String>((ref, memberId) {
      return ref.watch(membersDaoProvider).watchAvatarImageData(memberId);
    });
