import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:ogg_caf_converter/ogg_caf_converter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'package:prism_plurality/features/settings/services/voice_lab_support.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

class VoiceLabScreen extends StatefulWidget {
  const VoiceLabScreen({super.key});

  @override
  State<VoiceLabScreen> createState() => _VoiceLabScreenState();
}

class _VoiceLabScreenState extends State<VoiceLabScreen> {
  static const _fixtureOggAssetPath = 'assets/audio/voice_lab_fixture.ogg';
  static const _fixtureCafAssetPath = 'assets/audio/voice_lab_fixture.caf';
  static const _autoVoiceLabRepro = bool.fromEnvironment(
    'AUTO_VOICE_LAB_REPRO',
  );

  final AudioRecorder _recorder = AudioRecorder();
  final OggCafConverter _converter = OggCafConverter();
  final SoLoud _soLoud = SoLoud.instance;
  final List<double> _amplitudeSamples = <double>[];
  final List<String> _debugLogEntries = <String>[];

  VoiceLabCapability? _capability;
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  StreamSubscription<StreamSoundEvent>? _soundEventSubscription;
  Timer? _elapsedTimer;
  Timer? _playbackPollTimer;
  Stopwatch? _stopwatch;
  AudioSource? _loadedSource;
  SoundHandle? _activeHandle;
  String? _recordingPath;
  Uint8List? _sourceBytes;
  Uint8List? _normalizedBytes;
  Uint8List? _fixtureOggBytes;
  Uint8List? _fixtureCafBytes;
  Duration _elapsed = Duration.zero;
  Duration _playbackPosition = Duration.zero;
  Duration _playbackDuration = Duration.zero;
  bool _isLoading = true;
  bool _isRecording = false;
  bool _isProcessing = false;
  bool _isPlaying = false;
  bool _isPlaybackReady = false;
  bool _ownsSoLoudInstance = false;
  String _status = 'Checking recorder and playback support...';
  String? _error;
  String? _sourceContainer;
  String? _normalizedContainer;
  String? _fixtureOggContainer;
  String? _fixtureCafContainer;
  int _sourceByteCount = 0;
  String _lastPlaybackPath = 'Not used yet';
  String _lastPlaybackTarget = 'Not used yet';
  String _lastBufferSize = 'Unavailable';
  String _lastMetadataSummary = 'Unavailable';
  bool _autoReproStarted = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _playbackPollTimer?.cancel();
    final amplitudeSubscription = _amplitudeSubscription;
    _amplitudeSubscription = null;
    unawaited(amplitudeSubscription?.cancel() ?? Future<void>.value());

    final shouldDeinitSoLoud = _ownsSoLoudInstance && _soLoud.isInitialized;
    if (shouldDeinitSoLoud) {
      _soLoud.deinit();
      _ownsSoLoudInstance = false;
    }

    unawaited(_disposeAsync(skipSoLoudCleanup: shouldDeinitSoLoud));
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final opusSupported = !kIsWeb
          ? await _recorder.isEncoderSupported(AudioEncoder.opus)
          : false;
      _appendLog('Recorder Opus support reported as $opusSupported.');

      final capability = buildVoiceLabCapability(
        isWeb: kIsWeb,
        platform: defaultTargetPlatform,
        opusRecordingSupported: opusSupported,
      );
      _appendLog('Capability summary: ${capability.summary}');

      var playbackReady = false;
      try {
        if (!_soLoud.isInitialized) {
          await _soLoud.init();
          _ownsSoLoudInstance = true;
        }
        playbackReady = true;
        _appendLog('SoLoud initialized successfully.');
      } catch (e, st) {
        debugPrint('[VoiceLab] SoLoud init failed: $e\n$st');
        _appendLog('SoLoud init failed: $e');
      }

      await _loadBundledFixtures();

      if (!mounted) {
        return;
      }

      setState(() {
        _capability = capability;
        _isPlaybackReady = playbackReady;
        _isLoading = false;
        _status = capability.isSupported
            ? capability.summary
            : (capability.unsupportedReason ?? capability.summary);
      });

