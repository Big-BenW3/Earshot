import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/services.dart';
import '../theme/tokens.dart';
import '../widgets/account.dart';
import '../widgets/common.dart';
import '../widgets/press.dart';
import '../widgets/pending_uploads.dart';
import '../widgets/skeleton.dart';

/// `/app`: the signed-in host's shows, on any device. Listeners never come
/// here; they open a show link.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const SignedIn(
    title: 'Your shows, on any device',
    body:
        'Sign in with your Sui wallet to create shows, upload episodes and '
        'manage them. Listeners never need a wallet: they just open the show '
        'link or follow the podcast feed.',
    child: _MyShows(),
  );
}

class _MyShows extends StatefulWidget {
  const _MyShows();

  @override
  State<_MyShows> createState() => _MyShowsState();
}

class _MyShowsState extends State<_MyShows> {
  Future<List<MyShow>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<List<MyShow>> _load() async {
    final services = context.services;
    try {
      return await services.api.myShows();
    } on ApiException catch (e) {
      if (e.status == 401) services.auth.sessionEnded();
      rethrow;
    }
  }

  void _reload() => setState(() {
    _future = _load();
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return PageFrame(
      headerTrailing: const AccountChip(),
      children: [
        const SizedBox(height: Space.lg),
        const AuthNotice(),
        EarshotPendingUploads(onCompleted: _reload),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.end,
          runSpacing: Space.md,
          spacing: Space.lg,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Overline('Host'),
                const SizedBox(height: Space.sm),
                Semantics(
                  header: true,
                  child: Text(
                    'Your shows',
                    style: TextStyles.headline(compact),
                  ),
                ),
              ],
            ),
            Press(
              child: FilledButton.icon(
                onPressed: () => context.go('/new'),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Start a show'),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.xl),
        FutureBuilder<List<MyShow>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SkeletonPulse(
                label: 'Loading your shows',
                child: Column(
                  children: [
                    _RowSkeleton(),
                    SizedBox(height: Space.md),
                    _RowSkeleton(),
                  ],
                ),
              );
            }
            if (snap.hasError) {
              return ErrorState(message: '${snap.error}', onRetry: _reload);
            }
            final shows = snap.data!;
            if (shows.isEmpty) {
              return MessageState(
                title: 'No shows yet',
                body:
                    'Start a show for your church, class or meetup. You can '
                    'upload the first episode straight after.',
                icon: Icons.graphic_eq_rounded,
                action: Press(
                  child: FilledButton(
                    onPressed: () => context.go('/new'),
                    child: const Text('Start a show'),
                  ),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final s in shows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.md),
                    child: _ShowCard(item: s),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Space.lg),
    decoration: BoxDecoration(
      color: Palette.surface,
      borderRadius: BorderRadius.circular(Radii.card),
    ),
    child: const Row(
      children: [
        SkeletonBox(width: 72, height: 72, radius: 12),
        SizedBox(width: Space.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 220, height: 18),
              SizedBox(height: 10),
              SkeletonBox(width: 120, height: 12),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ShowCard extends StatelessWidget {
  const _ShowCard({required this.item});
  final MyShow item;

  @override
  Widget build(BuildContext context) {
    final show = item.show;
    final count = item.episodeCount;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: Space.md,
        spacing: Space.lg,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CoverArt(show: show, size: 72, radius: 12),
              const SizedBox(width: Space.lg),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(show.name, style: TextStyles.itemTitle),
                      const SizedBox(height: 4),
                      Text(
                        count == 0
                            ? 'No episodes yet'
                            : '$count ${count == 1 ? 'episode' : 'episodes'}',
                        style: TextStyles.small,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '/s/${show.slug}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyles.timecode,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Wrap(
            spacing: Space.sm,
            children: [
              Press(
                child: FilledButton(
                  onPressed: () => context.go('/s/${show.slug}/admin'),
                  child: const Text('Manage'),
                ),
              ),
              Press(
                child: OutlinedButton(
                  onPressed: () => context.go('/s/${show.slug}'),
                  child: const Text('Listen'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
