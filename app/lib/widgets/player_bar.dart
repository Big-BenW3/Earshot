import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import '../services/playback/player_controller.dart';
import '../services/services.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import 'common.dart';
import 'dial.dart';
import 'press.dart';

/// Link to an episode, optionally at a time: `.../e/abc?t=754`.
String episodeLink(Episode e, {Duration? at}) {
  if (at == null || at.inSeconds <= 0) return e.pageUrl;
  return '${e.pageUrl}?t=${at.inSeconds}';
}

/// Persistent player along the bottom of every page.
class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.services.player;
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final episode = player.episode;
        final show = player.show;
        return AnimatedSize(
          duration: Motion.of(context, Motion.enter),
          curve: Motion.out,
          alignment: Alignment.topCenter,
          child: episode == null || show == null
              ? const SizedBox(width: double.infinity)
              : _Bar(player: player, show: show, episode: episode),
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.player, required this.show, required this.episode});
  final PlayerController player;
  final Show show;
  final Episode episode;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 860;
    return Semantics(
      container: true,
      label: 'Player',
      explicitChildNodes: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Palette.night,
          border: const Border(top: BorderSide(color: Palette.line)),
          boxShadow: [
            BoxShadow(
              color: Palette.amber.withValues(alpha: 0.10),
              blurRadius: 24,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: wide
              ? _WideBar(player: player, show: show, episode: episode)
              : _CompactBar(player: player, show: show, episode: episode),
        ),
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.show, required this.episode, this.onTap});
  final Show show;
  final Episode episode;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return RingInkWell(
      onTap: onTap ?? () => context.go('/s/${show.slug}/e/${episode.id}'),
      radius: Radii.small,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(
          children: [
            CoverArt(show: show, size: 44, radius: 8),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    episode.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyles.label,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    show.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyles.small,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({
    required this.forward,
    required this.onPressed,
    this.size = 26,
  });
  final bool forward;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) => Press(
    child: IconButton(
      tooltip: forward ? 'Forward 15 seconds' : 'Back 15 seconds',
      onPressed: onPressed,
      icon: SkipGlyph(forward: forward, size: size),
    ),
  );
}

/// A circular arrow with "15" inside (Material has no 15-second icon).
class SkipGlyph extends StatelessWidget {
  const SkipGlyph({super.key, required this.forward, this.size = 26});
  final bool forward;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _SkipPainter(forward),
      child: Center(
        child: Padding(
          padding: EdgeInsets.only(top: size * 0.06),
          child: Text(
            '15',
            style: TextStyle(
              fontFamily: Fonts.mono,
              fontSize: size * 0.36,
              fontWeight: FontWeight.w500,
              color: Palette.cream,
              height: 1,
              letterSpacing: -0.5,
            ),
          ),
        ),
      ),
    ),
  );
}

class _SkipPainter extends CustomPainter {
  _SkipPainter(this.forward);
  final bool forward;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = (s * 0.08).clamp(1.6, 3.0);
    final rect = Rect.fromCircle(
      center: Offset(s / 2, s / 2),
      radius: s / 2 - stroke,
    );
    final paint = Paint()
      ..color = Palette.cream
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.save();
    if (!forward) {
      // Mirror for the back arrow.
      canvas.translate(s, 0);
      canvas.scale(-1, 1);
    }
    // Arc from the top, clockwise, leaving a gap before the top.
    const start = -math.pi / 2 + 0.35;
    const sweep = math.pi * 2 - 0.9;
    canvas.drawArc(rect, start, sweep, false, paint);
    // Arrowhead at the start of the arc, pointing clockwise.
    final p = Offset(
      rect.center.dx + rect.width / 2 * math.cos(start),
      rect.center.dy + rect.height / 2 * math.sin(start),
    );
    final head = s * 0.2;
    final arrow = Path()
      ..moveTo(p.dx - head * 0.9, p.dy - head * 0.75)
      ..lineTo(p.dx + head * 0.15, p.dy)
      ..lineTo(p.dx - head * 0.9, p.dy + head * 0.75);
    canvas.drawPath(arrow, paint..strokeJoin = StrokeJoin.round);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SkipPainter old) => old.forward != forward;
}

