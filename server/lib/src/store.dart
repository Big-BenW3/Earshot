import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'keys.dart' show newId;
import 'sniff.dart';
import 'validation.dart';

class ShowRecord {
  ShowRecord({
    required this.id,
    required this.ownerAddress,
    required this.slug,
    required this.name,
    required this.description,
    required this.author,
    required this.language,
    required this.category,
    required this.explicit,
    required this.coverBlobId,
    required this.coverMime,
    required this.orderMode,
    required this.pinnedEpisodeId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ShowRecord.fromRow(Row r) => ShowRecord(
    id: r['id'] as int,
    ownerAddress: r['owner_address'] as String,
    slug: r['slug'] as String,
    name: r['name'] as String,
    description: r['description'] as String,
    author: r['author'] as String,
    language: r['language'] as String,
    category: r['category'] as String,
    explicit: (r['explicit'] as int) == 1,
    coverBlobId: r['cover_blob_id'] as String?,
    coverMime: r['cover_mime'] as String?,
    orderMode: r['order_mode'] as String,
    pinnedEpisodeId: r['pinned_episode_id'] as String?,
    createdAt: DateTime.parse(r['created_at'] as String),
    updatedAt: DateTime.parse(r['updated_at'] as String),
  );

  final int id;

  /// The verified Sui address of the host who created the show.
  final String ownerAddress;
  final String slug;
  final String name;
  final String description;
  final String author;
  final String language;
  final String category;
  final bool explicit;
  final String? coverBlobId;
  final String? coverMime;

  /// `newest` (by publish date) or `custom` (admin ordered).
  final String orderMode;
  final String? pinnedEpisodeId;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class EpisodeRecord {
  EpisodeRecord({
    required this.id,
    required this.showId,
    required this.title,
    required this.description,
    required this.publishAt,
    required this.blobId,
    required this.mime,
    required this.sizeBytes,
    required this.durationSeconds,
    required this.endEpoch,
    required this.hidden,
    required this.position,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EpisodeRecord.fromRow(Row r) => EpisodeRecord(
    id: r['id'] as String,
    showId: r['show_id'] as int,
    title: r['title'] as String,
    description: r['description'] as String,
    publishAt: DateTime.parse(r['publish_at'] as String),
    blobId: r['blob_id'] as String,
    mime: r['mime'] as String,
    sizeBytes: r['size_bytes'] as int,
    durationSeconds: r['duration_seconds'] as int?,
    endEpoch: r['end_epoch'] as int?,
    hidden: (r['hidden'] as int) == 1,
    position: r['position'] as int,
    createdAt: DateTime.parse(r['created_at'] as String),
    updatedAt: DateTime.parse(r['updated_at'] as String),
  );

  final String id;
  final int showId;
  final String title;
  final String description;
  final DateTime publishAt;
  final String blobId;
  final String mime;
  final int sizeBytes;
  final int? durationSeconds;
  final int? endEpoch;
  final bool hidden;
  final int position;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool isPublic(DateTime now) => !hidden && !publishAt.isAfter(now);
}

/// A Walrus blob a host stored with their own wallet and then claimed here.
/// Every field comes from the server's own checks: the Blob object on Sui
/// (owner, blob ID, size, epochs) and the blob's first bytes (type).
class UploadRecord {
  UploadRecord({
    required this.objectId,
    required this.blobId,
    required this.ownerAddress,
    required this.kind,
    required this.mime,
    required this.sizeBytes,
    required this.startEpoch,
    required this.endEpoch,
  });

  factory UploadRecord.fromRow(Row r) => UploadRecord(
    objectId: r['object_id'] as String,
    blobId: r['blob_id'] as String,
    ownerAddress: r['owner_address'] as String,
    kind: UploadKind.values.byName(r['kind'] as String),
    mime: r['mime'] as String,
    sizeBytes: r['size_bytes'] as int,
    startEpoch: r['start_epoch'] as int,
    endEpoch: r['end_epoch'] as int,
  );

  /// The Sui `Blob` object. Each one can be claimed once.
  final String objectId;
  final String blobId;

  /// The address that owned the Blob object when it was checked: the
  /// signed-in host, who paid for it.
  final String ownerAddress;
  final UploadKind kind;

  /// Sniffed from the blob's first bytes, never taken from the client.
  final String mime;

  /// The size registered on Sui.
  final int sizeBytes;
  final int startEpoch;

  /// Storage ends at the start of this Walrus epoch.
  final int endEpoch;

  Map<String, Object> toJson() => {
    'objectId': objectId,
    'blobId': blobId,
    'owner': ownerAddress,
    'kind': kind.name,
    'mime': mime,
    'sizeBytes': sizeBytes,
    'startEpoch': startEpoch,
    'endEpoch': endEpoch,
  };
}

class NotFoundException implements Exception {
  NotFoundException(this.message);
  final String message;
}

/// SQLite-backed metadata store. Files themselves live on Walrus.
class Store {
  Store._(this._db) {
    _db.execute('PRAGMA foreign_keys = ON;');
    _db.execute('PRAGMA journal_mode = WAL;');
    _migrate();
  }

  /// Opens (or creates) `earshot.db` inside [dataDir].
  factory Store.open(String dataDir) {
    Directory(dataDir).createSync(recursive: true);
    final db = sqlite3.open(p.join(dataDir, 'earshot.db'));
    try {
      return Store._(db);
    } catch (_) {
      db.dispose();
      rethrow;
    }
  }

  factory Store.inMemory() => Store._(sqlite3.openInMemory());

  final Database _db;

  /// Shared with sui_auth's session and nonce tables (prefixed `sui_auth_`).
  Database get db => _db;

  /// Clock, replaceable in tests.
  DateTime Function() now = () => DateTime.now().toUtc();

  void close() => _db.dispose();

  void _migrate() {
    final version =
        _db.select('PRAGMA user_version').single.values.single as int;
    if (version > 1) {
      throw StateError('This database requires a newer Earshot version.');
    }
    final old = _db.select(
      "SELECT 1 FROM pragma_table_info('shows') WHERE name = 'admin_key_hash'",
    );
    if (old.isNotEmpty) {
      throw StateError(
        'This database uses the old admin-link model. Earshot now signs hosts '
        'in with a Sui wallet. Keep a backup and migrate the database before starting.',
      );
    }
    // Uploads recorded by the old publisher proxy (keyed by blob ID, without
    // start epochs) need an explicit migration before wallet claims are accepted.
    final proxyUploads = _db.select(
      "SELECT 1 FROM pragma_table_info('uploads') WHERE name = 'blob_id'",
    );
    final claims = _db.select(
      "SELECT 1 FROM pragma_table_info('uploads') WHERE name = 'start_epoch'",
    );
    if (proxyUploads.isNotEmpty && claims.isEmpty) {
      throw StateError(
        'This database uses legacy publisher uploads. Keep a backup and migrate it before starting.',
      );
    }
    _db.execute('''
      CREATE TABLE IF NOT EXISTS shows (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        slug TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        author TEXT NOT NULL DEFAULT '',
        language TEXT NOT NULL DEFAULT 'en',
        category TEXT NOT NULL DEFAULT 'Society & Culture',
        explicit INTEGER NOT NULL DEFAULT 0,
        cover_blob_id TEXT,
        cover_mime TEXT,
        order_mode TEXT NOT NULL DEFAULT 'newest',
        pinned_episode_id TEXT,
        owner_address TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS shows_by_owner ON shows(owner_address, created_at);
      CREATE TABLE IF NOT EXISTS uploads (
        object_id TEXT PRIMARY KEY,
        blob_id TEXT NOT NULL,
        owner_address TEXT NOT NULL,
        kind TEXT NOT NULL,
        mime TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        start_epoch INTEGER NOT NULL,
        end_epoch INTEGER NOT NULL,
        created_at TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS uploads_by_owner ON uploads(owner_address, blob_id);
      CREATE TABLE IF NOT EXISTS episodes (
        id TEXT PRIMARY KEY,
        show_id INTEGER NOT NULL REFERENCES shows(id) ON DELETE CASCADE,
        title TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        publish_at TEXT NOT NULL,
        blob_id TEXT NOT NULL,
        mime TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        duration_seconds INTEGER,
        end_epoch INTEGER,
        hidden INTEGER NOT NULL DEFAULT 0,
        position INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS episodes_show ON episodes(show_id, publish_at);
    ''');
    if (version == 0) {
      _db.execute('''
        BEGIN;
        ALTER TABLE episodes ADD COLUMN upload_object_id TEXT;
        UPDATE episodes SET upload_object_id = (
          SELECT u.object_id FROM uploads u JOIN shows s ON s.owner_address = u.owner_address
          WHERE s.id = episodes.show_id AND u.blob_id = episodes.blob_id
          ORDER BY u.end_epoch DESC LIMIT 1
        ) WHERE id = (SELECT e.id FROM episodes e WHERE e.show_id = episodes.show_id
          AND e.blob_id = episodes.blob_id ORDER BY e.created_at, e.id LIMIT 1);
        CREATE UNIQUE INDEX episodes_by_upload ON episodes(show_id, upload_object_id)
          WHERE upload_object_id IS NOT NULL;
        PRAGMA user_version = 1;
        COMMIT;
      ''');
    }
  }

  String _stamp() => now().toIso8601String();

  // ---------------------------------------------------------------- shows

  /// Creates a show owned by [ownerAddress] (a verified, signed-in address).
  ShowRecord createShow({
    required String ownerAddress,
    required String name,
    required String description,
    required String author,
    required String language,
    required String category,
    required bool explicit,
  }) {
    final base = slugify(name);
    var slug = base;
    var n = 2;
    while (_db.select('SELECT 1 FROM shows WHERE slug = ?', [
          slug,
        ]).isNotEmpty ||
        _reservedSlugs.contains(slug)) {
      slug = '$base-$n';
      n++;
    }
    final stamp = _stamp();
    _db.execute(
      'INSERT INTO shows (slug, name, description, author, language, category, '
      'explicit, owner_address, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        slug,
        name,
        description,
        author,
        language,
        category,
        explicit ? 1 : 0,
        ownerAddress,
        stamp,
        stamp,
      ],
    );
    return showBySlug(slug)!;
  }

  static const _reservedSlugs = {'new', 'admin', 'api', 'feed', 'walrus'};

  ShowRecord? showBySlug(String slug) {
    final rows = _db.select('SELECT * FROM shows WHERE slug = ?', [slug]);
    return rows.isEmpty ? null : ShowRecord.fromRow(rows.first);
  }

  /// Every show a host owns, newest first: what `/app` lists on any device.
  List<ShowRecord> showsOwnedBy(String ownerAddress) => _db
      .select(
        'SELECT * FROM shows WHERE owner_address = ? ORDER BY created_at DESC, id DESC',
        [ownerAddress],
      )
      .map(ShowRecord.fromRow)
      .toList();

  int episodeCount(ShowRecord show) =>
      _db.select('SELECT COUNT(*) AS n FROM episodes WHERE show_id = ?', [
            show.id,
          ]).first['n']
          as int;

  ShowRecord updateShow(
    ShowRecord show, {
    String? name,
    String? description,
    String? author,
    String? language,
    String? category,
    bool? explicit,
    String? coverBlobId,
    String? coverMime,
    String? orderMode,
  }) {
    _db.execute(
      'UPDATE shows SET name = COALESCE(?, name), description = COALESCE(?, description), '
      'author = COALESCE(?, author), language = COALESCE(?, language), '
      'category = COALESCE(?, category), explicit = COALESCE(?, explicit), '
      'cover_blob_id = COALESCE(?, cover_blob_id), cover_mime = COALESCE(?, cover_mime), '
      'order_mode = COALESCE(?, order_mode), updated_at = ? WHERE id = ?',
      [
        name,
        description,
        author,
        language,
        category,
        explicit == null ? null : (explicit ? 1 : 0),
        coverBlobId,
        coverMime,
        orderMode,
        _stamp(),
        show.id,
      ],
    );
    return showBySlug(show.slug)!;
  }

  void setPinned(ShowRecord show, String? episodeId) {
    _db.execute(
      'UPDATE shows SET pinned_episode_id = ?, updated_at = ? WHERE id = ?',
      [episodeId, _stamp(), show.id],
    );
  }

  void unpinIfCurrent(ShowRecord show, String episodeId) {
    _db.execute(
      'UPDATE shows SET pinned_episode_id = NULL, updated_at = ? WHERE id = ? AND pinned_episode_id = ?',
      [_stamp(), show.id, episodeId],
    );
  }

  // -------------------------------------------------------------- uploads

  /// Records a claimed blob. Returns false when the object was claimed
  /// already (by anyone).
  bool recordUpload(UploadRecord upload) {
    _db.execute(
      'INSERT OR IGNORE INTO uploads (object_id, blob_id, owner_address, kind, '
      'mime, size_bytes, start_epoch, end_epoch, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        upload.objectId,
        upload.blobId,
        upload.ownerAddress,
        upload.kind.name,
        upload.mime,
        upload.sizeBytes,
        upload.startEpoch,
        upload.endEpoch,
        _stamp(),
      ],
    );
    return _db.updatedRows == 1;
  }

  UploadRecord? uploadByObject(String objectId) {
    final rows = _db.select('SELECT * FROM uploads WHERE object_id = ?', [
      objectId,
    ]);
    return rows.isEmpty ? null : UploadRecord.fromRow(rows.first);
  }

  /// Whether a Blob object has been claimed already.
  bool isClaimed(String objectId) => _db.select(
    'SELECT 1 FROM uploads WHERE object_id = ?',
    [objectId],
  ).isNotEmpty;

  /// The owner's claim for [blobId]. The same file stored twice has one blob
  /// ID and two Blob objects; the one stored longest wins.
  UploadRecord? upload(String ownerAddress, String blobId) {
    final rows = _db.select(
      'SELECT * FROM uploads WHERE owner_address = ? AND blob_id = ? '
      'ORDER BY end_epoch DESC LIMIT 1',
      [ownerAddress, blobId],
    );
    return rows.isEmpty ? null : UploadRecord.fromRow(rows.first);
  }

  // ------------------------------------------------------------- episodes

  EpisodeRecord createEpisode({
    required ShowRecord show,
    required UploadRecord upload,
    required String title,
    required String description,
    required DateTime publishAt,
    required int? durationSeconds,
  }) {
    final existing = _db.select(
      'SELECT * FROM episodes WHERE show_id = ? AND upload_object_id = ?',
      [show.id, upload.objectId],
    );
    if (existing.isNotEmpty) return EpisodeRecord.fromRow(existing.first);
    final id = newId();
    final stamp = _stamp();
    // New episodes go to the top of a custom order.
    final minRow = _db.select(
      'SELECT MIN(position) AS m FROM episodes WHERE show_id = ?',
      [show.id],
    );
    final min = (minRow.first['m'] as int?) ?? 0;
    _db.execute(
      'INSERT INTO episodes (id, show_id, title, description, publish_at, '
      'blob_id, mime, size_bytes, duration_seconds, end_epoch, hidden, '
      'position, created_at, updated_at, upload_object_id) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?)',
      [
        id,
        show.id,
        title,
        description,
        publishAt.toUtc().toIso8601String(),
        upload.blobId,
        upload.mime,
        upload.sizeBytes,
        durationSeconds,
        upload.endEpoch,
        min - 1,
        stamp,
        stamp,
        upload.objectId,
      ],
    );
    return episode(show.id, id)!;
  }

  EpisodeRecord? episode(int showId, String id) {
    final rows = _db.select(
      'SELECT * FROM episodes WHERE show_id = ? AND id = ?',
      [showId, id],
    );
    return rows.isEmpty ? null : EpisodeRecord.fromRow(rows.first);
  }

  EpisodeRecord updateEpisode(
    EpisodeRecord episode, {
    String? title,
    String? description,
    DateTime? publishAt,
    bool? hidden,
    bool setDuration = false,
    int? durationSeconds,
  }) {
    _db.execute(
      'UPDATE episodes SET title = COALESCE(?, title), description = COALESCE(?, description), '
      'publish_at = COALESCE(?, publish_at), hidden = COALESCE(?, hidden), '
      'duration_seconds = CASE WHEN ? THEN ? ELSE duration_seconds END, updated_at = ? WHERE id = ?',
      [
        title,
        description,
        publishAt?.toUtc().toIso8601String(),
        hidden == null ? null : (hidden ? 1 : 0),
        setDuration ? 1 : 0,
        durationSeconds,
        _stamp(),
        episode.id,
      ],
    );
    return this.episode(episode.showId, episode.id)!;
  }

  /// All episodes of a show in display order. Hidden and scheduled episodes
  /// are included only when [includePrivate] is true.
  List<EpisodeRecord> episodes(ShowRecord show, {bool includePrivate = false}) {
    final order = show.orderMode == 'custom'
        ? 'position ASC, publish_at DESC'
        : 'publish_at DESC, created_at DESC';
    final rows = _db.select(
      'SELECT * FROM episodes WHERE show_id = ? ORDER BY $order',
      [show.id],
    );
    final list = rows.map(EpisodeRecord.fromRow).toList();
    if (includePrivate) return list;
    final t = now();
    return list.where((e) => e.isPublic(t)).toList();
  }

  /// Saves a custom order. [ids] must list every episode of the show once.
  void reorder(ShowRecord show, List<String> ids) {
    final existing = _db
        .select('SELECT id FROM episodes WHERE show_id = ?', [show.id])
        .map((r) => r['id'] as String)
        .toSet();
    if (ids.length != existing.length ||
        ids.toSet().length != ids.length ||
        !existing.containsAll(ids)) {
      throw ValidationException({
        'episodeIds': 'The order must list every episode exactly once.',
      });
    }
    _db.execute('BEGIN');
    try {
      final stmt = _db.prepare(
        'UPDATE episodes SET position = ? WHERE id = ? AND show_id = ?',
      );
      for (var i = 0; i < ids.length; i++) {
        stmt.execute([i, ids[i], show.id]);
      }
      stmt.dispose();
      _db.execute(
        "UPDATE shows SET order_mode = 'custom', updated_at = ? WHERE id = ?",
        [_stamp(), show.id],
      );
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }
}
