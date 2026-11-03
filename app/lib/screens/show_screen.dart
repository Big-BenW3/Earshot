import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/services.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../util/validation.dart';
import '../widgets/common.dart';
import '../widgets/episode_row.dart';
import '../widgets/press.dart';
import '../widgets/skeleton.dart';

/// Loads a show page and keeps the result; shared with the episode screen.
class ShowLoader<T> extends StatefulWidget {
  const ShowLoader({
    super.key,
    required this.load,
    required this.builder,
    this.notFound,
    this.loading,
  });

  final Future<T> Function(BuildContext context) load;
  final Widget Function(BuildContext context, T value, VoidCallback reload)
  builder;
  final Widget? notFound;

  /// Content-shaped placeholder shown while loading.
  final Widget? loading;

  @override
  State<ShowLoader<T>> createState() => _ShowLoaderState<T>();
}

class _ShowLoaderState<T> extends State<ShowLoader<T>> {
  Future<T>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= widget.load(context);
  }

  void _reload() => setState(() {
    _future = widget.load(context);
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return widget.loading ??
              const PageFrame(showFooter: false, children: [LoadingState()]);
        }
        final error = snap.error;
        if (error is ApiException && error.notFound) {
          return PageFrame(
            children: [widget.notFound ?? const NotFoundState()],
          );
        }
        if (error != null) {
          return PageFrame(
            children: [ErrorState(message: '$error', onRetry: _reload)],
          );
        }
        return widget.builder(context, snap.data as T, _reload);
      },
    );
  }
}

class ShowScreen extends StatelessWidget {
  const ShowScreen({super.key, required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context) {
    return ShowLoader<ShowPage>(
      loading: const ShowSkeleton(),
      key: ValueKey(slug),
      load: (c) => c.services.api.show(slug),
      notFound: const NotFoundState(
        title: 'Show not found',
        body:
            'There is no show at this link. Check the address with whoever shared it.',
      ),
      builder: (context, page, _) => _ShowView(page: page),
    );
  }
}

class _ShowView extends StatelessWidget {
  const _ShowView({required this.page});
  final ShowPage page;

  @override
  Widget build(BuildContext context) {
    final show = page.show;
    final pinned = page.pinned;
    final rest = page.unpinned;
    return PageFrame(
      children: [
        const SizedBox(height: Space.lg),
        _ShowHeader(page: page),
        const SizedBox(height: Space.xxxl),
        if (pinned != null) ...[
          _PinnedCard(show: show, episode: pinned),
          const SizedBox(height: Space.xxl),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Semantics(
              header: true,
              child: const Text('Episodes', style: TextStyles.title),
            ),
            const SizedBox(width: Space.md),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${page.episodes.length}',
                style: TextStyles.timecode,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        const Divider(),
        if (page.episodes.isEmpty)
          const MessageState(
            title: 'No episodes yet',
            body:
                'New recordings will appear here as soon as they are published.',
            icon: Icons.graphic_eq_rounded,
          )
        else
          for (final e in rest) ...[
            EpisodeRow(show: show, episode: e),
            const Divider(),
          ],
      ],
    );
  }
}

class _ShowHeader extends StatelessWidget {
  const _ShowHeader({required this.page});
  final ShowPage page;

