import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/platform/browser.dart';
import '../services/services.dart';
import '../services/wallet_upload.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../util/validation.dart';
import 'package:sui_wallet_web/sui_wallet_web.dart' show shortenSuiAddress;

import '../widgets/account.dart';
import '../widgets/common.dart';
import '../widgets/press.dart';
import '../widgets/pending_uploads.dart';
import '../widgets/show_form.dart';
import '../widgets/wallet_write.dart';
import 'show_screen.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key, required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context) => SignedIn(
    title: 'Sign in to manage this show',
    body:
        'Shows belong to the Sui address that created them. Sign in with that '
        'wallet, on any device, to upload and edit episodes.',
    child: _OwnerLoader(key: ValueKey(slug), slug: slug),
  );
}

enum _Load { loading, notOwner, notFound, error, ready }

/// Loads the show for its signed-in owner. 403 means another account.
class _OwnerLoader extends StatefulWidget {
  const _OwnerLoader({super.key, required this.slug});
  final String slug;

  @override
  State<_OwnerLoader> createState() => _OwnerLoaderState();
}

class _OwnerLoaderState extends State<_OwnerLoader> {
  _Load _state = _Load.loading;
  ShowPage? _page;
  String _error = '';
  String? _loadedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final address = context.services.auth.address;
    if (address != _loadedFor) {
      _loadedFor = address;
      _load();
    }
  }

  Future<void> _load() async {
    final services = context.services;
    setState(() => _state = _Load.loading);
    try {
      final page = await services.api.adminShow(widget.slug);
      if (mounted) {
        setState(() {
          _page = page;
          _state = _Load.ready;
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status == 401) {
        services.auth.sessionEnded();
        return;
      }
      setState(() {
        _error = e.message;
        _state = e.status == 403
            ? _Load.notOwner
            : e.notFound
            ? _Load.notFound
            : _Load.error;
      });
    }
  }

  /// Refetches without showing the loading state (keeps tabs and forms).
  Future<void> _refresh() async {
    try {
      final page = await context.services.api.adminShow(widget.slug);
      if (mounted) setState(() => _page = page);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _Load.loading:
        return const PageFrame(
          showFooter: false,
          headerTrailing: AccountChip(),
          children: [LoadingState(label: 'Opening your show')],
        );
      case _Load.notOwner:
        return PageFrame(
          headerTrailing: const AccountChip(),
          children: [
            MessageState(
              title: 'This show belongs to another account',
              body:
                  'You are signed in as ${shortenSuiAddress(context.services.auth.address ?? '')}. '
                  'Sign in with the wallet that created the show to manage it.',
              icon: Icons.key_off_rounded,
              action: Wrap(
                spacing: Space.md,
                runSpacing: Space.md,
                alignment: WrapAlignment.center,
                children: [
                  Press(
                    child: FilledButton(
                      onPressed: () async {
                        try {
                          await context.services.auth.signOut();
                        } catch (_) {
                          if (context.mounted) {
                            showToast(
                              context,
                              'Could not sign out. Check your connection and try again.',
                            );
                          }
                        }
                      },
                      child: const Text('Sign out'),
                    ),
                  ),
                  Press(
                    child: OutlinedButton(
                      onPressed: () => context.go('/s/${widget.slug}'),
                      child: const Text('Go to the public page'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      case _Load.notFound:
        return const PageFrame(
          headerTrailing: AccountChip(),
          children: [NotFoundState(title: 'Show not found')],
        );
      case _Load.error:
        return PageFrame(
          headerTrailing: const AccountChip(),
          children: [ErrorState(message: _error, onRetry: _load)],
        );
      case _Load.ready:
        return _AdminView(
          page: _page!,
          onPage: (p) => setState(() => _page = p),
          reload: _refresh,
        );
    }
  }
}

class _AdminView extends StatefulWidget {
  const _AdminView({
    required this.page,
    required this.onPage,
    required this.reload,
  });

  final ShowPage page;
  final ValueChanged<ShowPage> onPage;
  final VoidCallback reload;

  @override
  State<_AdminView> createState() => _AdminViewState();
}

class _AdminViewState extends State<_AdminView>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, vsync: this)
    ..addListener(() => setState(() {}));

  /// The cover being stored, kept so a second try does not pay twice.
  WalletUpload? _coverUpload;
  Object? _coverSource;

  @override
  void dispose() {
    _tabs.dispose();
    _coverUpload?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final show = page.show;
    final compact = MediaQuery.sizeOf(context).width < 600;
    final maxEpoch = page.episodes
        .map((e) => e.endEpoch ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);

    return PageFrame(
      maxWidth: 960,
      headerTrailing: const AccountChip(),
      children: [
        const SizedBox(height: Space.sm),
        const AuthNotice(),
        EarshotPendingUploads(slug: show.slug, onCompleted: widget.reload),
        const SizedBox(height: Space.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CoverArt(show: show, size: compact ? 64 : 88),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Overline('Admin'),
                  const SizedBox(height: Space.xs),
                  Semantics(
                    header: true,
                    child: Text(show.name, style: TextStyles.headline(compact)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.lg),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            Press(
              child: OutlinedButton.icon(
                onPressed: () => context.go('/s/${show.slug}'),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Public page'),
              ),
            ),
            Press(
              child: OutlinedButton.icon(
                onPressed: () =>
                    copyToClipboard(context, show.publicUrl, 'Public link'),
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text('Copy public link'),
              ),
            ),
            Press(
              child: OutlinedButton.icon(
                onPressed: () =>
                    copyToClipboard(context, show.feedUrl, 'Feed link'),
                icon: const Icon(Icons.rss_feed_rounded, size: 18),
                label: const Text('Copy RSS link'),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.xl),
        TabBar(
          controller: _tabs,
          isScrollable: compact,
          tabAlignment: compact ? TabAlignment.start : null,
          tabs: [
            Tab(text: 'Episodes (${page.episodes.length})'),
            const Tab(text: 'Upload'),
            const Tab(text: 'Show details'),
          ],
        ),
        const SizedBox(height: Space.xl),
        Offstage(
          offstage: _tabs.index != 0,
          child: _EpisodesPanel(
            page: page,
            onPage: widget.onPage,
            onUpload: () => _tabs.animateTo(1),
          ),
        ),
        Offstage(
          offstage: _tabs.index != 1,
          child: _UploadPanel(show: show, onPublished: widget.reload),
        ),
        Offstage(
          offstage: _tabs.index != 2,
          child: ShowForm(
            key: ValueKey(show.coverBlobId),
            initial: show,
            submitLabel: 'Save changes',
            canChangeCover: () =>
                _coverUpload == null || !_coverUpload!.needsRetention,
            onSubmit: (v) => _saveShow(context, v),
          ),
        ),
        const SizedBox(height: Space.xxl),
        Container(
          padding: const EdgeInsets.all(Space.lg),
          decoration: BoxDecoration(
            color: Palette.surface,
            borderRadius: BorderRadius.circular(Radii.card),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: Palette.muted,
                size: 20,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(
                  'Hiding an episode removes it from the show page and the feed. '
                  'The file stays on Walrus until its storage period ends'
                  '${maxEpoch > 0 ? ' (up to epoch $maxEpoch)' : ''}, or until you '
                  'delete it. Your wallet pays for each upload (Earshot suggests '
                  '${_epochs(context.services.config.epochs)}) and owns it as a '
                  'deletable blob at your Sui address.',
                  style: TextStyles.small,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _epochs(int n) => n == 1 ? '1 epoch' : '$n epochs';

  Future<void> _saveShow(BuildContext context, ShowFormValues v) async {
    final services = context.services;
    final fields = <String, Object?>{
      'name': v.name,
      'author': v.author,
      'description': v.description,
      'language': v.language,
      'category': v.category,
      'explicit': v.explicit,
    };
    final cover = v.cover;
    if (cover != null) {
      if (!identical(_coverSource, cover)) {
        _coverUpload?.dispose();
        _coverUpload = services.newUpload(cover.bytes);
        _coverSource = cover;
      }
      _coverUpload!.setRecoveryMetadata({
        'kind': 'cover',
        'label': '${v.name} cover art',
        'slug': widget.page.show.slug,
        'fields': fields,
      });
      final blob = await storeWithWallet(
        context,
        upload: _coverUpload!,
        title: 'Store the cover art',
        what: 'the cover art',
      );
      if (blob == null) {
        throw ApiException(
          0,
          'The cover art is not stored yet. Save again to finish; you will '
          'not pay twice.',
        );
      }
      fields['coverBlobId'] = blob.blobId;
    }
    final ShowPage page;
    try {
      page = await services.api.updateShow(widget.page.show.slug, fields);
      if (cover != null) await _coverUpload?.markListed();
    } catch (_) {
      await _coverUpload?.releaseRecovery();
      rethrow;
    }
    if (!mounted) return;
    widget.onPage(page);
    if (context.mounted) showToast(context, 'Show details saved');
  }
}

// ------------------------------------------------------------------ episodes

class _EpisodesPanel extends StatefulWidget {
  const _EpisodesPanel({
    required this.page,
    required this.onPage,
    required this.onUpload,
  });

  final ShowPage page;
  final ValueChanged<ShowPage> onPage;
  final VoidCallback onUpload;

  @override
  State<_EpisodesPanel> createState() => _EpisodesPanelState();
}

class _EpisodesPanelState extends State<_EpisodesPanel> {
  bool _busy = false;

  Show get show => widget.page.show;

  Future<void> _run(Future<ShowPage?> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final page = await action();
      if (mounted && page != null) widget.onPage(page);
      if (mounted) showToast(context, done);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<ShowPage> _refetch() => context.services.api.adminShow(show.slug);

  /// Moves the episode at [from] so it ends up at index [to].
  void _reorder(int from, int to) {
    final ids = [for (final e in widget.page.episodes) e.id];
    final id = ids.removeAt(from);
    ids.insert(to, id);
    _run(() => context.services.api.reorder(show.slug, ids), 'Order saved');
  }

  void _setHidden(Episode e, bool hidden) => _run(() async {
    await context.services.api.updateEpisode(show.slug, e.id, {
      'hidden': hidden,
    });
    return _refetch();
  }, hidden ? 'Hidden from listeners' : 'Visible to listeners');

  void _pin(Episode e, bool pin) => _run(
    () => context.services.api.pin(show.slug, pin ? e.id : null),
    pin ? 'Pinned to the top' : 'Unpinned',
  );

  Future<void> _edit(Episode e) async {
    final saved = await showDialog<bool>(
      context: context,
      animationStyle: Motion.popover(context),
      builder: (_) => ServicesScope(
        services: context.services,
        child: _EditEpisodeDialog(show: show, episode: e),
      ),
    );
    if (saved == true && mounted) {
      await _run(_refetch, 'Episode saved');
    }
  }

  @override
  Widget build(BuildContext context) {
    final episodes = widget.page.episodes;
    if (episodes.isEmpty) {
      return MessageState(
        title: 'No episodes yet',
        body:
            'Upload a recording and it will appear on the show page and in the feed.',
        icon: Icons.graphic_eq_rounded,
        action: Press(
          child: FilledButton.icon(
            onPressed: widget.onUpload,
            icon: const Icon(Icons.upload_rounded),
            label: const Text('Upload an episode'),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Space.md,
          runSpacing: Space.sm,
          children: [
            const Text('Order on the show page', style: TextStyles.small),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'newest', label: Text('Newest first')),
                ButtonSegment(value: 'custom', label: Text('Custom')),
              ],
              selected: {show.orderMode},
              showSelectedIcon: false,
              style: ButtonStyle(
                minimumSize: const WidgetStatePropertyAll(Size(64, 44)),
                backgroundColor: WidgetStateProperty.resolveWith(
                  (s) => s.contains(WidgetState.selected)
                      ? Palette.amber
                      : Palette.surface,
                ),
                foregroundColor: WidgetStateProperty.resolveWith(
                  (s) => s.contains(WidgetState.selected)
                      ? Palette.night
                      : Palette.cream,
                ),
                side: const WidgetStatePropertyAll(
                  BorderSide(color: Palette.faint),
                ),
              ),
              onSelectionChanged: _busy
                  ? null
                  : (v) {
                      final mode = v.first;
                      if (mode == 'custom') {
                        _reorder(0, 0);
                      } else {
                        _run(
                          () => context.services.api.updateShow(show.slug, {
                            'orderMode': 'newest',
                          }),
                          'Sorted by publish date',
                        );
                      }
                    },
            ),
            if (_busy)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: Space.sm),
        const Text(
          'Drag the handle or use the menu to move an episode. Moving one switches to a custom order.',
          style: TextStyles.small,
        ),
        const SizedBox(height: Space.lg),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: episodes.length,
          onReorderItem: _busy ? (_, _) {} : _reorder,
          proxyDecorator: (child, _, _) => Material(
            color: Palette.raised,
            borderRadius: BorderRadius.circular(Radii.card),
            child: child,
          ),
          itemBuilder: (context, i) {
            final e = episodes[i];
            return _AdminEpisodeRow(
              key: ValueKey(e.id),
              index: i,
              episode: e,
              pinned: show.pinnedEpisodeId == e.id,
              isFirst: i == 0,
              isLast: i == episodes.length - 1,
              onEdit: () => _edit(e),
              onHide: (h) => _setHidden(e, h),
              onPin: (p) => _pin(e, p),
              onMove: (delta) => _reorder(i, i + delta),
              onOpen: () => context.go('/s/${show.slug}/e/${e.id}'),
            );
          },
        ),
      ],
    );
  }
}

class _AdminEpisodeRow extends StatelessWidget {
  const _AdminEpisodeRow({
    super.key,
    required this.index,
    required this.episode,
    required this.pinned,
    required this.isFirst,
    required this.isLast,
    required this.onEdit,
    required this.onHide,
    required this.onPin,
    required this.onMove,
    required this.onOpen,
  });

  final int index;
  final Episode episode;
  final bool pinned;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onEdit;
  final ValueChanged<bool> onHide;
  final ValueChanged<bool> onPin;
  final ValueChanged<int> onMove;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final e = episode;
    final chips = <Widget>[
      if (pinned) const _Badge('Pinned', Palette.amber),
      if (e.hidden) const _Badge('Hidden', Palette.tube),
      if (e.scheduled && !e.hidden)
        _Badge('Scheduled ${shortDate(e.publishAt)}', Palette.glow),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Container(
        decoration: BoxDecoration(
          color: Palette.surface,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(
            color: pinned ? Palette.amber.withValues(alpha: 0.6) : Palette.line,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          Space.xs,
          Space.md,
          Space.xs,
          Space.md,
        ),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Tooltip(
                message: 'Drag to reorder',
                child: Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    color: Palette.faint,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Opacity(
                opacity: e.hidden ? 0.6 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(episodeMeta(e), style: TextStyles.timecode),
                    const SizedBox(height: 4),
                    Text(e.title, style: TextStyles.itemTitle),
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: Space.sm),
                      Wrap(
                        spacing: Space.xs,
                        runSpacing: Space.xs,
                        children: chips,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: 'Edit details',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 20),
            ),
            PopupMenuButton<String>(
              tooltip: 'More actions for ${e.title}',
              // Opens from its trigger, quick in and quicker out.
              popUpAnimationStyle: Motion.popover(context),
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (v) => switch (v) {
                'open' => onOpen(),
                'pin' => onPin(true),
                'unpin' => onPin(false),
                'hide' => onHide(true),
                'show' => onHide(false),
                'up' => onMove(-1),
                'down' => onMove(1),
                _ => null,
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'open',
                  child: Text('Open episode page'),
                ),
                if (!e.hidden)
                  PopupMenuItem(
                    value: pinned ? 'unpin' : 'pin',
                    child: Text(pinned ? 'Unpin' : 'Pin to the top'),
                  ),
                PopupMenuItem(
                  value: e.hidden ? 'show' : 'hide',
                  child: Text(
                    e.hidden ? 'Show to listeners' : 'Hide from listeners',
                  ),
                ),
                if (!isFirst)
                  const PopupMenuItem(value: 'up', child: Text('Move up')),
                if (!isLast)
                  const PopupMenuItem(value: 'down', child: Text('Move down')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(Radii.pill),
      border: Border.all(color: color.withValues(alpha: 0.7)),
    ),
    child: Text(
      text.toUpperCase(),
      style: TextStyles.overline.copyWith(color: color, fontSize: 11),
    ),
  );
}

// --------------------------------------------------------------- date field

class DateTimeField extends StatelessWidget {
  const DateTimeField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Publish date',
  });
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final String label;

  Future<void> _pick(BuildContext context) async {
    final local = value.toLocal();
    final date = await showDatePicker(
      context: context,
      initialDate: local,
      firstDate: DateTime(1990),
      lastDate: DateTime(2100),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(local),
    );
    onChanged(
      DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? local.hour,
        time?.minute ?? local.minute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final future = value.isAfter(
      DateTime.now().add(const Duration(minutes: 1)),
    );
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        helperText: future
            ? 'Scheduled: listeners see it from this date.'
            : 'Listeners see it straight away. Pick a later date to schedule it.',
      ),
      child: Row(
        children: [
          Expanded(child: Text(dateTime(value), style: TextStyles.body)),
          TextButton(
            onPressed: () => _pick(context),
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- edit dialog

class _EditEpisodeDialog extends StatefulWidget {
  const _EditEpisodeDialog({required this.show, required this.episode});
  final Show show;
  final Episode episode;

  @override
  State<_EditEpisodeDialog> createState() => _EditEpisodeDialogState();
}

class _EditEpisodeDialogState extends State<_EditEpisodeDialog> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.episode.title);
  late final _description = TextEditingController(
    text: widget.episode.description,
  );
  late final _duration = TextEditingController(
    text: widget.episode.duration == null
        ? ''
        : clock(widget.episode.duration!),
  );
  late DateTime _publishAt = widget.episode.publishAt.toLocal();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _duration.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = parseClock(_duration.text);
      await context.services.api
          .updateEpisode(widget.show.slug, widget.episode.id, {
            'title': _title.text.trim(),
            'description': _description.text.trim(),
            'publishAt': _publishAt.toUtc().toIso8601String(),
            'durationSeconds': d?.inSeconds,
          });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.fields.values.firstOrNull ?? e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit episode'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Space.sm),
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Title'),
                  maxLength: 200,
                  validator: (v) => requiredText(v, 'Title'),
                ),
                const SizedBox(height: Space.md),
                TextFormField(
                  controller: _description,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    alignLabelWithHint: true,
                  ),
                  minLines: 3,
                  maxLines: 8,
                  maxLength: 10000,
                  validator: (v) => optionalText(v, 'Description', max: 10000),
                ),
                const SizedBox(height: Space.md),
                DateTimeField(
                  value: _publishAt,
                  onChanged: (d) => setState(() => _publishAt = d),
                ),
                const SizedBox(height: Space.lg),
                TextFormField(
                  controller: _duration,
                  decoration: const InputDecoration(
                    labelText: 'Duration',
                    hintText: '42:15',
                    helperText: 'Minutes and seconds. Leave empty if unknown.',
                  ),
                  validator: durationText,
                ),
                if (_error != null) ...[
                  const SizedBox(height: Space.md),
                  Text(
                    _error!,
                    style: TextStyles.small.copyWith(color: Palette.tube),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        Press(
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Saving…' : 'Save'),
          ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------- upload

enum _Stage { pick, details, working, saving, done, failed }

class _UploadPanel extends StatefulWidget {
  const _UploadPanel({required this.show, required this.onPublished});
  final Show show;
  final VoidCallback onPublished;

  @override
  State<_UploadPanel> createState() => _UploadPanelState();
}

class _UploadPanelState extends State<_UploadPanel> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _duration = TextEditingController();
  _Stage _stage = _Stage.pick;
  PickedFile? _file;
  bool _durationFromFile = false;
  String? _fileError;

  /// Saving the episode details failed after the file was listed.
  String? _error;
  DateTime _publishAt = DateTime.now();
  Episode? _published;
  bool _picking = false;

  /// The wallet-paid write of [_file]. Kept after a failure so "Try again"
  /// continues where it stopped; dropped only when the file changes.
  WalletUpload? _upload;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _duration.dispose();
    _upload?.dispose();
    super.dispose();
  }

  static String _titleFromName(String name) {
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    return base
        .replaceAll(RegExp(r'[_]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _pick() async {
    if (_picking || (_upload != null && !_upload!.canReplace)) return;
    final services = context.services;
    setState(() {
      _picking = true;
      _fileError = null;
    });
    try {
      final file = await services.browser.pickFile(accept: audioAccept);
      if (file == null || !mounted) return;
      final head = await file.head();
      if (!mounted) return;
      final problem = checkAudioFile(
        name: file.name,
        size: file.size,
        head: head,
        maxBytes: services.config.maxUploadBytes,
      );
      if (problem != null) {
        setState(() => _fileError = problem);
        return;
      }
      final duration = await services.browser.audioDuration(file);
      if (!mounted) return;
      final bytes = await file.readAll();
      if (!mounted) return;
      // The previous unpaid selection can be discarded.
      _upload?.dispose();
      final upload = services.newUpload(bytes);
      unawaited(upload.loadQuote());
      setState(() {
        _file = file;
        _upload = upload;
        _error = null;
        _stage = _Stage.details;
        if (_title.text.trim().isEmpty) _title.text = _titleFromName(file.name);
        _durationFromFile = duration != null;
        _duration.text = duration == null ? '' : clock(duration);
        _publishAt = DateTime.now();
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _fileError = 'Could not read that file. Try choosing it again.',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _send() async {
    if (_stage == _Stage.working || _stage == _Stage.saving || _picking) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    final services = context.services;
    final upload = _upload!;
    setState(() {
      _stage = _Stage.working;
      _error = null;
    });
    upload.setRecoveryMetadata({
      'kind': 'episode',
      'label': _title.text.trim(),
      'slug': widget.show.slug,
      'title': _title.text.trim(),
      'description': _description.text.trim(),
      'publishAt': _publishAt.toUtc().toIso8601String(),
      'durationSeconds': parseClock(_duration.text)?.inSeconds,
    });
    final blob = await upload.start();
    if (!mounted) return;
    if (blob == null) {
      setState(() => _stage = _Stage.failed);
      return;
    }
    setState(() => _stage = _Stage.saving);
    try {
      final episode = await services.api.createEpisode(
        widget.show.slug,
        title: _title.text.trim(),
        description: _description.text.trim(),
        blobId: blob.blobId,
        publishAt: _publishAt,
        durationSeconds: parseClock(_duration.text)?.inSeconds,
      );
      await upload.markListed();
      if (!mounted) return;
      setState(() {
        _published = episode;
        _stage = _Stage.done;
      });
      widget.onPublished();
    } on ApiException catch (e) {
      await upload.releaseRecovery();
      if (e.status == 401) services.auth.sessionEnded();
      if (mounted) {
        setState(() {
          _error = e.fields.values.firstOrNull ?? e.message;
          _stage = _Stage.failed;
        });
      }
    } catch (_) {
      await upload.releaseRecovery();
      if (mounted) {
        setState(() {
          _error =
              'Could not finish saving the episode. Your upload is saved; try again.';
          _stage = _Stage.failed;
        });
      }
    }
  }

  void _reset() {
    _upload?.dispose();
    setState(() {
      _stage = _Stage.pick;
      _file = null;
      _upload = null;
      _title.clear();
      _description.clear();
      _duration.clear();
      _published = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = context.services.config;
    switch (_stage) {
      case _Stage.pick:
        return _DropZone(
          busy: _picking,
          error: _fileError,
          maxMb: config.maxUploadMb,
          onPick: _pick,
        );
      case _Stage.done:
        final e = _published!;
        return MessageState(
          icon: Icons.check_circle_outline_rounded,
          tone: Palette.moss,
          title: e.scheduled ? 'Episode scheduled' : 'Episode published',
          body: e.scheduled
              ? '"${e.title}" will appear on ${dateTime(e.publishAt)}. '
                    'Your wallet owns the file on Walrus.'
              : '"${e.title}" is live on the show page and in the feed. '
                    'Your wallet owns the file on Walrus.',
          action: Wrap(
            spacing: Space.md,
            runSpacing: Space.md,
            alignment: WrapAlignment.center,
            children: [
              Press(
                child: FilledButton(
                  onPressed: _reset,
                  child: const Text('Upload another'),
                ),
              ),
              if (!e.scheduled)
                Press(
                  child: OutlinedButton(
                    onPressed: () =>
                        context.go('/s/${widget.show.slug}/e/${e.id}'),
                    child: const Text('View episode'),
                  ),
                ),
            ],
          ),
        );
      default:
        return _details(context);
    }
  }

  Widget _details(BuildContext context) {
    final file = _file!;
    final upload = _upload!;
    final working = _stage == _Stage.working || _stage == _Stage.saving;
    // After the file is paid for, its details can still change, but the
    // file cannot without starting a new (paid) write.
    final locked = working || !upload.canReplace;
    return Form(
      key: _form,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(Space.lg),
            decoration: BoxDecoration(
              color: Palette.surface,
              borderRadius: BorderRadius.circular(Radii.card),
              border: Border.all(color: Palette.line),
            ),
            child: Row(
              children: [
                const Icon(Icons.audio_file_outlined, color: Palette.amber),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.name,
                        style: TextStyles.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        [
                          fileSize(file.size),
                          if (_durationFromFile)
                            clock(parseClock(_duration.text) ?? Duration.zero),
                        ].join('  ·  '),
                        style: TextStyles.timecode,
                      ),
                    ],
                  ),
                ),
                if (!locked)
                  TextButton(
                    onPressed: _pick,
                    child: const Text('Change file'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.xl),
          TextFormField(
            controller: _title,
            enabled: !working,
            decoration: const InputDecoration(labelText: 'Episode title'),
            maxLength: 200,
            validator: (v) => requiredText(v, 'Title'),
          ),
          const SizedBox(height: Space.md),
          TextFormField(
            controller: _description,
            enabled: !working,
            decoration: const InputDecoration(
              labelText: 'Description',
              helperText: 'Shown on the episode page and in podcast apps.',
              alignLabelWithHint: true,
            ),
            minLines: 3,
            maxLines: 10,
            maxLength: 10000,
            validator: (v) => optionalText(v, 'Description', max: 10000),
          ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.lg,
            runSpacing: Space.lg,
            children: [
              SizedBox(
                width: 360,
                child: DateTimeField(
                  value: _publishAt,
                  onChanged: working
                      ? (_) {}
                      : (d) => setState(() => _publishAt = d),
                ),
              ),
              SizedBox(
                width: 200,
                child: TextFormField(
                  controller: _duration,
                  enabled: !working,
                  decoration: InputDecoration(
                    labelText: 'Duration',
                    hintText: '42:15',
                    helperText: _durationFromFile
                        ? 'Read from the file.'
                        : 'Your browser could not read it. Type it if you know it.',
                  ),
                  validator: durationText,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xl),
          if (_stage == _Stage.saving)
            const _SavingDetails()
          else if (_error != null)
            _SaveFailed(message: _error!, onRetry: _send)
          else
            WalletWritePanel(
              upload: upload,
              onRetry: _send,
              what: 'this recording',
            ),
          const SizedBox(height: Space.lg),
          if (!working)
            Wrap(
              spacing: Space.md,
              runSpacing: Space.md,
              children: [
                if (_stage == _Stage.details)
                  Press(
                    child: FilledButton.icon(
                      onPressed: _send,
                      icon: const Icon(Icons.upload_rounded),
                      label: const Text('Upload and publish'),
                    ),
                  ),
                TextButton(onPressed: _reset, child: const Text('Cancel')),
              ],
            ),
        ],
      ),
    );
  }
}

class _SavingDetails extends StatelessWidget {
  const _SavingDetails();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Saving episode details…',
      child: const ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(4)),
              child: LinearProgressIndicator(minHeight: 6),
            ),
            SizedBox(height: Space.sm),
            Text('Saving episode details…', style: TextStyles.timecode),
          ],
        ),
      ),
    );
  }
}

/// The file is stored and listed; only the episode details did not save.
class _SaveFailed extends StatelessWidget {
  const _SaveFailed({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: Palette.surface,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: Palette.tube.withValues(alpha: 0.7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline_rounded, color: Palette.tube),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(
                    'The episode was not saved. $message The file is stored; '
                    'trying again does not pay again.',
                    style: TextStyles.small,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.lg),
            Press(
              child: FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DropZone extends StatelessWidget {
  const _DropZone({
    required this.busy,
    required this.error,
    required this.maxMb,
    required this.onPick,
  });
  final bool busy;
  final String? error;
  final int maxMb;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            vertical: Space.xxxl,
            horizontal: Space.xl,
          ),
          decoration: BoxDecoration(
            color: Palette.surface,
            borderRadius: BorderRadius.circular(Radii.card),
            border: Border.all(
              color: error != null ? Palette.tube : Palette.faint,
            ),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.graphic_eq_rounded,
                size: 40,
                color: Palette.amber,
              ),
              const SizedBox(height: Space.lg),
              const Text(
                'Add a recording',
                style: TextStyles.title,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.sm),
              Text(
                'MP3, M4A, AAC, OGG or WAV, up to $maxMb MB.',
                style: TextStyles.small,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.xl),
              Press(
                child: FilledButton.icon(
                  onPressed: busy ? null : onPick,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Palette.night,
                          ),
                        )
                      : const Icon(Icons.folder_open_rounded),
                  label: Text(busy ? 'Reading file…' : 'Choose audio file'),
                ),
              ),
            ],
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: Space.md),
          Semantics(
            liveRegion: true,
            child: Text(
              error!,
              style: TextStyles.small.copyWith(color: Palette.tube),
            ),
          ),
        ],
      ],
    );
  }
}
