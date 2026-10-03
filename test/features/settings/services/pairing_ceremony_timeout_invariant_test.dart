import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level invariants for the split initiator ceremony.
///
/// The three core calls
/// (`verifyInitiatorConfirmationResumable` → `uploadPairingSnapshotResumable` →
/// `completeInitiatorResumableCeremony`) own their own waits. Core's budgets are
/// deliberately long — a legacy single-`PUT` upload can run to 300s and a
/// lease-aware ceremony can run to its four-hour cap — so any Dart-side deadline
/// shorter than those would preempt core and break pairing on slow links. The
/// same reasoning applies to `cancelPairingCeremony`, which must be allowed to
/// do its best-effort relay cleanup.
///
/// These checks are textual on purpose: they catch a future edit that
/// re-introduces a wrapper deadline without needing a live engine.
void main() {
  String readSource(String path) => File(path).readAsStringSync();

  /// Strips line comments so a commented-out call cannot satisfy a matcher.
  String uncommented(String source) => source
      .split('\n')
      .map((l) => l.replaceFirst(RegExp(r'\s*//.*$'), ''))
      .join('\n');

  test('the sheet never wraps pairing ceremony calls in a Dart deadline', () {
    final source = uncommented(
      readSource('lib/features/settings/widgets/setup_device_sheet.dart'),
    );

    expect(
      source.contains('.timeout('),
      isFalse,
      reason:
          'setup_device_sheet.dart must not apply a .timeout() to the pairing '
          'ceremony calls: core owns those waits (300s single-PUT budget, up to '
          '4h for a lease-aware ceremony). Keep short UI responsiveness timers '
          'separate from operation cancellation.',
    );

    // The split calls are reached through the controller, never directly.
    expect(
      source.contains('uploadPairingSnapshot('),
      isFalse,
      reason:
          'the app must use the split ceremony '
          '(uploadPairingSnapshotResumable) rather than the pre-split '
          'single-call upload.',
    );
    expect(
      source.contains('completeInitiatorCeremony('),
      isFalse,
      reason:
          'credential release must go through '
          'completeInitiatorResumableCeremony, which core refuses until the '
          'snapshot is durably published.',
    );
  });

  test('the controller never wraps a core ceremony call in a deadline', () {
    final source = uncommented(
      readSource(
        'lib/features/settings/services/pairing_snapshot_upload_controller.dart',
      ),
    );

    expect(
      source.contains('.timeout('),
      isFalse,
      reason:
          'the controller must not impose a Dart deadline on verify/upload/'
          'complete or on cancelPairingCeremony.',
    );

    // Cancellation must not await the in-flight upload future: it can take up
    // to 300s to unwind.
    expect(
      source.contains('await upload.future') && source.contains('cancel()'),
      isTrue,
      reason: 'sanity: the controller still awaits its own upload in run()',
    );
  });

  test('run() only reaches credential release after a successful upload', () {
    final source = uncommented(
      readSource(
        'lib/features/settings/services/pairing_snapshot_upload_controller.dart',
      ),
    ).replaceAll(RegExp(r'\s+'), '');

    // Scope the check to run()'s body: the upload call itself lives in the
    // `_startUpload` helper, but the ordering that matters is inside run().
    final runStart = source.indexOf('Future<bool>run(');
    // Anchor run()'s end on the next member's signature (a code anchor, since
    // line comments were stripped above).
    final runEnd = source.indexOf('Future<void>cancel()');
    expect(runStart, greaterThan(-1));
    expect(runEnd, greaterThan(runStart));
    final body = source.substring(runStart, runEnd);

    final verifyIndex = body.indexOf(
      '_api.verifyInitiatorConfirmationResumable(',
    );
    final startUploadIndex = body.indexOf('_startUpload()');
    final applyIndex = body.indexOf('_applyUploadResult(');
    final completeIndex = body.indexOf(
      '_api.completeInitiatorResumableCeremony(',
    );

    expect(verifyIndex, greaterThan(-1));
    expect(startUploadIndex, greaterThan(verifyIndex));
    expect(applyIndex, greaterThan(startUploadIndex));
    // Credential release comes last, and only after the upload resolved.
    expect(completeIndex, greaterThan(applyIndex));
    // A generation guard must follow the credential-release call and precede the
    // completed phase, so a cancelled or superseded run can never report a
    // success that mutates the caller's UI.
    final guardAfterComplete = body.indexOf(
      'if(!_isCurrent(generation))returnfalse;',
      completeIndex,
    );
    expect(guardAfterComplete, greaterThan(completeIndex));
    expect(
      body.indexOf('PairingCeremonyPhase.completed', guardAfterComplete),
      greaterThan(guardAfterComplete),
      reason:
          'credential release must be followed by a run-generation check so a '
          'cancelled or superseded run cannot report completion',
    );
  });

  test('the sheet drains the PIN synchronously before any setState or await', () {
    final source = uncommented(
      readSource('lib/features/settings/widgets/setup_device_sheet.dart'),
    );

    // P1 security/lifecycle invariant. `_completeInitiator` is the single funnel
    // for both the `_validatedPin` pre-flight path and the `passwordEntry`
    // fallback. Its first `setState` moves to the confirming step, which
    // unmounts `_InitiatorPinView`; that view's `dispose()` zeroes the buffer it
    // owns. The drain therefore has to come first — unconditionally, before any
    // `setState` or `await`.
    final methodStart = source.indexOf(
      'Future<void> _completeInitiator(PinBuffer pin) async {',
    );
    expect(
      methodStart,
      greaterThan(-1),
      reason: '_completeInitiator must keep taking the PinBuffer owner',
    );

    // The body ends at the next member's signature (a code anchor, since line
    // comments were stripped above).
    final methodEnd = source.indexOf(
      'void _onCeremonyPhase(PairingCeremonyPhase phase) {',
      methodStart,
    );
    expect(methodEnd, greaterThan(methodStart));
    final body = source.substring(methodStart, methodEnd);

    final drainIndex = body.indexOf('pin.consumeBytesAndClear()');
    expect(
      drainIndex,
      greaterThan(-1),
      reason:
          '_completeInitiator must drain its PinBuffer: the view that owns it '
          'is unmounted by the confirming step',
    );

    final firstSetState = body.indexOf('setState(');
    final firstAwait = body.indexOf('await ');
    expect(firstSetState, greaterThan(drainIndex));
    expect(firstAwait, greaterThan(drainIndex));

    // Zeroization stays in the caller's hands: the drained buffer is overwritten
    // in the method's own finally block, and handed to run() as bytes rather
    // than as a buffer the controller would have to consume later.
    expect(
      body.contains('zeroBytesBestEffort(pinBytes)'),
      isTrue,
      reason: 'the drained PIN bytes must be overwritten on every exit path',
    );
    // Whitespace-insensitive: the formatter may lay the call out on one line.
    final compact = body.replaceAll(RegExp(r'\s+'), '');
    expect(
      compact.contains('ceremony.run(pinBytes:pinBytes'),
      isTrue,
      reason:
          'run() must receive the already-drained bytes, not the view-owned '
          'buffer',
    );
  });

  test('the controller never consumes or zeroes the caller-owned PIN buffer', () {
    final source = uncommented(
      readSource(
        'lib/features/settings/services/pairing_snapshot_upload_controller.dart',
      ),
    );
    // Scoped to run()'s body so the assertion cannot be satisfied elsewhere.
    final runStart = source.indexOf('Future<bool> run(');
    final runEnd = source.indexOf('Future<void> cancel()', runStart);
    expect(runStart, greaterThan(-1));
    expect(runEnd, greaterThan(runStart));
    final body = source.substring(runStart, runEnd);

    expect(
      source.contains('consumeBytesAndClear'),
      isFalse,
      reason:
          'the pre-drain belongs to the sheet; the controller must receive '
          'bytes that are already drained',
    );
    expect(
      body.contains('zeroBytesBestEffort(pinBytes)'),
      isFalse,
      reason:
          'the caller owns the PIN buffer and overwrites it in its own finally; '
          'zeroing it here would race the caller and hide a lifetime bug',
    );
  });

  test('cancel issues cancelPairingCeremony without awaiting the upload', () {
    final source = uncommented(
      readSource(
        'lib/features/settings/services/pairing_snapshot_upload_controller.dart',
      ),
    );

    // Scope the check to cancel()'s body: `await upload.future` legitimately
    // appears in run(), so a file-wide assertion proves nothing about cancel.
    final cancelStart = source.indexOf('Future<void> cancel()');
    final cancelEnd = source.indexOf('void dispose()', cancelStart);
    expect(cancelStart, greaterThan(-1));
    expect(cancelEnd, greaterThan(cancelStart));
    final body = source.substring(cancelStart, cancelEnd);

    expect(
      body.contains('await upload.future'),
      isFalse,
      reason:
          'cancel must not await the in-flight upload future: it can take up to '
          'five minutes to unwind',
    );
    expect(
      body.contains('upload'),
      isFalse,
      reason: 'cancel must not touch the upload completer at all',
    );
    expect(
      body.contains('_api.cancelPairingCeremony('),
      isTrue,
      reason: 'cancel still has to issue the core cancel',
    );
  });

  test('byte progress stays determinate once a total has been observed', () {
    final source = uncommented(
      readSource(
        'lib/features/settings/services/pairing_snapshot_upload_controller.dart',
      ),
    );
    // One consistent policy for both transports: the total alone decides, so a
    // resolved single-PUT downgrade cannot tear the bar back to indeterminate.
    expect(
      source.contains('bool get showByteProgress => _bytesTotal != null;'),
      isTrue,
      reason:
          'byte progress must key off the observed total for both transports, '
          'not off the resolved transport',
    );
  });
}
