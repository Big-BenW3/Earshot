import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/services.dart';
import '../services/wallet_upload.dart';
import '../theme/tokens.dart';
import '../widgets/account.dart';
import '../widgets/common.dart';
import '../widgets/press.dart';
import '../widgets/show_form.dart';
import '../widgets/wallet_write.dart';

class CreateShowScreen extends StatelessWidget {
  const CreateShowScreen({super.key});

  @override
  Widget build(BuildContext context) => const SignedIn(
    title: 'Sign in to start a show',
    body:
        'Your shows belong to your Sui address, so you can manage them from '
        'any device. Listeners never need a wallet.',
    child: _CreateShowContent(),
  );
}

class _CreateShowContent extends StatefulWidget {
  const _CreateShowContent();
  @override
  State<_CreateShowContent> createState() => _CreateShowContentState();
}

class _CreateShowContentState extends State<_CreateShowContent> {
  final _progress = ValueNotifier<String?>(null);
  CreatedShow? _created;
  String? _coverProblem;

  /// The cover art's wallet-paid write, kept so a retry does not pay twice.
  WalletUpload? _coverUpload;

  @override
  void dispose() {
    _progress.dispose();
    _coverUpload?.dispose();
    super.dispose();
  }

  Future<void> _create(ShowFormValues v) async {
    final services = context.services;
    _progress.value = 'Creating show…';
    final created = await services.api.createShow(
      name: v.name,
      author: v.author,
      description: v.description,
      language: v.language,
      category: v.category,
      explicit: v.explicit,
    );
    String? problem;
    if (v.cover != null && mounted) {
      _coverUpload = services.newUpload(v.cover!.bytes);
      _progress.value = 'Storing cover art…';
      problem = await _storeCover(created.show.slug);
    }
    if (!mounted) return;
    setState(() {
      _created = created;
      _coverProblem = problem;
    });
  }

  /// Stores the cover with the host's wallet and sets it on the show.
  /// Returns what went wrong, or null.
  Future<String?> _storeCover(String slug) async {
    final upload = _coverUpload!;
    final api = context.services.api;
    upload.setRecoveryMetadata({
      'kind': 'cover',
      'label': 'Show cover art',
      'slug': slug,
      'fields': <String, Object?>{},
    });
    final blob = await storeWithWallet(
      context,
      upload: upload,
      title: 'Store the cover art',
      what: 'the cover art',
    );
    if (blob == null) {
      return upload.problem?.message ?? 'You closed it before it was stored.';
    }
    try {
      await api.updateShow(slug, {'coverBlobId': blob.blobId});
      await upload.markListed();
      return null;
    } on ApiException catch (e) {
      await upload.releaseRecovery();
      return e.message;
    } catch (_) {
      await upload.releaseRecovery();
      return 'Could not finish saving the cover. Your upload is saved; try again.';
    }
  }

  Future<void> _retryCover() async {
    final problem = await _storeCover(_created!.show.slug);
    if (mounted) setState(() => _coverProblem = problem);
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final created = _created;
    return PageFrame(
      maxWidth: 900,
      headerTrailing: const AccountChip(),
      children: [
        const SizedBox(height: Space.xl),
        if (created == null) ...[
          const Overline('New show'),
          const SizedBox(height: Space.sm),
          Semantics(
            header: true,
            child: Text('Start a show', style: TextStyles.headline(compact)),
          ),
          const SizedBox(height: Space.sm),
          const Text(
            'You get a public page and a podcast feed to share. The show '
            'belongs to your signed-in address.',
            style: TextStyles.bodyMuted,
          ),
          const SizedBox(height: Space.xxl),
          ShowForm(
            submitLabel: 'Create show',
            onSubmit: _create,
            progress: _progress,
          ),
        ] else
          _Created(
            created: created,
            coverProblem: _coverProblem,
            onRetryCover: _retryCover,
          ),
      ],
    );
  }
}

class _Created extends StatelessWidget {
  const _Created({
    required this.created,
    required this.coverProblem,
    required this.onRetryCover,
  });
  final CreatedShow created;
  final String? coverProblem;
  final VoidCallback onRetryCover;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final slug = created.show.slug;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Overline('Ready', color: Palette.moss),
        const SizedBox(height: Space.sm),
        Semantics(
          header: true,
          child: Text(
            '${created.show.name} is ready',
            style: TextStyles.headline(compact),
          ),
        ),
        const SizedBox(height: Space.sm),
        const Text(
          'It belongs to your signed-in address. Manage it from Your shows '
          'on any device by signing in with the same wallet.',
          style: TextStyles.bodyMuted,
        ),
        if (coverProblem != null) ...[
          const SizedBox(height: Space.lg),
          Semantics(
            liveRegion: true,
            child: Text(
              'The cover art is not stored yet. $coverProblem You can also '
              'add it later from admin.',
              style: TextStyles.small.copyWith(color: Palette.tube),
            ),
          ),
          const SizedBox(height: Space.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onRetryCover,
              icon: const Icon(Icons.image_outlined, size: 18),
              label: const Text('Store cover art'),
            ),
          ),
        ],
        const SizedBox(height: Space.xl),
        CopyField(
          label: 'Public link',
          value: created.publicUrl,
          emphasis: true,
          help: 'Share this with listeners. No account needed to listen.',
        ),
        const SizedBox(height: Space.md),
        CopyField(
          label: 'Podcast feed (RSS)',
          value: created.feedUrl,
          help: 'Paste into a podcast app to subscribe.',
        ),
        const SizedBox(height: Space.xl),
        Wrap(
          spacing: Space.md,
          runSpacing: Space.md,
          children: [
            Press(
              child: FilledButton.icon(
                onPressed: () => context.go('/s/$slug/admin'),
                icon: const Icon(Icons.upload_rounded),
                label: const Text('Upload the first episode'),
              ),
            ),
            Press(
              child: OutlinedButton(
                onPressed: () => context.go('/s/$slug'),
                child: const Text('View public page'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
