/// Input rules for shows and episodes. Messages are shown to people as-is.
library;

/// Apple Podcasts top-level categories.
const podcastCategories = <String>[
  'Arts',
  'Business',
  'Comedy',
  'Education',
  'Fiction',
  'Government',
  'Health & Fitness',
  'History',
  'Kids & Family',
  'Leisure',
  'Music',
  'News',
  'Religion & Spirituality',
  'Science',
  'Society & Culture',
  'Sports',
  'Technology',
  'True Crime',
  'TV & Film',
];

const maxNameLength = 120;
const maxAuthorLength = 120;
const maxShowDescriptionLength = 4000;
const maxTitleLength = 200;
const maxEpisodeDescriptionLength = 10000;
const maxDurationSeconds = 48 * 3600;

final _language = RegExp(r'^[a-z]{2,3}(-[A-Za-z]{2,4})?$');

class ValidationException implements Exception {
  ValidationException(this.errors);

  /// Field name to message.
  final Map<String, String> errors;

  String get message => errors.values.first;

  @override
  String toString() => 'ValidationException($errors)';
}

/// Collects errors while reading a JSON body.
class FieldReader {
  FieldReader(this.json);

  final Map<String, Object?> json;
  final Map<String, String> errors = {};

  bool has(String key) => json.containsKey(key);

  String? text(
    String key, {
    required String label,
    required int max,
    bool required = false,
  }) {
    final raw = json[key];
    if (raw == null) {
      if (required) errors[key] = '$label is required.';
      return null;
    }
    if (raw is! String) {
      errors[key] = '$label must be text.';
      return null;
    }
    final value = raw.trim();
    if (required && value.isEmpty) {
      errors[key] = '$label is required.';
      return null;
    }
    if (value.length > max) {
      errors[key] = '$label must be $max characters or fewer.';
      return null;
    }
    return value;
  }

  bool? boolean(String key, {required String label}) {
    final raw = json[key];
    if (raw == null) return null;
    if (raw is! bool) {
      errors[key] = '$label must be true or false.';
      return null;
    }
    return raw;
  }

  String? language(String key) {
    final value = text(key, label: 'Language', max: 12);
    if (value == null) return null;
    if (!_language.hasMatch(value)) {
      errors[key] = 'Choose a language from the list.';
      return null;
    }
    return value;
  }

  String? category(String key) {
    final value = text(key, label: 'Category', max: 60);
    if (value == null) return null;
    if (!podcastCategories.contains(value)) {
      errors[key] = 'Choose a category from the list.';
      return null;
    }
    return value;
  }

  DateTime? dateTime(
    String key, {
    required String label,
    bool required = false,
  }) {
    final raw = json[key];
    if (raw == null) {
      if (required) errors[key] = '$label is required.';
      return null;
    }
    final parsed = raw is String ? DateTime.tryParse(raw) : null;
    if (parsed == null) {
      errors[key] = '$label must be a valid date.';
      return null;
    }
    final utc = parsed.toUtc();
    if (utc.year < 1900 || utc.year > 2200) {
      errors[key] = '$label must be a valid date.';
      return null;
    }
    return utc;
  }

  /// Reads a nullable whole number. Returns (present, value).
  (bool, int?) nullableInt(
    String key, {
    required String label,
    required int min,
    required int max,
  }) {
    if (!json.containsKey(key)) return (false, null);
    final raw = json[key];
    if (raw == null) return (true, null);
    final value = raw is int
        ? raw
        : (raw is double && raw.isFinite ? raw.round() : null);
    if (value == null || value < min || value > max) {
      errors[key] = '$label must be between $min and $max.';
      return (false, null);
    }
    return (true, value);
  }

  void check() {
    if (errors.isNotEmpty) throw ValidationException(Map.of(errors));
  }
}

/// Latin letters with accents, grouped by their plain form, so that
/// "Àdúrà" becomes "adura" rather than losing letters.
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

/// Combining diacritical marks (U+0300 to U+036F). Yoruba often writes a
/// tone mark on a dotted letter this way ("ọ́" is "ọ" + U+0301), and text
/// pasted from some systems arrives decomposed ("à" as "a" + U+0300).
bool _isCombiningMark(int unit) => unit >= 0x0300 && unit <= 0x036F;

/// Builds a URL slug from a show name. Accented letters fold to their plain
/// form and combining marks are dropped, so "Ọlọ́run Wà" becomes
/// "olorun-wa" rather than "olo-run-wa".
String slugify(String name) {
  final lower = name
      .toLowerCase()
      .split('')
      .where((c) => !_isCombiningMark(c.codeUnitAt(0)))
      .map((c) => _foldMap[c] ?? c)
      .join();
  final buffer = StringBuffer();
  var dash = false;
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    final isAlnum =
        (rune >= 0x61 && rune <= 0x7a) || (rune >= 0x30 && rune <= 0x39);
    if (isAlnum) {
      buffer.write(ch);
      dash = false;
    } else if (!dash && buffer.isNotEmpty) {
      buffer.write('-');
      dash = true;
    }
  }
  var slug = buffer.toString().replaceAll(RegExp(r'-+$'), '');
  if (slug.length > 48) {
    slug = slug.substring(0, 48).replaceAll(RegExp(r'-+$'), '');
  }
  return slug.isEmpty ? 'show' : slug;
}

final slugPattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
