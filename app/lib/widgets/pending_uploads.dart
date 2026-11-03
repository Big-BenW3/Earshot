import 'package:flutter/material.dart';
import 'package:upload_recovery/pending_uploads_panel.dart';

import '../services/services.dart';

class EarshotPendingUploads extends StatelessWidget {
  const EarshotPendingUploads({super.key, this.slug, this.onCompleted});
  final String? slug;
  final VoidCallback? onCompleted;

  @override
  Widget build(BuildContext context) {
    final services = context.services;
    final recovery = services.recovery;
    final owner = services.auth.address;
    if (recovery == null || owner == null) return const SizedBox.shrink();
    return PendingUploadsPanel(
      recovery: recovery,
      owner: owner,
      filter: (job) => slug == null || job.metadata['slug'] == slug,
      beforeResume: () async {
        if (!await services.auth.confirmSession() || !context.mounted) {
          return false;
        }
        final connected = await services.auth.connectWallet(context);
        return connected == owner;
      },
      canContinue: () => services.auth.address == owner,
      onCompleted: (_, _) => onCompleted?.call(),
    );
  }
}
