import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../services/walrus_service.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/dial.dart';
import '../widgets/player_bar.dart';
import '../widgets/press.dart';
import '../widgets/skeleton.dart';
import 'show_screen.dart';

class EpisodeScreen extends StatelessWidget {
  const EpisodeScreen({
    super.key,
    required this.slug,
    required this.episodeId,
    this.startAt,
  });

  final String slug;
  final String episodeId;

  /// From a shared link (`?t=754`).
  final Duration? startAt;

  @override
  Widget build(BuildContext context) {
    return ShowLoader<(Show, Episode)>(
      loading: const EpisodeSkeleton(),
      key: ValueKey('$slug/$episodeId'),
      load: (c) => c.services.api.episode(slug, episodeId),
      notFound: NotFoundState(
        title: 'Episode not available',
        body: 'It may have been removed by the show, or the link is mistyped.',
        // ignore: prefer_const_constructors
      ),
      builder: (context, data, _) => _EpisodeView(
        key: ValueKey(data.$2.id),
        show: data.$1,
        episode: data.$2,
        startAt: startAt,
      ),
    );
  }
}

class _EpisodeView extends StatefulWidget {
  const _EpisodeView({
    super.key,
    required this.show,
    required this.episode,
    this.startAt,
  });
  final Show show;
  final Episode episode;
  final Duration? startAt;

  @override
  State<_EpisodeView> createState() => _EpisodeViewState();
}

class _EpisodeViewState extends State<_EpisodeView> {
  BlobAvailability? _availability;
  double? _downloadProgress;
  String? _downloadError;
  DownloadCancellation? _downloadCancellation;

  @override
  void dispose() {
    _downloadCancellation?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_availability == null) _check();
  }

  Future<void> _check() async {
    final result = await context.services.walrus.availability(
      widget.episode.blobId,
    );
    if (mounted) setState(() => _availability = result);
  }

  Future<void> _download() async {
    if (_downloadProgress != null) return;
    final services = context.services;
    setState(() {
      _downloadProgress = 0;
      _downloadError = null;
    });
    final cancellation = _downloadCancellation = DownloadCancellation();
    try {
      final bytes = await services.walrus.download(
        widget.episode.blobId,
        cancellation: cancellation,
        maxBytes: widget.episode.sizeBytes,
        onProgress: (done, total) {
          if (mounted && total > 0) {
            setState(() => _downloadProgress = done / total);
          }
        },
      );
      if (!mounted) return;
      services.browser.saveFile(
        bytes,
        fileName: downloadName(
          widget.show.name,
          widget.episode.title,
          widget.episode.extension,
        ),
        mime: widget.episode.mime,
      );
      if (mounted) showToast(context, 'Download ready');
    } on WalrusException catch (e) {
      if (mounted) setState(() => _downloadError = e.message);
    } finally {
      _downloadCancellation = null;
      if (mounted) setState(() => _downloadProgress = null);
    }
  }

  Future<void> _share(Duration? at) async {
    final services = context.services;
    final url = episodeLink(widget.episode, at: at);
    if (services.browser.canShare) {
      await services.browser.share(title: widget.episode.title, url: url);
    } else {
      await copyToClipboard(
        context,
        url,
        at == null ? 'Link' : 'Link at ${clock(at)}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final show = widget.show;
    final episode = widget.episode;
    final player = context.services.player;
    final compact = MediaQuery.sizeOf(context).width < 600;
    final expired = _availability == BlobAvailability.missing;

    return PageFrame(
      maxWidth: 860,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.go('/s/${show.slug}'),
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
            label: Text(show.name, overflow: TextOverflow.ellipsis),
          ),
        ),
        const SizedBox(height: Space.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CoverArt(show: show, size: compact ? 72 : 96),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Overline(show.author),
                  const SizedBox(height: Space.sm),
                  Text(episodeMeta(episode), style: TextStyles.timecode),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.xl),
        Semantics(
          header: true,
          child: Text(episode.title, style: TextStyles.headline(compact)),
        ),
        const SizedBox(height: Space.xl),
        if (expired)
          _ExpiredNotice(endEpoch: episode.endEpoch)
        else
          ListenableBuilder(
            listenable: player,
            builder: (context, _) => _PlayPanel(
              show: show,
              episode: episode,
              startAt: widget.startAt,
            ),
          ),
        const SizedBox(height: Space.xl),
        ListenableBuilder(
          listenable: player,
          builder: (context, _) {
            final current =
                player.isCurrent(episode) && player.position > Duration.zero;
            return Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                Press(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        copyToClipboard(context, episode.pageUrl, 'Link'),
                    icon: const Icon(Icons.link_rounded, size: 20),
                    label: const Text('Copy link'),
                  ),
                ),
                if (current)
                  Press(
                    child: OutlinedButton.icon(
                      onPressed: () => copyToClipboard(
                        context,
                        episodeLink(episode, at: player.position),
                        'Link at ${clock(player.position)}',
                      ),
                      icon: const Icon(Icons.schedule_rounded, size: 20),
                      label: Text('Copy link at ${clock(player.position)}'),
                    ),
                  ),
                if (context.services.browser.canShare)
                  Press(
                    child: OutlinedButton.icon(
                      onPressed: () => _share(current ? player.position : null),
                      icon: const Icon(Icons.ios_share_rounded, size: 20),
                      label: const Text('Share'),
                    ),
                  ),
                if (!expired)
                  Press(
                    child: OutlinedButton.icon(
                      onPressed: _downloadProgress != null ? null : _download,
                      icon: const Icon(Icons.download_rounded, size: 20),
                      label: Text(
                        _downloadProgress == null
                            ? 'Download episode'
                            : 'Downloading ${(_downloadProgress! * 100).round()}%',
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (_downloadProgress != null) ...[
          const SizedBox(height: Space.md),
          LinearProgressIndicator(
            value: _downloadProgress == 0 ? null : _downloadProgress,
          ),
        ],
        if (_downloadError != null) ...[
          const SizedBox(height: Space.md),
          Semantics(
            liveRegion: true,
            child: Text(
              _downloadError!,
              style: TextStyles.small.copyWith(color: Palette.tube),
            ),
          ),
        ],
        const SizedBox(height: Space.xxl),
        if (episode.description.isNotEmpty) ...[
          const Overline('Notes', color: Palette.muted),
          const SizedBox(height: Space.md),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Space.readingWidth),
            child: SelectableText(episode.description, style: TextStyles.body),
          ),
          const SizedBox(height: Space.xxl),
        ],
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Space.readingWidth),
          child: WalrusNote(
            blobId: episode.blobId,
            endEpoch: episode.endEpoch,
            extra: _availability == BlobAvailability.unknown
                ? 'Could not check the storage status just now.'
                : 'Downloads are read from Walrus with Dartus. Playback streams '
                      'straight from the aggregator.',
          ),
        ),
      ],
    );
  }
}

