import 'package:flutter/material.dart';

import '../../core/network_image.dart';
import '../../core/theme.dart';
import '../../data/models.dart';

class ChannelLogo extends StatelessWidget {
  const ChannelLogo({
    super.key,
    required this.channel,
    required this.allowInsecure,
    this.size = 48,
    this.radius = 12,
  });

  final Channel channel;
  final bool allowInsecure;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    final url = channel.logoUrl;
    // Decode logos at the size they are actually drawn at. Channel images are
    // often much larger than the 34-54px tile, and a big source list can
    // otherwise exhaust the image cache (or Android's memory budget) until
    // previously loaded logos start failing to decode.
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).ceil();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: size,
        height: size,
        color: colors.surface1,
        alignment: Alignment.center,
        child: url == null || url.isEmpty
            ? _Fallback(size: size, color: colors.subtext0)
            : Image(
                image: ResizeImage(
                  MojacNetworkImage(url, allowInsecure: allowInsecure),
                  width: pixels,
                  height: pixels,
                  policy: ResizeImagePolicy.fit,
                ),
                width: size,
                height: size,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) {
                  return _Fallback(size: size, color: colors.subtext0);
                },
              ),
      ),
    );
  }
}

/// The channel number as a small pill, drawn over the corner of a logo.
///
/// Channels used to spend a whole text column on the number, which made the
/// artwork noticeably smaller for no real benefit. Overlaying it gives the
/// logo the full cell and keeps the number discoverable.
class ChannelNumberBadge extends StatelessWidget {
  const ChannelNumberBadge({super.key, required this.number});

  final String number;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: colors.crust.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        number,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.text,
              fontSize: 9.5,
              height: 1.1,
              fontWeight: FontWeight.w700,
              fontFeatures: const <FontFeature>[
                FontFeature.tabularFigures(),
              ],
            ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.live_tv_rounded, size: size * 0.5, color: color);
  }
}