      if (_autoVoiceLabRepro &&
          playbackReady &&
          capability.isSupported &&
          !_autoReproStarted) {
        _autoReproStarted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_runAutoRepro());
        });
      }
    } catch (e, st) {
      debugPrint('[VoiceLab] initialize failed: $e\n$st');
      _appendLog('Voice Lab initialization failed: $e');
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _error = '$e';
        _status = 'Failed to initialize the voice lab.';
      });
    }
  }

  Future<void> _runAutoRepro() async {
    _appendLog('AUTO_VOICE_LAB_REPRO starting.');
    await _loadBundledCafFixture();
    if (!mounted) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await _playRecording();
  }

  void _appendLog(String message) {
    final now = DateTime.now();
    final timestamp =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${(now.millisecond ~/ 10).toString().padLeft(2, '0')}';
    final entry = '[$timestamp] $message';
    debugPrint('[VoiceLab] $entry');

    void mutate() {
      _debugLogEntries.insert(0, entry);
      if (_debugLogEntries.length > 80) {
        _debugLogEntries.removeLast();
      }
    }

    if (mounted) {
      setState(mutate);
    } else {
      mutate();
    }
  }

  Future<void> _loadBundledFixtures() async {
    try {
      final oggData = await rootBundle.load(_fixtureOggAssetPath);
      _fixtureOggBytes = oggData.buffer.asUint8List(
        oggData.offsetInBytes,
        oggData.lengthInBytes,
      );
      _fixtureOggContainer = detectVoiceLabContainer(_fixtureOggBytes!);
      _appendLog(
        'Loaded bundled Ogg fixture (${formatVoiceLabBytes(_fixtureOggBytes!.length)}, $_fixtureOggContainer).',
      );
    } catch (e) {
      _appendLog('Bundled Ogg fixture unavailable: $e');
    }

    try {
      final cafData = await rootBundle.load(_fixtureCafAssetPath);
      _fixtureCafBytes = cafData.buffer.asUint8List(
        cafData.offsetInBytes,
        cafData.lengthInBytes,
      );
      _fixtureCafContainer = detectVoiceLabContainer(_fixtureCafBytes!);
      _appendLog(
        'Loaded bundled CAF fixture (${formatVoiceLabBytes(_fixtureCafBytes!.length)}, $_fixtureCafContainer).',
      );
    } catch (e) {
      _appendLog('Bundled CAF fixture unavailable: $e');
    }
  }

  Future<void> _startRecording() async {
    final capability = _capability;
    if (capability == null || !capability.isSupported || _isRecording) {
      return;
    }

    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        setState(() {
          _error = 'Microphone permission is required before recording.';
          _status = 'Microphone permission was not granted.';
        });
        return;
      }

      await _disposeLoadedAudio();

      final tempDir = await getTemporaryDirectory();
      final fileName =
          'voice_lab_${DateTime.now().microsecondsSinceEpoch}.${capability.outputFileExtension}';
      _recordingPath = '${tempDir.path}/$fileName';
      _appendLog(
        'Starting recorder -> $_recordingPath (${capability.sourceContainerLabel}).',
      );

      const config = RecordConfig(
        encoder: AudioEncoder.opus,
        bitRate: 32000,
        sampleRate: 48000,
        numChannels: 1,
      );

      _amplitudeSamples.clear();
      _elapsed = Duration.zero;
      _playbackPosition = Duration.zero;
      _playbackDuration = Duration.zero;
      _sourceBytes = null;
      _normalizedBytes = null;
      _sourceContainer = null;
      _normalizedContainer = null;
      _sourceByteCount = 0;

      await _recorder.start(config, path: _recordingPath!);
      _stopwatch = Stopwatch()..start();
      _elapsedTimer?.cancel();
      _elapsedTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!mounted || _stopwatch == null) {
          return;
        }
        setState(() {
          _elapsed = _stopwatch!.elapsed;
        });
      });
      await _amplitudeSubscription?.cancel();
      _amplitudeSubscription = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amplitude) {
            _amplitudeSamples.add(amplitude.current);
          });

      setState(() {
        _error = null;
        _isRecording = true;
        _isProcessing = false;
        _status = 'Recording ${capability.sourceContainerLabel}...';
      });
    } catch (e, st) {
      debugPrint('[VoiceLab] start recording failed: $e\n$st');
      _appendLog('Start recording failed: $e');
      await _cleanupRecordingFile();
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$e';
        _isRecording = false;
        _status = 'Could not start recording.';
      });
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _status = 'Stopping recorder and normalizing bytes...';
    });

    try {
      final outputPath = await _recorder.stop();
      await _amplitudeSubscription?.cancel();
      _amplitudeSubscription = null;
      _elapsedTimer?.cancel();
      _stopwatch?.stop();

      final path = outputPath ?? _recordingPath;
      if (path == null) {
        throw StateError('Recorder returned no output path.');
      }

      final rawBytes = await File(path).readAsBytes();
      final normalizedBytes = _capability!.needsCafToOggRemux
          ? await _converter.convertCafToOggInMemory(input: path)
          : rawBytes;
      _appendLog(
        'Recorder output: ${formatVoiceLabBytes(rawBytes.length)} '
        '(${detectVoiceLabContainer(rawBytes)}).',
      );
      _appendLog(
        'Normalized bytes: ${formatVoiceLabBytes(normalizedBytes.length)} '
        '(${detectVoiceLabContainer(normalizedBytes)}).',
      );

      await _cleanupRecordingFile();

      if (!mounted) {
        return;
      }

      setState(() {
        _isRecording = false;
        _isProcessing = false;
        _sourceBytes = rawBytes;
        _normalizedBytes = normalizedBytes;
        _sourceByteCount = rawBytes.length;
        _sourceContainer = detectVoiceLabContainer(rawBytes);
        _normalizedContainer = detectVoiceLabContainer(normalizedBytes);
        _status =
            'Recorded ${formatVoiceLabBytes(normalizedBytes.length)} of ${_normalizedContainer ?? 'audio'}.';
      });
    } catch (e, st) {
      debugPrint('[VoiceLab] stop recording failed: $e\n$st');
      _appendLog('Stop recording failed: $e');
      await _cleanupRecordingFile();
      if (!mounted) {
        return;
      }
      setState(() {
        _isRecording = false;
        _isProcessing = false;
        _error = '$e';
        _status = 'Recording failed while finalizing.';
      });
    }
  }

  Future<void> _playRecording() async {
    final bytes = _normalizedBytes;
    if (bytes == null || !_isPlaybackReady) {
      return;
    }

    await _playBytes(
      bytes,
      label: 'current sample',
      containerLabel: _normalizedContainer,
    );
  }

  Future<void> _playBundledOggFixture() async {
    final bytes = _fixtureOggBytes;
    if (bytes == null || !_isPlaybackReady) {
      return;
    }

    await _playBytes(
      bytes,
      label: 'bundled Ogg fixture',
      containerLabel: _fixtureOggContainer,
    );
  }

  Future<void> _loadBundledCafFixture() async {
    final cafBytes = _fixtureCafBytes;
    if (cafBytes == null) {
      return;
    }

    String? tempPath;
    try {
      await _disposeLoadedAudio();
      if (!mounted) {
        return;
      }

      setState(() {
        _isProcessing = true;
        _error = null;
        _status = 'Converting bundled CAF fixture...';
      });

      final tempDir = await getTemporaryDirectory();
      tempPath =
          '${tempDir.path}/voice_lab_fixture_${DateTime.now().microsecondsSinceEpoch}.caf';
      await File(tempPath).writeAsBytes(cafBytes, flush: true);
      _appendLog(
        'Wrote bundled CAF fixture to $tempPath (${formatVoiceLabBytes(cafBytes.length)}).',
      );

      final normalizedBytes = await _converter.convertCafToOggInMemory(
        input: tempPath,
      );
      final normalizedContainer = detectVoiceLabContainer(normalizedBytes);
      _appendLog(
        'Bundled CAF fixture converted to ${formatVoiceLabBytes(normalizedBytes.length)} '
        '($normalizedContainer).',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isProcessing = false;
        _sourceBytes = cafBytes;
        _normalizedBytes = normalizedBytes;
        _sourceByteCount = cafBytes.length;
        _sourceContainer =
            _fixtureCafContainer ?? detectVoiceLabContainer(cafBytes);
        _normalizedContainer = normalizedContainer;
        _status = 'Loaded bundled CAF fixture into the current sample slot.';
      });
    } catch (e, st) {
      debugPrint('[VoiceLab] bundled CAF fixture conversion failed: $e\n$st');
      _appendLog('Bundled CAF fixture conversion failed: $e');
      if (!mounted) {
        return;
      }
      setState(() {
        _isProcessing = false;
        _error = '$e';
        _status = 'Bundled CAF fixture conversion failed.';
      });
    } finally {
      if (tempPath != null) {
        try {
          final file = File(tempPath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
    }
  }

  Future<void> _playBytes(
    Uint8List bytes, {
    required String label,
    String? containerLabel,
  }) async {
    try {
      await _disposeLoadedAudio();

      final playbackMode = chooseVoiceLabPlaybackMode(bytes);
      final resolvedContainer =
          containerLabel ?? detectVoiceLabContainer(bytes);
      late final AudioSource source;
      late final SoundHandle handle;
      late final Duration duration;
      _appendLog(
        'Preparing $label: ${formatVoiceLabBytes(bytes.length)} '
        '($resolvedContainer) via ${describeVoiceLabPlaybackMode(playbackMode)}.',
      );

      if (playbackMode == VoiceLabPlaybackMode.bufferStream) {
        _lastMetadataSummary =
            'Disabled: flutter_soloud callback lifetime crash';
        _appendLog(
          'Native metadata/buffering callbacks disabled for $label due to flutter_soloud callback lifetime crash.',
        );
        source = _soLoud.setBufferStream(
          format: BufferType.auto,
          bufferingTimeNeeds: 0.05,
          maxBufferSizeDuration: const Duration(seconds: 30),
        );
        _soundEventSubscription = source.soundEvents.listen((event) {
          _appendLog(
            'Sound event for $label: ${event.event.name} handle=${event.handle.id}.',
          );
        });
        handle = _soLoud.play(source);
        _appendLog(
          'Started buffered source for $label with handle=${handle.id}.',
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        _soLoud.addAudioDataStream(source, bytes);
        final bufferSize = _soLoud.getBufferSize(source);
        _lastBufferSize = formatVoiceLabBytes(bufferSize);
        _appendLog('Buffered ${formatVoiceLabBytes(bufferSize)} for $label.');
        _soLoud.setDataIsEnded(source);
        _appendLog('Marked buffered data as ended for $label.');
        duration = _soLoud.getLength(source);
      } else {
        _lastBufferSize = 'N/A for loadMem';
        _lastMetadataSummary = 'Not requested for loadMem playback';
        source = await _soLoud.loadMem(
          'voice_lab_${DateTime.now().microsecondsSinceEpoch}.ogg',
          bytes,
        );
        _soundEventSubscription = source.soundEvents.listen((event) {
          _appendLog(
            'Sound event for $label: ${event.event.name} handle=${event.handle.id}.',
          );
        });
        handle = _soLoud.play(source);
        duration = _soLoud.getLength(source);
      }

      _loadedSource = source;
      _activeHandle = handle;
      _lastPlaybackPath = describeVoiceLabPlaybackMode(playbackMode);
      _lastPlaybackTarget = label;
      _appendLog(
        'Started $label with handle=${handle.id}; reported length ${_formatDuration(duration)}.',
      );
      _playbackPollTimer?.cancel();
      _playbackPollTimer = Timer.periodic(const Duration(milliseconds: 150), (
        _,
      ) {
        final currentHandle = _activeHandle;
        if (!mounted || currentHandle == null) {
          return;
        }
        if (!_soLoud.getIsValidVoiceHandle(currentHandle)) {
          _playbackPollTimer?.cancel();
          _appendLog('Handle ${currentHandle.id} for $label became invalid.');
          setState(() {
            _isPlaying = false;
            _playbackPosition = Duration.zero;
            _status = 'Playback finished for $label.';
          });
          return;
        }
        setState(() {
          _playbackPosition = _soLoud.getPosition(currentHandle);
        });
      });

      setState(() {
        _error = null;
        _isPlaying = true;
        _playbackDuration = duration;
        _playbackPosition = Duration.zero;
        _status =
            'Playing $label ($resolvedContainer) via ${describeVoiceLabPlaybackMode(playbackMode)}.';
      });
    } catch (e, st) {
      debugPrint('[VoiceLab] playback failed: $e\n$st');
      _appendLog('Playback failed for $label: $e');
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$e';
        _isPlaying = false;
        _status = 'Playback failed.';
      });
    }
  }

  Future<void> _stopPlayback() async {
    final handle = _activeHandle;
    _playbackPollTimer?.cancel();
    _appendLog(
      handle == null
          ? 'Stop playback requested with no active handle.'
          : 'Stopping handle ${handle.id}.',
    );
    if (handle != null && _soLoud.isInitialized) {
      try {
        await _soLoud.stop(handle);
      } catch (e, st) {
        debugPrint('[VoiceLab] stop playback failed: $e\n$st');
        _appendLog('Stop playback failed: $e');
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _isPlaying = false;
      _playbackPosition = Duration.zero;
      _status = 'Playback stopped.';
    });
  }

  Future<void> _reset() async {
    _appendLog('Resetting Voice Lab state.');
    if (_isRecording) {
      try {
        await _recorder.cancel();
      } catch (e, st) {
        debugPrint('[VoiceLab] cancel recording failed: $e\n$st');
        _appendLog('Cancel recording during reset failed: $e');
      }
    }

    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _elapsedTimer?.cancel();
    _playbackPollTimer?.cancel();
    _stopwatch?.stop();
    await _cleanupRecordingFile();
    await _disposeLoadedAudio();

    if (!mounted) {
      return;
    }
    setState(() {
      _amplitudeSamples.clear();
      _elapsed = Duration.zero;
      _playbackPosition = Duration.zero;
      _playbackDuration = Duration.zero;
      _isRecording = false;
      _isProcessing = false;
      _isPlaying = false;
      _sourceBytes = null;
      _normalizedBytes = null;
      _sourceByteCount = 0;
      _sourceContainer = null;
      _normalizedContainer = null;
      _error = null;
      _lastPlaybackPath = 'Not used yet';
      _lastPlaybackTarget = 'Not used yet';
      _lastBufferSize = 'Unavailable';
      _lastMetadataSummary = 'Unavailable';
      _status = _capability?.summary ?? 'Voice lab reset.';
    });
  }

  Future<void> _disposeLoadedAudio() async {
    _playbackPollTimer?.cancel();
    await _soundEventSubscription?.cancel();
    _soundEventSubscription = null;

    final handle = _activeHandle;
    if (handle != null && _soLoud.isInitialized) {
      try {
        await _soLoud.stop(handle);
      } catch (_) {}
    }
    _activeHandle = null;

    final source = _loadedSource;
    if (source != null && _soLoud.isInitialized) {
      try {
        await _soLoud.disposeSource(source);
      } catch (_) {}
    }
    _loadedSource = null;
  }

  Future<void> _cleanupRecordingFile() async {
    final path = _recordingPath;
    _recordingPath = null;
    if (path == null) {
      return;
    }

    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e, st) {
      debugPrint('[VoiceLab] cleanup failed for $path: $e\n$st');
      _appendLog('Cleanup failed for $path: $e');
    }
  }

  Future<void> _disposeAsync({bool skipSoLoudCleanup = false}) async {
    try {
      if (_isRecording) {
        await _recorder.cancel();
      }
    } catch (_) {}
    await _cleanupRecordingFile();
    if (skipSoLoudCleanup) {
      await _soundEventSubscription?.cancel();
      _soundEventSubscription = null;
      _activeHandle = null;
      _loadedSource = null;
    } else {
      await _disposeLoadedAudio();
    }
    await _recorder.dispose();
    if (_ownsSoLoudInstance && _soLoud.isInitialized) {
      _soLoud.deinit();
      _ownsSoLoudInstance = false;
    }
  }

  Future<void> _copyDebugLog() async {
    final buffer = StringBuffer()
      ..writeln('Voice Lab')
      ..writeln('Status: $_status')
      ..writeln('Error: ${_error ?? 'none'}')
      ..writeln('Playback target: $_lastPlaybackTarget')
      ..writeln('Playback path: $_lastPlaybackPath')
      ..writeln('Buffer size: $_lastBufferSize')
      ..writeln('Metadata: $_lastMetadataSummary')
      ..writeln()
      ..writeln('Debug log:');

    for (final entry in _debugLogEntries.reversed) {
      buffer.writeln(entry);
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) {
      return;
    }
    PrismToast.show(context, message: 'Voice Lab logs copied');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final capability = _capability;

    return PrismPageScaffold(
      topBar: const PrismTopBar(title: 'Voice Lab', showBackButton: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          PrismSurface(
            fillColor: theme.colorScheme.primaryContainer.withValues(
              alpha: 0.35,
            ),
            borderColor: theme.colorScheme.primary.withValues(alpha: 0.2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Debug-only voice pipeline spike',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(_status, style: theme.textTheme.bodyMedium),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          PrismSectionCard(
            padding: const EdgeInsets.all(16),
            child: _isLoading
                ? Center(
                    child: PrismSpinner(color: theme.colorScheme.primary),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Capability',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _VoiceLabInfoRow(
                        label: 'Recorder path',
                        value: capability?.summary ?? 'Unavailable',
                      ),
                      const Divider(height: 16),
                      _VoiceLabInfoRow(
                        label: 'Playback engine',
                        value: _isPlaybackReady
                            ? 'SoLoud initialized'
                            : 'Playback init failed',
                      ),
                      const Divider(height: 16),
                      _VoiceLabInfoRow(
                        label: 'Source container',
                        value:
                            capability?.sourceContainerLabel ?? 'Unavailable',
                      ),
                      const Divider(height: 16),
                      _VoiceLabInfoRow(
                        label: 'Normalized container',
                        value:
                            capability?.normalizedContainerLabel ??
                            'Unavailable',
                      ),
                      const Divider(height: 16),
                      _VoiceLabInfoRow(
                        label: 'Bundled Ogg fixture',
                        value: _fixtureOggBytes == null
                            ? 'Unavailable'
                            : '${formatVoiceLabBytes(_fixtureOggBytes!.length)} ($_fixtureOggContainer)',
                      ),
                      const Divider(height: 16),
                      _VoiceLabInfoRow(
                        label: 'Bundled CAF fixture',
                        value: _fixtureCafBytes == null
                            ? 'Unavailable'
                            : '${formatVoiceLabBytes(_fixtureCafBytes!.length)} ($_fixtureCafContainer)',
                      ),
                      if (capability?.unsupportedReason != null) ...[
                        const Divider(height: 16),
                        _VoiceLabInfoRow(
                          label: 'Why unavailable',
                          value: capability!.unsupportedReason!,
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          PrismSectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Controls',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: PrismButton(
                    label: _isRecording ? 'Recording...' : 'Record',
                    icon: AppIcons.microphone,
                    tone: PrismButtonTone.filled,
                    expanded: true,
                    enabled:
                        !_isLoading &&
                        !_isRecording &&
                        !_isProcessing &&
                        (capability?.isSupported ?? false),
                    onPressed: _startRecording,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: PrismButton(
                    label: _isProcessing ? 'Stopping...' : 'Stop recording',
                    icon: AppIcons.stopRounded,
                    tone: PrismButtonTone.outlined,
                    expanded: true,
                    enabled: _isRecording,
                    onPressed: _stopRecording,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: PrismButton(
                    label: _isPlaying ? 'Playing...' : 'Play sample',
                    icon: AppIcons.playArrowRounded,
                    tone: PrismButtonTone.outlined,
                    expanded: true,
                    enabled:
                        !_isRecording &&
                        !_isProcessing &&
                        !_isPlaying &&
                        _normalizedBytes != null &&
                        _isPlaybackReady,
                    onPressed: _playRecording,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: PrismButton(
                    label: 'Stop playback',
                    icon: AppIcons.stopRounded,
                    tone: PrismButtonTone.outlined,
                    expanded: true,
                    enabled: _isPlaying,
                    onPressed: _stopPlayback,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: PrismButton(
                    label: 'Load CAF fixture',
                    icon: AppIcons.download,
                    tone: PrismButtonTone.outlined,
                    expanded: true,
                    enabled:
                        !_isLoading &&
                        !_isRecording &&
                        !_isProcessing &&
                        !_isPlaying &&
                        _fixtureCafBytes != null,
                    onPressed: _loadBundledCafFixture,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: PrismButton(
                    label: 'Play Ogg fixture',
                    icon: AppIcons.playArrowRounded,
                    tone: PrismButtonTone.outlined,
                    expanded: true,
                    enabled:
                        !_isLoading &&
                        !_isRecording &&
                        !_isProcessing &&
                        !_isPlaying &&
                        _fixtureOggBytes != null &&
                        _isPlaybackReady,
                    onPressed: _playBundledOggFixture,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: PrismButton(
                    label: 'Reset',
                    icon: AppIcons.deleteForever,
                    tone: PrismButtonTone.outlined,
                    expanded: true,
                    enabled:
                        _isRecording ||
                        _isPlaying ||
                        _normalizedBytes != null ||
                        _sourceBytes != null ||
                        _error != null,
                    onPressed: _reset,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PrismSectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recording details',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _VoiceLabInfoRow(
                  label: 'Elapsed',
                  value: _formatDuration(_elapsed),
                ),
                const Divider(height: 16),
                _VoiceLabInfoRow(
                  label: 'Amplitude samples',
                  value: '${_amplitudeSamples.length}',
                ),
                const Divider(height: 16),
                _VoiceLabInfoRow(
                  label: 'Recorded bytes',
                  value: _sourceBytes == null
                      ? 'Not recorded yet'
                      : formatVoiceLabBytes(_sourceByteCount),
                ),
                const Divider(height: 16),
                _VoiceLabInfoRow(
                  label: 'Recorded container',
                  value: _sourceContainer ?? 'Unknown',
                ),
                const Divider(height: 16),
                _VoiceLabInfoRow(
                  label: 'Normalized bytes',
                  value: _normalizedBytes == null
                      ? 'Not available yet'
                      : formatVoiceLabBytes(_normalizedBytes!.length),
                ),
                const Divider(height: 16),
                _VoiceLabInfoRow(
                  label: 'Normalized container',
                  value: _normalizedContainer ?? 'Unknown',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PrismSectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Playback details',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _VoiceLabInfoRow(
                  label: 'Playback position',
                  value: _formatDuration(_playbackPosition),
                ),
                const Divider(height: 16),
                _VoiceLabInfoRow(
                  label: 'Playback length',
                  value: _formatDuration(_playbackDuration),
                ),
                const Divider(height: 16),
                _VoiceLabInfoRow(
                  label: 'Playback path',
                  value: _lastPlaybackPath,
                ),
                const Divider(height: 16),
                _VoiceLabInfoRow(
                  label: 'Playback target',
                  value: _lastPlaybackTarget,
                ),
                const Divider(height: 16),
                _VoiceLabInfoRow(label: 'Buffer size', value: _lastBufferSize),
                const Divider(height: 16),
                _VoiceLabInfoRow(
                  label: 'Metadata',
                  value: _lastMetadataSummary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PrismSectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Debug log',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: PrismButton(
                    label: 'Copy logs',
                    icon: AppIcons.copy,
                    enabled: _debugLogEntries.isNotEmpty,
                    onPressed: () { _copyDebugLog(); },
                  ),
                ),
                const SizedBox(height: 12),
                if (_debugLogEntries.isEmpty)
                  Text(
                    'No debug events yet.',
                    style: theme.textTheme.bodyMedium,
                  )
                else
                  for (
                    var i = 0;
                    i < _debugLogEntries.length && i < 20;
                    i++
                  ) ...[
                    SelectableText(
                      _debugLogEntries[i],
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                    if (i < 19 && i < _debugLogEntries.length - 1)
                      const Divider(height: 12),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final centiseconds = (duration.inMilliseconds.remainder(1000) ~/ 10)
        .toString()
        .padLeft(2, '0');
    return '$minutes:$seconds.$centiseconds';
  }
}

class _VoiceLabInfoRow extends StatelessWidget {
  const _VoiceLabInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 132,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}