class _PlayPanel extends StatelessWidget {
  const _PlayPanel({required this.show, required this.episode, this.startAt});
  final Show show;
  final Episode episode;
  final Duration? startAt;

  @override
  Widget build(BuildContext context) {
    final player = context.services.player;
    final current = player.isCurrent(episode);
    final playing = current && player.playing;
    final saved = player.savedPosition(episode);
    final total = (current ? player.duration : null) ?? episode.duration;

    String label;
    Duration? from;
    if (current) {
      label = playing ? 'Playing' : 'Paused at ${clock(player.position)}';
    } else if (startAt != null && startAt! > Duration.zero) {
      from = startAt;
      label = 'Play from ${clock(startAt!)}';
    } else if (saved != null &&
        saved > const Duration(seconds: 5) &&
        (total == null || !isFinished(saved, total))) {
      label = 'Resume from ${clock(saved)}';
    } else {
      label = 'Play episode';
    }

    return Container(
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        color: Palette.night,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: current ? Palette.amber.withValues(alpha: 0.5) : Palette.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PlayKey(
                playing: playing,
                loading: current && player.loading,
                size: 72,
                label: playing ? 'Pause' : label,
                onPressed: () => current
                    ? player.toggle()
                    : player.playEpisode(show, episode, start: from),
              ),
              const SizedBox(width: Space.xl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyles.itemTitle),
                    const SizedBox(height: 4),
                    Text(
                      total == null ? 'Length unknown' : clock(total),
                      style: TextStyles.timecode,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (current) ...[
            const SizedBox(height: Space.xl),
            if (player.failed)
              Text(
                player.errorMessage,
                style: TextStyles.small.copyWith(color: Palette.tube),
              )
            else
              DialSlider(
                position: player.position,
                duration: player.duration,
                onSeek: player.seek,
              ),
          ],
        ],
      ),
    );
  }
}

class _ExpiredNotice extends StatelessWidget {
  const _ExpiredNotice({required this.endEpoch});
  final int? endEpoch;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Palette.tube.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.hourglass_bottom_rounded, color: Palette.tube),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This recording is no longer stored',
                  style: TextStyles.itemTitle,
                ),
                const SizedBox(height: Space.xs),
                Text(
                  'Its Walrus storage period has ended${endEpoch == null ? '' : ' (epoch $endEpoch)'}, '
                  'or the host deleted it. Ask the show to upload it again.',
                  style: TextStyles.small,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
