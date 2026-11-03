import 'package:sui_wallet_web/sui_wallet_web.dart';
import 'package:upload_recovery/walrus_recovery.dart';

import 'api_client.dart';

WalrusUploadRecovery createUploadRecovery({
  required EarshotApi api,
  required SuiWalletController wallet,
  required String chain,
  UploadRecoveryStore? store,
}) => WalrusUploadRecovery(
  app: 'earshot',
  chain: chain,
  wallet: wallet,
  store: store,
  finish: (job, stored) => finishRecoveredUpload(api, job, stored),
);

Future<RecoveryCompletion> finishRecoveredUpload(
  EarshotApi api,
  RecoverySummary job,
  RecoveredUpload stored,
) async {
  final metadata = job.metadata;
  final slug = metadata['slug'] as String;
  final blob = await api.claimBlob(stored.objectId);
  switch (metadata['kind']) {
    case 'episode':
      await api.createEpisode(
        slug,
        title: metadata['title'] as String,
        description: metadata['description'] as String,
        blobId: blob.blobId,
        publishAt: DateTime.parse(metadata['publishAt'] as String),
        durationSeconds: metadata['durationSeconds'] as int?,
      );
    case 'cover':
      await api.updateShow(slug, {
        ...Map<String, Object?>.from(metadata['fields'] as Map),
        'coverBlobId': blob.blobId,
      });
    default:
      throw const FormatException('Unknown saved upload type');
  }
  return const RecoveryCompletion.complete();
}
