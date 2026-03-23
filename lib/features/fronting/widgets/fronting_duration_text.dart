import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/extensions/duration_extensions.dart';

/// A widget that displays a live-updating duration since [startTime].
///
/// Updates every second, showing formatted duration like "1h 23m 45s".
class FrontingDurationText extends StatefulWidget {
  const FrontingDurationText({
    super.key,
    required this.startTime,
    this.style,
    this.rounded = false,
  });

  final DateTime startTime;
  final TextStyle? style;
  /// When true, drops seconds once past 1 minute (e.g. "5m" instead of "5m 12s").
  final bool rounded;

  @override
  State<FrontingDurationText> createState() => _FrontingDurationTextState();
}

class _FrontingDurationTextState extends State<FrontingDurationText> {
  late Timer _timer;
  late Duration _elapsed;

  @override
  void initState() {
    super.initState();
    _elapsed = DateTime.now().difference(widget.startTime);
    _startTimer();
  }

  void _startTimer() {
    // Tick every second while under a minute, then every 60s.
    final interval = _elapsed.inMinutes < 1
        ? const Duration(seconds: 1)
        : const Duration(seconds: 60);
    _timer = Timer.periodic(interval, (_) {
      final newElapsed = DateTime.now().difference(widget.startTime);
      // Switch to minute-based timer once we cross the 1m boundary.
      if (_elapsed.inMinutes < 1 && newElapsed.inMinutes >= 1) {
        _timer.cancel();
        _startTimer();
      }
      setState(() => _elapsed = newElapsed);
    });
  }

  @override
  void didUpdateWidget(FrontingDurationText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startTime != widget.startTime) {
      _elapsed = DateTime.now().difference(widget.startTime);
      _timer.cancel();
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.rounded
        ? _elapsed.toRoundedString()
        : _elapsed.toShortString();
    return Text(
      text,
      style: widget.style ??
          Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
    );
  }
}
