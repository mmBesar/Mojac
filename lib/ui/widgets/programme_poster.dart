import 'package:flutter/material.dart';

import '../../core/network_image.dart';
import '../../core/theme.dart';
import '../../data/models.dart';

/// A poster/thumbnail for an XMLTV programme. Falls back to a neutral tile when
/// the guide has no icon or the image cannot be loaded.
///
/// Guides often advertise a poster and a still. If the first URL fails, the
/// widget walks to the next one instead of giving up on the whole programme.
class ProgrammePoster extends StatefulWidget {
  const ProgrammePoster({
    super.key,
    required this.programme,
    required this.allowInsecure,
    this.width = 48,
    this.height = 64,
    this.radius = 8,
  });

  final Programme programme;
  final bool allowInsecure;
  final double width;
  final double height;
  final double radius;

  @override
  State<ProgrammePoster> createState() => _ProgrammePosterState();
}

class _ProgrammePosterState extends State<ProgrammePoster> {
  int _index = 0;

  @override
  void didUpdateWidget(ProgrammePoster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.programme != widget.programme) {
      _index = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    final images = widget.programme.images;
    final url = _index < images.length ? images[_index].trim() : '';
    // XMLTV artwork is frequently full HD. Decode only what the poster slot
    // needs so a guide full of programmes cannot blow the image cache.
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth =
        widget.width.isFinite ? (widget.width * ratio).ceil() : 1080;
    final cacheHeight = (widget.height * ratio).ceil();
    final fallback = _Fallback(
      width: widget.width,
      height: widget.height,
      color: colors.overlay0,
      background: colors.surface1,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: url.isEmpty
            ? fallback
            : Image(
                image: ResizeImage(
                  MojacNetworkImage(
                    url,
                    allowInsecure: widget.allowInsecure,
                  ),
                  width: cacheWidth,
                  height: cacheHeight,
                  policy: ResizeImagePolicy.fit,
                ),
                width: widget.width,
                height: widget.height,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) {
                  if (_index + 1 < images.length) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() => _index += 1);
                      }
                    });
                  }
                  return fallback;
                },
              ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({
    required this.width,
    required this.height,
    required this.color,
    required this.background,
  });

  final double width;
  final double height;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: background),
      child: SizedBox(
        width: width,
        height: height,
        child: Icon(
          Icons.movie_filter_rounded,
          color: color,
          size: width.isFinite && width < 60 ? 18 : 28,
        ),
      ),
    );
  }
}