  @override
  Widget build(BuildContext context) {
    final show = page.show;
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 600;
    final wide = width >= 820;
    final player = context.services.player;
    final latest =
        page.pinned ?? (page.episodes.isEmpty ? null : page.episodes.first);

    final text = Column(
      crossAxisAlignment: wide
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Overline(
          [
            show.category,
            languageName(show.language),
          ].where((s) => s.isNotEmpty).join('  ·  '),
        ),
        const SizedBox(height: Space.md),
        Semantics(
          header: true,
          child: Text(
            show.name,
            style: TextStyles.display(compact),
            textAlign: wide ? TextAlign.start : TextAlign.center,
          ),
        ),
        const SizedBox(height: Space.sm),
        Text(
          'by ${show.author}',
          style: TextStyles.body.copyWith(color: Palette.muted),
          textAlign: wide ? TextAlign.start : TextAlign.center,
        ),
        if (show.description.isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Space.readingWidth),
            child: _Expandable(text: show.description, center: !wide),
          ),
        ],
        const SizedBox(height: Space.xl),
        Wrap(
          spacing: Space.md,
          runSpacing: Space.md,
          alignment: wide ? WrapAlignment.start : WrapAlignment.center,
          children: [
            if (latest != null)
              ListenableBuilder(
                listenable: player,
                builder: (context, _) {
                  final current = player.isCurrent(latest);
                  final saved = player.savedPosition(latest);
                  final label = current && player.playing
                      ? 'Pause'
                      : saved != null && saved > const Duration(seconds: 5)
                      ? 'Resume ${page.pinned != null ? 'pinned' : 'latest'}'
                      : 'Play ${page.pinned != null ? 'pinned' : 'latest'}';
                  return Press(
                    child: FilledButton.icon(
                      onPressed: () => current
                          ? player.toggle()
                          : player.playEpisode(show, latest),
                      icon: Icon(
                        current && player.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      label: Text(label),
                    ),
                  );
                },
              ),
            _SubscribeButton(show: show),
            Press(
              child: OutlinedButton.icon(
                onPressed: () => _share(context, show),
                icon: const Icon(Icons.ios_share_rounded, size: 20),
                label: const Text('Share'),
              ),
            ),
          ],
        ),
      ],
    );

    final cover = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.cover),
        boxShadow: const [
          BoxShadow(
            color: Color(0x73000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: CoverArt(show: show, size: wide ? 280 : (compact ? 200 : 240)),
    );

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cover,
          const SizedBox(width: Space.xxxl),
          Expanded(child: text),
        ],
      );
    }
    return Column(
      children: [
        cover,
        const SizedBox(height: Space.xl),
        text,
      ],
    );
  }

  Future<void> _share(BuildContext context, Show show) async {
    final browser = context.services.browser;
    if (browser.canShare) {
      await browser.share(title: show.name, url: show.publicUrl);
    } else {
      await copyToClipboard(context, show.publicUrl, 'Show link');
    }
  }
}

class _SubscribeButton extends StatelessWidget {
  const _SubscribeButton({required this.show});
  final Show show;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      style: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Palette.raised),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.rss_feed_rounded, size: 20),
          onPressed: () => copyToClipboard(context, show.feedUrl, 'Feed link'),
          child: const Text('Copy RSS feed link'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: const Text(
              'In your podcast app, choose "Add by URL" or "Follow a show by URL" '
              'and paste the link.',
              style: TextStyles.small,
            ),
          ),
        ),
      ],
      builder: (context, controller, _) => Press(
        child: OutlinedButton.icon(
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          icon: const Icon(Icons.rss_feed_rounded, size: 20),
          label: const Text('Subscribe'),
        ),
      ),
    );
  }
}

class _PinnedCard extends StatelessWidget {
  const _PinnedCard({required this.show, required this.episode});
  final Show show;
  final Episode episode;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.card),
      child: ColoredBox(
        color: Palette.surface,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(width: 4, child: ColoredBox(color: Palette.amber)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.sm,
                    Space.lg,
                    Space.md,
                    Space.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(left: Space.md),
                        child: Overline('Pinned  ·  Start here'),
                      ),
                      EpisodeRow(show: show, episode: episode),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Expandable extends StatefulWidget {
  const _Expandable({required this.text, required this.center});
  final String text;
  final bool center;

  @override
  State<_Expandable> createState() => _ExpandableState();
}

class _ExpandableState extends State<_Expandable> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final long =
        widget.text.length > 280 || '\n'.allMatches(widget.text).length > 3;
    return Column(
      crossAxisAlignment: widget.center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          style: TextStyles.bodyMuted,
          maxLines: long && !_open ? 4 : null,
          overflow: long && !_open ? TextOverflow.fade : null,
          textAlign: widget.center ? TextAlign.center : TextAlign.start,
        ),
        if (long)
          TextButton(
            onPressed: () => setState(() => _open = !_open),
            child: Text(_open ? 'Show less' : 'Read more'),
          ),
      ],
    );
  }
}

/// Small helper used by other screens for "date · duration · size".
String episodeMeta(Episode e) => [
  shortDate(e.publishAt),
  if (e.duration != null) humanDuration(e.duration!),
  if (e.sizeBytes > 0) fileSize(e.sizeBytes),
].join('  ·  ');

extension GoShow on BuildContext {
  void goShow(String slug) => go('/s/$slug');
}
