/// Data shapes returned by the Earshot API.
library;

class AppConfig {
  const AppConfig({
    required this.aggregatorUrl,
    required this.network,
    required this.epochs,
    required this.maxUploadMb,
    required this.maxImageMb,
    required this.publicBaseUrl,
    required this.categories,
    this.suiChain = 'sui:testnet',
  });

  factory AppConfig.fromJson(Map<String, Object?> j) => AppConfig(
    aggregatorUrl: Uri.parse(j['aggregatorUrl'] as String),
    network: j['network'] as String? ?? 'testnet',
    epochs: (j['epochs'] as num?)?.toInt() ?? 0,
    maxUploadMb: (j['maxUploadMb'] as num?)?.toInt() ?? 100,
    maxImageMb: (j['maxImageMb'] as num?)?.toInt() ?? 5,
    publicBaseUrl: j['publicBaseUrl'] as String? ?? '',
    categories: [
      for (final c in (j['categories'] as List?) ?? const []) c as String,
    ],
    suiChain: j['suiChain'] as String? ?? 'sui:testnet',
  );

  final Uri aggregatorUrl;
  final String network;
  final int epochs;
  final int maxUploadMb;
  final int maxImageMb;
  final String publicBaseUrl;
  final List<String> categories;

  /// Wallet Standard chain id hosts sign in on, e.g. `sui:testnet`.
  final String suiChain;

  int get maxUploadBytes => maxUploadMb * 1024 * 1024;
  int get maxImageBytes => maxImageMb * 1024 * 1024;
}

class Show {
  const Show({
    required this.slug,
    required this.name,
    required this.description,
    required this.author,
    required this.language,
    required this.category,
    required this.explicit,
    required this.coverBlobId,
    required this.coverUrl,
    required this.orderMode,
    required this.pinnedEpisodeId,
    required this.publicUrl,
    required this.feedUrl,
  });

  factory Show.fromJson(Map<String, Object?> j) => Show(
    slug: j['slug'] as String,
    name: j['name'] as String,
    description: j['description'] as String? ?? '',
    author: j['author'] as String? ?? '',
    language: j['language'] as String? ?? 'en',
    category: j['category'] as String? ?? '',
    explicit: j['explicit'] as bool? ?? false,
    coverBlobId: j['coverBlobId'] as String?,
    coverUrl: j['coverUrl'] as String?,
    orderMode: j['orderMode'] as String? ?? 'newest',
    pinnedEpisodeId: j['pinnedEpisodeId'] as String?,
    publicUrl: j['publicUrl'] as String? ?? '',
    feedUrl: j['feedUrl'] as String? ?? '',
  );

  final String slug;
  final String name;
  final String description;
  final String author;
  final String language;
  final String category;
  final bool explicit;
  final String? coverBlobId;
  final String? coverUrl;
  final String orderMode;
  final String? pinnedEpisodeId;
  final String publicUrl;
  final String feedUrl;

  bool get customOrder => orderMode == 'custom';
}

class Episode {
  const Episode({
    required this.id,
    required this.title,
    required this.description,
    required this.publishAt,
    required this.durationSeconds,
    required this.blobId,
    required this.mime,
    required this.sizeBytes,
    required this.endEpoch,
    required this.audioUrl,
    required this.pageUrl,
    required this.pinned,
    this.hidden = false,
    this.scheduled = false,
  });

  factory Episode.fromJson(Map<String, Object?> j) => Episode(
    id: j['id'] as String,
    title: j['title'] as String,
    description: j['description'] as String? ?? '',
    publishAt: DateTime.parse(j['publishAt'] as String),
    durationSeconds: (j['durationSeconds'] as num?)?.toInt(),
    blobId: j['blobId'] as String,
    mime: j['mime'] as String? ?? 'audio/mpeg',
    sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
    endEpoch: (j['endEpoch'] as num?)?.toInt(),
    audioUrl: j['audioUrl'] as String,
    pageUrl: j['pageUrl'] as String? ?? '',
    pinned: j['pinned'] as bool? ?? false,
    hidden: j['hidden'] as bool? ?? false,
    scheduled: j['scheduled'] as bool? ?? false,
  );

  final String id;
  final String title;
  final String description;
  final DateTime publishAt;
  final int? durationSeconds;
  final String blobId;
  final String mime;
  final int sizeBytes;
  final int? endEpoch;
  final String audioUrl;
  final String pageUrl;
  final bool pinned;
  final bool hidden;
  final bool scheduled;

  Duration? get duration =>
      durationSeconds == null ? null : Duration(seconds: durationSeconds!);

  /// File extension for downloads, from the stored type.
  String get extension => switch (mime) {
    'audio/mpeg' => 'mp3',
    'audio/x-m4a' || 'audio/mp4' => 'm4a',
    'audio/aac' => 'aac',
    'audio/ogg' => 'ogg',
    'audio/wav' => 'wav',
    _ => 'audio',
  };
}

/// A show with its episodes, as the show page and admin load it.
class ShowPage {
  const ShowPage(this.show, this.episodes);

  factory ShowPage.fromJson(Map<String, Object?> j) =>
      ShowPage(Show.fromJson(j['show'] as Map<String, Object?>), [
        for (final e in j['episodes'] as List)
          Episode.fromJson(e as Map<String, Object?>),
      ]);

  final Show show;
  final List<Episode> episodes;

  Episode? get pinned {
    final id = show.pinnedEpisodeId;
    if (id == null) return null;
    for (final e in episodes) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Listener order: everything except the pinned episode.
  List<Episode> get unpinned =>
      episodes.where((e) => e.id != show.pinnedEpisodeId).toList();
}

class CreatedShow {
  const CreatedShow({
    required this.show,
    required this.publicUrl,
    required this.feedUrl,
  });

  factory CreatedShow.fromJson(Map<String, Object?> j) => CreatedShow(
    show: Show.fromJson(j['show'] as Map<String, Object?>),
    publicUrl: j['publicUrl'] as String,
    feedUrl: j['feedUrl'] as String,
  );

  final Show show;
  final String publicUrl;
  final String feedUrl;
}

/// One of the signed-in host's shows, as `/app` lists them.
class MyShow {
  const MyShow(this.show, this.episodeCount);

  factory MyShow.fromJson(Map<String, Object?> j) =>
      MyShow(Show.fromJson(j), (j['episodeCount'] as num?)?.toInt() ?? 0);

  final Show show;
  final int episodeCount;
}

/// What the server recorded when it listed a blob the host stored with
/// their own wallet (`POST /api/blobs`). Every field comes from the
/// server's checks on Sui and of the blob's first bytes.
class ClaimedBlob {
  const ClaimedBlob({
    required this.objectId,
    required this.blobId,
    required this.mime,
    required this.kind,
    required this.sizeBytes,
    required this.startEpoch,
    required this.endEpoch,
  });

  factory ClaimedBlob.fromJson(Map<String, Object?> j) => ClaimedBlob(
    objectId: j['objectId'] as String,
    blobId: j['blobId'] as String,
    mime: j['mime'] as String,
    kind: j['kind'] as String,
    sizeBytes: (j['sizeBytes'] as num).toInt(),
    startEpoch: (j['startEpoch'] as num).toInt(),
    endEpoch: (j['endEpoch'] as num).toInt(),
  );

  /// The Sui `Blob` object, owned by the host's address.
  final String objectId;
  final String blobId;
  final String mime;

  /// `audio` or `image`.
  final String kind;
  final int sizeBytes;
  final int startEpoch;
  final int endEpoch;
}
