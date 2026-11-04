import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';

/// A slim, glowing progress bar for the programme that is on air right now.
///
/// It ticks once a second on its own so the channel list shows real progress
/// between the app's thirty-second data refreshes instead of jumping in large
/// steps. The widget is tiny, so a handful of visible tiles cost very little.
class LiveProgressBar extends StatefulWidget {
  const LiveProgressBar({
    super.key,
    required this.programme,
    this.height = 4,
    this.showRemaining = true,
  });

  final Programme programme;
  final double height;
  final bool showRemaining;

  @override
  State<LiveProgressBar> createState() => _LiveProgressBarState();
}

class _LiveProgressBarState extends State<LiveProgressBar> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant LiveProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.programme != widget.programme) {
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    if (!widget.programme.stop.isAfter(DateTime.now())) {
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      if (!DateTime.now().isBefore(widget.programme.stop)) {
        _timer?.cancel();
      }
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.mojacColors;
    final now = DateTime.now();
    final remaining = widget.programme.stop.difference(now);
    final fraction = widget.programme.progressAt(now);

    final bar = TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: fraction),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final filled = (value * width).clamp(0.0, width);
            return SizedBox(
              height: widget.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surface1,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    start: 0,
                    top: 0,
                    bottom: 0,
                    width: filled,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: LinearGradient(
                          colors: <Color>[
                            colors.accent.withValues(alpha: 0.55),
                            colors.accent,
                          ],
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: colors.accent.withValues(alpha: 0.35),
                            blurRadius: 5,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (filled > 3)
                    PositionedDirectional(
                      start: (filled - 3).clamp(0.0, width - 6),
                      top: -(widget.height / 2),
                      width: 6,
                      height: widget.height * 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.accent,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: colors.accent.withValues(alpha: 0.65),
                              blurRadius: 7,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );

    if (!widget.showRemaining) {
      return bar;
    }

    final label = remaining.inSeconds <= 0
        ? null
        : strings.minutesLeft((remaining.inSeconds / 60).ceil());

    return Row(
      children: <Widget>[
        Expanded(child: bar),
        if (label != null) ...<Widget>[
          const SizedBox(width: 8),
          Text(
            label,
            maxLines: 1,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.overlay0,
                  fontSize: 9,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
          ),
        ],
      ],
    );
  }
}