class SpeedButton extends StatelessWidget {
  const SpeedButton({super.key, required this.player});
  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Playback speed',
      child: Semantics(
        button: true,
        label: 'Playback speed ${speedLabel(player.speed)}. Change speed',
        child: ExcludeSemantics(
          child: Press(
            child: OutlinedButton(
              onPressed: player.cycleSpeed,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(64, 44),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: TextStyles.timecode,
              ),
              child: Text(
                speedLabel(player.speed),
                style: TextStyles.timecode.copyWith(
                  color: Palette.cream,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WideBar extends StatelessWidget {
  const _WideBar({
    required this.player,
    required this.show,
    required this.episode,
  });
  final PlayerController player;
  final Show show;
  final Episode episode;

  @override
  Widget build(BuildContext context) {
    final d = player.duration;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.xl,
        vertical: Space.md,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 280,
            child: _TitleBlock(show: show, episode: episode),
          ),
          const SizedBox(width: Space.lg),
          _SkipButton(forward: false, onPressed: () => player.skip(-skipStep)),
          const SizedBox(width: Space.xs),
          PlayKey(
            playing: player.playing,
            loading: player.loading,
            onPressed: player.toggle,
            size: 52,
          ),
          const SizedBox(width: Space.xs),
          _SkipButton(forward: true, onPressed: () => player.skip(skipStep)),
          const SizedBox(width: Space.xl),
          Text(clock(player.position), style: TextStyles.timecode),
          const SizedBox(width: Space.md),
          Expanded(
            child: player.failed
                ? Text(
                    player.errorMessage,
                    style: TextStyles.small.copyWith(color: Palette.tube),
                    maxLines: 2,
                  )
                : DialSlider(
                    position: player.position,
                    duration: d,
                    onSeek: player.seek,
                    height: 44,
                  ),
          ),
          const SizedBox(width: Space.md),
          Text(
            d == null ? '--:--' : '-${clock(d - player.position)}',
            style: TextStyles.timecode,
          ),
          const SizedBox(width: Space.lg),
          SpeedButton(player: player),
          const SizedBox(width: Space.xs),
          IconButton(
            tooltip: 'Close player',
            onPressed: player.close,
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class _CompactBar extends StatelessWidget {
  const _CompactBar({
    required this.player,
    required this.show,
    required this.episode,
  });
  final PlayerController player;
  final Show show;
  final Episode episode;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: LinearProgressIndicator(
            value: player.progress,
            minHeight: 2,
            color: Palette.glow,
            backgroundColor: Palette.line,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.sm,
            Space.sm,
            Space.md,
            Space.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Open full player',
                  child: _TitleBlock(
                    show: show,
                    episode: episode,
                    onTap: () => showNowPlaying(context),
                  ),
                ),
              ),
              if (player.failed)
                const Padding(
                  padding: EdgeInsets.only(right: Space.sm),
                  child: Icon(Icons.error_outline_rounded, color: Palette.tube),
                ),
              _SkipButton(
                forward: false,
                onPressed: () => player.skip(-skipStep),
                size: 24,
              ),
              PlayKey(
                playing: player.playing,
                loading: player.loading,
                onPressed: player.toggle,
                size: 46,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Future<void> showNowPlaying(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // Rises from the bar that opened it; leaves faster than it came.
    sheetAnimationStyle: Motion.sheet(context),
    builder: (_) => const NowPlayingSheet(),
  );
}

/// Full player for phones.
class NowPlayingSheet extends StatelessWidget {
  const NowPlayingSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final services = context.services;
    final player = services.player;
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final show = player.show;
        final episode = player.episode;
        if (show == null || episode == null) return const SizedBox(height: 120);
        final d = player.duration;
        final art = (MediaQuery.sizeOf(context).width - 96).clamp(160.0, 320.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
          child: Column(
            children: [
              const Overline('Now playing'),
              const SizedBox(height: Space.lg),
              CoverArt(show: show, size: art),
              const SizedBox(height: Space.xl),
              Text(
                episode.title,
                style: TextStyles.headline(
                  true,
                ).copyWith(fontSize: 24, height: 30 / 24),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.xs),
              Text(
                show.name,
                style: TextStyles.small,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.xl),
              if (player.failed)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.md),
                  child: Text(
                    player.errorMessage,
                    style: TextStyles.small.copyWith(color: Palette.tube),
                    textAlign: TextAlign.center,
                  ),
                ),
              DialSlider(
                position: player.position,
                duration: d,
                onSeek: player.seek,
                height: 44,
              ),
              const SizedBox(height: Space.sm),
              Row(
                children: [
                  Text(clock(player.position), style: TextStyles.timecode),
                  const Spacer(),
                  Text(
                    d == null ? '--:--' : '-${clock(d - player.position)}',
                    style: TextStyles.timecode,
                  ),
                ],
              ),
              const SizedBox(height: Space.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _SkipButton(
                    forward: false,
                    onPressed: () => player.skip(-skipStep),
                    size: 34,
                  ),
                  const SizedBox(width: Space.xl),
                  PlayKey(
                    playing: player.playing,
                    loading: player.loading,
                    onPressed: player.toggle,
                    size: 76,
                  ),
                  const SizedBox(width: Space.xl),
                  _SkipButton(
                    forward: true,
                    onPressed: () => player.skip(skipStep),
                    size: 34,
                  ),
                ],
              ),
              const SizedBox(height: Space.xl),
              Semantics(
                label: 'Playback speed',
                container: true,
                child: Wrap(
                  spacing: Space.sm,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final s in playbackSpeeds)
                      _SpeedChip(
                        speed: s,
                        selected: player.speed == s,
                        onTap: () => player.setSpeed(s),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Space.lg),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: Space.sm,
                children: [
                  TextButton.icon(
                    onPressed: () => copyToClipboard(
                      context,
                      episodeLink(episode, at: player.position),
                      'Link at ${clock(player.position)}',
                    ),
                    icon: const Icon(Icons.link_rounded),
                    label: Text('Copy link at ${clock(player.position)}'),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.go('/s/${show.slug}/e/${episode.id}');
                    },
                    icon: const Icon(Icons.notes_rounded),
                    label: const Text('Episode notes'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SpeedChip extends StatelessWidget {
  const _SpeedChip({
    required this.speed,
    required this.selected,
    required this.onTap,
  });
  final double speed;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Speed ${speedLabel(speed)}',
      excludeSemantics: true,
      child: Press(
        child: Material(
          color: selected ? Palette.amber : Palette.surface,
          shape: StadiumBorder(
            side: BorderSide(color: selected ? Palette.amber : Palette.faint),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 44, minWidth: 56),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                speedLabel(speed),
                style: TextStyles.timecode.copyWith(
                  fontSize: 14,
                  color: selected ? Palette.night : Palette.cream,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
