import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/services/media/media_heal_responder.dart';

void main() {
  // Fakes / observation.
  late Set<String> held;
  late Set<String> present;
  late ReUploadResult uploadResult;
  Object? batchError;
  Object? uploadError;
  late List<String> uploaded; // re-upload calls
  late List<String> announced; // media_uploaded broadcasts
  late int jitterCalls;

  MediaHealResponder build({int maxReUploadsPerWindow = 20}) {
    return MediaHealResponder(
      jitter: () async => jitterCalls++,
      maxReUploadsPerWindow: maxReUploadsPerWindow,
      clockMs: () => 1000000, // fixed clock → one window
      holdsBlob: (id) async => held.contains(id),
      batchExists: (ids) async {
        if (batchError != null) throw batchError!;
        return ids.where(present.contains).toList();
      },
      reUpload: (id) async {
        if (uploadError != null) throw uploadError!;
        uploaded.add(id);
        return uploadResult;
      },
      sendMediaUploaded: (id) async => announced.add(id),
    );
  }

  setUp(() {
    held = {};
    present = {};
    uploadResult = ReUploadResult.committed;
    batchError = null;
    uploadError = null;
    uploaded = [];
    announced = [];
    jitterCalls = 0;
  });

  test('does not respond to a blob it does not hold', () async {
    await build().onMediaRequest('x');
    expect(jitterCalls, 0);
    expect(uploaded, isEmpty);
    expect(announced, isEmpty);
  });

  test('aborts if the relay already holds it after jitter', () async {
    held = {'x'};
    present = {'x'};
    await build().onMediaRequest('x');
    expect(jitterCalls, 1, reason: 'jitter runs before the re-check');
    expect(uploaded, isEmpty);
    expect(announced, isEmpty);
  });

  test('re-uploads and announces when committed', () async {
    held = {'x'};
    present = {};
    uploadResult = ReUploadResult.committed;
    await build().onMediaRequest('x');
    expect(uploaded, ['x']);
    expect(announced, ['x']);
  });

  test('inProgress (202) re-upload does NOT announce', () async {
    held = {'x'};
    uploadResult = ReUploadResult.inProgress;
    await build().onMediaRequest('x');
    expect(uploaded, ['x']);
    expect(announced, isEmpty, reason: 'another responder is mid-upload');
  });

  test('failed re-upload does NOT announce', () async {
    held = {'x'};
    uploadResult = ReUploadResult.failed;
    await build().onMediaRequest('x');
    expect(uploaded, ['x']);
    expect(announced, isEmpty);
  });

  test('batch-exists error → quiet no-op (no upload, no announce)', () async {
    held = {'x'};
    batchError = Exception('transient');
    await build().onMediaRequest('x');
    expect(uploaded, isEmpty);
    expect(announced, isEmpty);
  });

  test('a transient upload error is swallowed (no announce)', () async {
    held = {'x'};
    uploadError = Exception('network');
    await build().onMediaRequest('x');
    expect(announced, isEmpty);
  });

  test('self-rate-limits re-uploads within the window', () async {
    held = {'a', 'b', 'c'};
    final responder = build(maxReUploadsPerWindow: 2);
    await responder.onMediaRequest('a');
    await responder.onMediaRequest('b');
    await responder.onMediaRequest('c'); // over the per-window cap
    expect(uploaded, ['a', 'b'], reason: 'third re-upload is throttled');
    expect(announced, ['a', 'b']);
  });
}
