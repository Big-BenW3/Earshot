import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/platform/browser.dart';
import '../services/services.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../util/validation.dart';
import 'common.dart';
import 'press.dart';

class ShowFormValues {
  const ShowFormValues({
    required this.name,
    required this.author,
    required this.description,
    required this.language,
    required this.category,
    required this.explicit,
    required this.cover,
  });

  final String name;
  final String author;
  final String description;
  final String language;
  final String category;
  final bool explicit;

  /// A newly chosen cover, or null to keep the current one.
  final PreparedImage? cover;
}

/// Create and edit form for a show. [onSubmit] throws [ApiException] for
/// field errors, or returns normally.
class ShowForm extends StatefulWidget {
  const ShowForm({
    super.key,
    this.initial,
    required this.submitLabel,
    required this.onSubmit,
    this.progress,
    this.canChangeCover,
  });

  final Show? initial;
  final String submitLabel;
  final Future<void> Function(ShowFormValues values) onSubmit;

  /// Status line while submitting, e.g. "Uploading cover art, 40%".
  final ValueNotifier<String?>? progress;
  final bool Function()? canChangeCover;

  @override
  State<ShowForm> createState() => _ShowFormState();
}

class _ShowFormState extends State<ShowForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _author = TextEditingController(text: widget.initial?.author);
  late final _description = TextEditingController(
    text: widget.initial?.description,
  );
  late String _language = widget.initial?.language ?? 'en';
  late String? _category = widget.initial?.category;
  late bool _explicit = widget.initial?.explicit ?? false;
  PreparedImage? _cover;
  String? _coverError;
  bool _pickingCover = false;
  bool _busy = false;
  bool _submitted = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    _name.dispose();
    _author.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    if (_pickingCover || _busy || !(widget.canChangeCover?.call() ?? true)) {
      return;
    }
    final services = context.services;
    setState(() {
      _pickingCover = true;
      _coverError = null;
    });
    try {
      final file = await services.browser.pickFile(accept: imageAccept);
      if (file == null || !mounted) return;
      final head = await file.head();
      if (!mounted) return;
      final problem = checkImageFile(
        name: file.name,
        size: file.size,
        head: head,
        // Large photos are scaled down before upload, so allow bigger input.
        maxBytes: 40 * 1024 * 1024,
      );
      if (problem != null) {
        setState(() => _coverError = problem);
        return;
      }
      final prepared = await services.browser.prepareCover(file);
      if (!mounted) return;
      if (prepared == null) {
        setState(
          () => _coverError = '${file.name} could not be read as an image.',
        );
        return;
      }
      if (prepared.bytes.length > services.config.maxImageBytes) {
        setState(
          () => _coverError =
              'This image is still ${fileSize(prepared.bytes.length)} after resizing. '
              'Cover images can be up to ${services.config.maxImageMb} MB.',
        );
        return;
      }
      setState(() => _cover = prepared);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _coverError = 'Could not read that image. Try choosing it again.',
        );
      }
    } finally {
      if (mounted) setState(() => _pickingCover = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || _pickingCover) return;
    setState(() {
      _error = null;
      _fieldErrors = const {};
      _submitted = true;
    });
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await widget.onSubmit(
        ShowFormValues(
          name: _name.text.trim(),
          author: _author.text.trim(),
          description: _description.text.trim(),
          language: _language,
          category: _category!,
          explicit: _explicit,
          cover: _cover,
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _fieldErrors = e.fields;
          _error = e.fields.isEmpty
              ? e.message
              : 'Check the highlighted fields.';
        });
        _form.currentState?.validate();
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _server(String field) => _fieldErrors[field];

  @override
  Widget build(BuildContext context) {
    final categories = context.services.config.categories;
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final cover = _CoverPicker(
      show: widget.initial,
      chosen: _cover,
      error: _coverError,
      busy: _pickingCover,
      onPick: _busy || !(widget.canChangeCover?.call() ?? true)
          ? null
          : _pickCover,
    );
    final fields = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Show name'),
          textInputAction: TextInputAction.next,
          maxLength: 120,
          validator: (v) =>
              requiredText(v, 'Show name', max: 120) ?? _server('name'),
        ),
        const SizedBox(height: Space.md),
        TextFormField(
          controller: _author,
          decoration: const InputDecoration(
            labelText: 'Author or host',
            helperText:
                'The church, department, group or person behind the show.',
          ),
          textInputAction: TextInputAction.next,
          maxLength: 120,
          validator: (v) =>
              requiredText(v, 'Author', max: 120) ?? _server('author'),
        ),
        const SizedBox(height: Space.md),
        TextFormField(
          controller: _description,
          decoration: const InputDecoration(
            labelText: 'Description',
            helperText: 'Shown on the show page and in podcast apps.',
            alignLabelWithHint: true,
          ),
          minLines: 3,
          maxLines: 8,
          maxLength: 4000,
          validator: (v) =>
              optionalText(v, 'Description') ?? _server('description'),
        ),
        const SizedBox(height: Space.md),
        Wrap(
          spacing: Space.lg,
          runSpacing: Space.lg,
          children: [
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                initialValue: _language,
                decoration: const InputDecoration(labelText: 'Language'),
                dropdownColor: Palette.raised,
                style: TextStyles.body,
                isExpanded: true,
                items: [
                  for (final (code, name) in languages)
                    DropdownMenuItem(value: code, child: Text(name)),
                  if (!languages.any((l) => l.$1 == _language))
                    DropdownMenuItem(value: _language, child: Text(_language)),
                ],
                onChanged: (v) => setState(() => _language = v ?? 'en'),
              ),
            ),
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String>(
                initialValue: categories.contains(_category) ? _category : null,
                decoration: const InputDecoration(labelText: 'Category'),
                dropdownColor: Palette.raised,
                style: TextStyles.body,
                isExpanded: true,
                items: [
                  for (final c in categories)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                validator: (v) =>
                    v == null ? 'Choose a category.' : _server('category'),
                onChanged: (v) => setState(() => _category = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        SwitchListTile(
          value: _explicit,
          onChanged: (v) => setState(() => _explicit = v),
          contentPadding: EdgeInsets.zero,
          title: const Text('Explicit content', style: TextStyles.label),
          subtitle: const Text(
            'Podcast apps label the show as explicit.',
            style: TextStyles.small,
          ),
        ),
      ],
    );

    return Form(
      key: _form,
      // After a failed submit, errors clear as soon as the field is fixed.
      autovalidateMode: _submitted
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 240, child: cover),
                const SizedBox(width: Space.xxl),
                Expanded(child: fields),
              ],
            )
          else ...[
            cover,
            const SizedBox(height: Space.xl),
            fields,
          ],
          const SizedBox(height: Space.xl),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.md),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyles.small.copyWith(color: Palette.tube),
                ),
              ),
            ),
          Wrap(
            spacing: Space.lg,
            runSpacing: Space.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Press(
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? 'Saving…' : widget.submitLabel),
                ),
              ),
              if (_busy && widget.progress != null)
                ValueListenableBuilder<String?>(
                  valueListenable: widget.progress!,
                  builder: (context, text, _) => text == null
                      ? const SizedBox.shrink()
                      : Semantics(
                          liveRegion: true,
                          child: Text(text, style: TextStyles.small),
                        ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CoverPicker extends StatelessWidget {
  const _CoverPicker({
    required this.show,
    required this.chosen,
    required this.error,
    required this.busy,
    required this.onPick,
  });

  final Show? show;
  final PreparedImage? chosen;
  final String? error;
  final bool busy;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    const size = 200.0;
    final preview = chosen != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(Radii.cover),
            child: Image.memory(
              chosen!.bytes,
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
          )
        : show != null && show!.coverBlobId != null
        ? CoverArt(show: show!, size: size)
        : Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Palette.surface,
              borderRadius: BorderRadius.circular(Radii.cover),
              border: Border.all(color: Palette.faint),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.image_outlined, size: 36, color: Palette.faint),
                SizedBox(height: Space.sm),
                Text('No cover yet', style: TextStyles.small),
              ],
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Overline('Cover art', color: Palette.muted),
        const SizedBox(height: Space.sm),
        Semantics(label: 'Cover art preview', image: true, child: preview),
        const SizedBox(height: Space.md),
        Press(
          child: OutlinedButton.icon(
            onPressed: busy ? null : onPick,
            icon: busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_rounded),
            label: Text(
              chosen != null || show?.coverBlobId != null
                  ? 'Change image'
                  : 'Choose image',
            ),
          ),
        ),
        const SizedBox(height: Space.sm),
        Text(
          chosen != null
              ? '${chosen!.width} × ${chosen!.height} px, ${fileSize(chosen!.bytes.length)}'
                    '${chosen!.adjusted ? '. Cropped to a square.' : '.'}'
              : 'Square, ideally 1400 to 3000 px. PNG, JPEG or WebP. Other shapes '
                    'are cropped to a square.',
          style: TextStyles.small,
        ),
        if (chosen != null && chosen!.width < 1400)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(
              'Podcast apps prefer at least 1400 × 1400 px.',
              style: TextStyles.small.copyWith(color: Palette.glow),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Semantics(
              liveRegion: true,
              child: Text(
                error!,
                style: TextStyles.small.copyWith(color: Palette.tube),
              ),
            ),
          ),
      ],
    );
  }
}
