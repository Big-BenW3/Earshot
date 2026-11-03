/// Formatting helpers for times, dates and sizes.
library;

String _two(int v) => v.toString().padLeft(2, '0');

/// `4:05`, `12:04`, `1:02:05`.
String clock(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  return h > 0 ? '$h:${_two(m)}:${_two(s)}' : '$m:${_two(s)}';
}

/// `45 min`, `1 hr 2 min`, `30 sec`.
String humanDuration(Duration d) {
  final total = d.inSeconds;
  if (total < 60) return '$total sec';
  final h = total ~/ 3600;
  final m = ((total % 3600) / 60).round();
  if (h == 0) return '$m min';
  if (m == 0) return '$h hr';
  return '$h hr $m min';
}

/// True when so little is left that the episode counts as finished: the
/// last 30 seconds, or the last 5% of a short clip (at least 2 seconds).
bool isFinished(Duration position, Duration total) {
  final left = (total - position).inMilliseconds;
  final slack = (total.inMilliseconds * 0.05).clamp(2000, 30000);
  return left <= slack;
}

/// `12 min left`, or `Played` near the end.
String timeLeft(Duration position, Duration total) {
  final left = total - position;
  if (isFinished(position, total)) return 'Played';
  if (left.inMinutes < 1) return '${left.inSeconds} sec left';
  final h = left.inHours;
  final m = left.inMinutes % 60;
  if (h == 0) return '$m min left';
  return m == 0 ? '$h hr left' : '$h hr $m min left';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `4 Jan 2026` in local time.
String shortDate(DateTime d) {
  final l = d.toLocal();
  return '${l.day} ${_months[l.month - 1]} ${l.year}';
}

/// `4 Jan 2026, 09:30` in local time.
String dateTime(DateTime d) {
  final l = d.toLocal();
  return '${shortDate(l)}, ${_two(l.hour)}:${_two(l.minute)}';
}

/// `2.4 MB`, `812 KB`.
String fileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  final mb = bytes / (1024 * 1024);
  return mb < 10 ? '${mb.toStringAsFixed(1)} MB' : '${mb.round()} MB';
}

/// Parses a shared timestamp: `754`, `12:34`, `1:02:05`, `1h2m5s`, `90s`.
Duration? parseTimestamp(String? raw) {
  if (raw == null) return null;
  final t = raw.trim().toLowerCase();
  if (t.isEmpty) return null;
  final plain = int.tryParse(t);
  if (plain != null) return plain >= 0 ? Duration(seconds: plain) : null;
  if (RegExp(r'^\d+(:\d{1,2}){1,2}$').hasMatch(t)) {
    final parts = t.split(':').map(int.parse).toList();
    var seconds = 0;
    for (final p in parts) {
      seconds = seconds * 60 + p;
    }
    return Duration(seconds: seconds);
  }
  final match = RegExp(r'^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$').firstMatch(t);
  if (match != null && match.group(0)!.isNotEmpty) {
    int g(int i) => int.tryParse(match.group(i) ?? '') ?? 0;
    return Duration(hours: g(1), minutes: g(2), seconds: g(3));
  }
  return null;
}

/// Parses `mm:ss` or `h:mm:ss` typed by an admin. Null when invalid.
Duration? parseClock(String raw) {
  final t = raw.trim();
  if (!RegExp(r'^\d{1,3}(:\d{2}){1,2}$').hasMatch(t)) return null;
  final parts = t.split(':').map(int.parse).toList();
  if (parts.skip(1).any((p) => p > 59)) return null;
  var seconds = 0;
  for (final p in parts) {
    seconds = seconds * 60 + p;
  }
  return Duration(seconds: seconds);
}

/// Latin letters with accents, grouped by their plain form (the same table
/// the server uses for show slugs), so "Àdúrà" becomes "adura".
const _folds = <String, String>{
  'a': 'àáâãäåāăąǎǟǡǻȁȃȧḁạảấầẩẫậắằẳẵặ',
  'ae': 'æ',
  'b': 'ḃḅḇ',
  'c': 'çćĉċčḉ',
  'd': 'ďḋḍḏḑḓđð',
  'e': 'èéêëēĕėęěȅȇȩḕḗḙḛḝẹẻẽếềểễệ',
  'f': 'ḟ',
  'g': 'ĝğġģǧǵḡ',
  'h': 'ĥȟḣḥḧḩḫẖ',
  'i': 'ìíîïĩīĭįǐȉȋḭḯỉịı',
  'j': 'ĵǰ',
  'k': 'ķǩḱḳḵ',
  'l': 'ĺļľḷḹḻḽł',
  'm': 'ḿṁṃ',
  'n': 'ñńņňǹṅṇṉṋ',
  'o': 'òóôõöōŏőơǒǫǭȍȏȫȭȯȱṍṏṑṓọỏốồổỗộớờởỡợø',
  'oe': 'œ',
  'p': 'ṕṗ',
  'r': 'ŕŗřȑȓṙṛṝṟ',
  's': 'śŝşšșṡṣṥṧṩ',
  'ss': 'ß',
  't': 'ţťțṫṭṯṱẗ',
  'th': 'þ',
  'u': 'ùúûüũūŭůűųưǔǖǘǚǜȕȗṳṵṷṹṻụủứừửữự',
  'v': 'ṽṿ',
  'w': 'ŵẁẃẅẇẉẘ',
  'x': 'ẋẍ',
  'y': 'ýÿŷȳẏẙỳỵỷỹ',
  'z': 'źżžẑẓẕ',
};

final Map<String, String> _foldMap = {
  for (final entry in _folds.entries)
    for (final ch in entry.value.split('')) ch: entry.key,
};

/// Lowercases [s], folds accented Latin letters to plain ones and drops
/// combining marks (U+0300 to U+036F), as the server does for slugs:
/// "Ọlọ́run Wà" becomes "olorun wa".
String foldToAscii(String s) => s
    .toLowerCase()
    .split('')
    .where((c) {
      final unit = c.codeUnitAt(0);
      return unit < 0x0300 || unit > 0x036F;
    })
    .map((c) => _foldMap[c] ?? c)
    .join();

/// A safe download file name: `grace-chapel-week-1-light.mp3`. Accented
/// letters are folded, so Yoruba titles keep their words.
String downloadName(String show, String title, String extension) {
  String clean(String s) => foldToAscii(
    s,
  ).replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  final base = [clean(show), clean(title)].where((s) => s.isNotEmpty).join('-');
  final trimmed = base.length > 80 ? base.substring(0, 80) : base;
  return '${trimmed.isEmpty ? 'episode' : trimmed}.$extension';
}

/// Shortens a blob ID for display: `Xy3k…9fQ2`.
String shortId(String id) => id.length <= 14
    ? id
    : '${id.substring(0, 6)}…${id.substring(id.length - 6)}';
