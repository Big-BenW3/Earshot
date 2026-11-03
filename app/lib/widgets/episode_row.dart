import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import 'dial.dart';
import 'press.dart';

/// One episode in a show's list.
class EpisodeRow extends StatelessWidget {
  const EpisodeRow({super.key, required this.show, required this.episode});
  final Show show;
  final Episode episode;

  @override
  Widget build(BuildContext context) {
    final player = context.services.player;
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final current = player.isCurrent(episode);
        final playing = current && player.playing;
        final saved = player.savedPosition(episode);
        final total = (current ? player.duration : null) ?? episode.duration;
        double? progress;
        String? status;
        if (saved != null &&
            saved > Duration.zero &&
            total != null &&
            total > Duration.zero) {
          progress = (saved.inMilliseconds / total.inMilliseconds).clamp(
            0.0,
            1.0,
          );
          status = timeLeft(saved, total);
        }
        final meta = [
          shortDate(episode.publishAt),
          if (episode.duration != null) humanDuration(episode.duration!),
        ].join('  ·  ');

        return Material(
          color: current ? Palette.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.card),
          child: RingInkWell(
            radius: Radii.card,
            onTap: () => context.go('/s/${show.slug}/e/${episode.id}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: Space.lg,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(meta, style: TextStyles.timecode),
                        const SizedBox(height: 6),
                        Text(episode.title, style: TextStyles.itemTitle),
                        if (episode.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            episode.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyles.small,
                          ),
                        ],
                        if (status != null || current) ...[
                          const SizedBox(height: Space.sm),
                          Text(
                            current && player.playing
                                ? 'Playing'
                                : status ?? 'Paused',
                            style: TextStyles.timecode.copyWith(
                              color: current ? Palette.amber : Palette.glow,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.lg),
                  PlayKey(
                    playing: playing,
                    loading: current && player.loading,
                    outlined: !current,
                    size: 48,
                    progress: progress ?? 0,
                    label: '${playing ? 'Pause' : 'Play'} ${episode.title}',
                    onPressed: () => playing
                        ? player.pause()
                        : current
                        ? player.toggle()
                        : player.playEpisode(show, episode),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
