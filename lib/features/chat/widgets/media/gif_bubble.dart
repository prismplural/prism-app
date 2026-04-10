import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:prism_plurality/features/chat/services/klipy_service.dart';
import 'package:prism_plurality/features/chat/widgets/media/expired_media.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Displays a GIF attachment inside a chat message bubble as a looping
/// silent MP4 video.
///
/// Uses the Klipy CDN for both preview images and MP4 playback. When GIF
/// search is disabled via [gifEnabled], shows a placeholder without making
/// any network requests.
class GifBubble extends StatefulWidget {
  const GifBubble({
    super.key,
    required this.sourceUrl,
    required this.previewUrl,
    this.width,
    this.height,
    this.contentDescription,
    this.gifEnabled = true,
  });

  /// Klipy MP4 URL (full quality for playback).
  final String sourceUrl;

  /// Klipy preview URL (smaller, for loading state).
  final String previewUrl;

  /// Width from API dimensions.
  final double? width;

  /// Height from API dimensions.
  final double? height;

  /// Accessibility text (stored in blurhash field).
  final String? contentDescription;

  /// From gifSearchEnabledProvider. When false, show placeholder instead
  /// of fetching from CDN.
  final bool gifEnabled;

  @override
  State<GifBubble> createState() => _GifBubbleState();
}

class _GifBubbleState extends State<GifBubble> with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _hasVideoError = false;
  bool _hasPreviewError = false;
  bool _isVideoInitialized = false;
  bool _isVisible = true;

  /// Whether the user explicitly started playback (reduced-motion mode).
  bool _manuallyStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.gifEnabled && KlipyService.isValidGifUrl(widget.sourceUrl)) {
      _initVideoPlayer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || _controller == null) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _controller?.pause();
      case AppLifecycleState.resumed:
        if (_isVisible && _isVideoInitialized && _shouldAutoPlay()) {
          _controller?.play();
        }
    }
  }

  @override
  void didUpdateWidget(GifBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceUrl != widget.sourceUrl) {
      _controller?.dispose();
      _controller = null;
      _isVideoInitialized = false;
      _hasVideoError = false;
      _hasPreviewError = false;
      _manuallyStarted = false;
      if (widget.gifEnabled && KlipyService.isValidGifUrl(widget.sourceUrl)) {
        _initVideoPlayer();
      }
    } else if (!oldWidget.gifEnabled && widget.gifEnabled) {
      if (KlipyService.isValidGifUrl(widget.sourceUrl)) {
        _initVideoPlayer();
      }
    }
  }

  @override
  void deactivate() {
    _controller?.pause();
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  bool _shouldAutoPlay() {
    if (!mounted || !_isVisible) return false;
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    return !disableAnimations || _manuallyStarted;
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    if (!mounted || _controller == null) return;
    if (info.visibleFraction < 0.1) {
      _isVisible = false;
      _controller?.pause();
    } else if (info.visibleFraction > 0.5) {
      _isVisible = true;
      if (_isVideoInitialized && _shouldAutoPlay()) {
        _controller?.play();
      }
    }
  }

  Future<void> _initVideoPlayer() async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.sourceUrl),
    );
    _controller = controller;

    try {
      await controller.setLooping(true);
      await controller.setVolume(0.0);
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _isVideoInitialized = true);
      if (_shouldAutoPlay()) {
        await controller.play();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _hasVideoError = true);
      }
    }
  }

  void _onPlayTapped() {
    if (_controller == null || !_isVideoInitialized) return;
    setState(() => _manuallyStarted = true);
    _controller!.play();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = screenWidth * 0.70;
    const maxHeight = 300.0;

    // Compute constrained size from source dimensions
    double effectiveWidth = (widget.width != null && widget.width! > 0)
        ? widget.width!
        : 240.0;
    double effectiveHeight = (widget.height != null && widget.height! > 0)
        ? widget.height!
        : 180.0;

    // Scale down to fit max width
    if (effectiveWidth > maxWidth) {
      final scale = maxWidth / effectiveWidth;
      effectiveWidth = maxWidth;
      effectiveHeight = effectiveHeight * scale;
    }
    // Scale down to fit max height
    if (effectiveHeight > maxHeight) {
      final scale = maxHeight / effectiveHeight;
      effectiveHeight = maxHeight;
      effectiveWidth = effectiveWidth * scale;
    }

    // URL validation — show expired state for invalid URLs
    if (!KlipyService.isValidGifUrl(widget.sourceUrl) ||
        !KlipyService.isValidGifUrl(widget.previewUrl)) {
      return const ExpiredMedia();
    }

    return VisibilityDetector(
      key: Key('gif_bubble_${widget.sourceUrl}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: Semantics(
        label: 'GIF: ${widget.contentDescription ?? 'GIF'}',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: effectiveWidth,
            height: effectiveHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildContent(context, theme, effectiveWidth, effectiveHeight),
                // "GIF" label overlay in top-left
                Positioned(
                  top: 6,
                  left: 6,
                  child: _GifLabel(theme: theme),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ThemeData theme,
    double w,
    double h,
  ) {
    final warmSurface = theme.brightness == Brightness.dark
        ? AppColors.charcoalSurface
        : AppColors.parchmentElevated;

    // GIFs disabled — show placeholder, no CDN fetch
    if (!widget.gifEnabled) {
      return Container(
        width: w,
        height: h,
        color: warmSurface,
        child: Center(
          child: Text(
            'GIF',
            style: theme.textTheme.titleMedium?.copyWith(
              color:
                  theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    // Error state — video init failed and no preview fallback
    if (_hasVideoError && _hasPreviewError) {
      return _ErrorPlaceholder(width: w, height: h);
    }

    final disableAnimations = MediaQuery.of(context).disableAnimations;

    // Reduced motion: show static preview with play button overlay
    if (disableAnimations && !_manuallyStarted) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _buildPreviewImage(w, h, warmSurface),
          Center(
            child: GestureDetector(
              onTap: _isVideoInitialized ? _onPlayTapped : null,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  AppIcons.playCircle,
                  size: 28,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Video ready — show video player
    if (_isVideoInitialized && _controller != null) {
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _controller!.value.size.width,
          height: _controller!.value.size.height,
          child: VideoPlayer(_controller!),
        ),
      );
    }

    // Loading state — show preview image while video loads
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildPreviewImage(w, h, warmSurface),
        if (!_hasVideoError)
          Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPreviewImage(double w, double h, Color fallbackColor) {
    if (_hasPreviewError) {
      return Container(width: w, height: h, color: fallbackColor);
    }

    return Image.network(
      widget.previewUrl,
      width: w,
      height: h,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _hasPreviewError = true);
        });
        return Container(width: w, height: h, color: fallbackColor);
      },
    );
  }
}

class _GifLabel extends StatelessWidget {
  const _GifLabel({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'GIF',
        style: theme.textTheme.bodySmall?.copyWith(
          color: Colors.white.withValues(alpha: 0.9),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1.0,
        ),
      ),
    );
  }
}

class _ErrorPlaceholder extends StatelessWidget {
  const _ErrorPlaceholder({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: width,
      height: height,
      color: theme.brightness == Brightness.dark
          ? AppColors.charcoalSurface
          : AppColors.parchmentElevated,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIcons.imageBroken,
              size: 28,
              color:
                  theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 4),
            Text(
              'GIF unavailable',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.5),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
