import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

class SyncToastListener extends ConsumerStatefulWidget {
  const SyncToastListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SyncToastListener> createState() => _SyncToastListenerState();
}

class _SyncToastListenerState extends ConsumerState<SyncToastListener> {
  String? _lastError;

  @override
  Widget build(BuildContext context) {
    ref.listen<SyncStatus>(syncStatusProvider, (previous, next) {
      // Show a toast when a new error appears.
      if (next.lastError != null && next.lastError != _lastError) {
        _lastError = next.lastError;
        _showToast(
          () => PrismToast.error(
            context,
            message: 'Sync error: ${next.lastError}',
          ),
        );
      } else if (next.lastError == null) {
        _lastError = null;
      }
    });

    return widget.child;
  }

  void _showToast(VoidCallback show) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final route = ModalRoute.of(context);
      if (!mounted || (route != null && !route.isCurrent)) {
        return;
      }
      show();
    });
  }
}
