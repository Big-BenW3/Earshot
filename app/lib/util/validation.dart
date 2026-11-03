/// Client-side checks that mirror the server's rules, so people see clear
/// messages before anything is uploaded.
library;

import 'format.dart';

enum AudioFormat { mp3, m4a, aac, ogg, wav }

extension AudioFormatLabel on AudioFormat {
  String get label => switch (this) {
    AudioFormat.mp3 => 'MP3',
    AudioFormat.m4a => 'M4A',
    AudioFormat.aac => 'AAC',
    AudioFormat.ogg => 'OGG',
    AudioFormat.wav => 'WAV',
  };
}

const audioAccept =
    '.mp3,.m4a,.aac,.ogg,.oga,.opus,.wav,audio/mpeg,audio/mp4,audio/x-m4a,'
    'audio/aac,audio/ogg,audio/wav,audio/x-wav';
const imageAccept = '.png,.jpg,.jpeg,.webp,image/png,image/jpeg,image/webp';

bool _ascii(List<int> b, int offset, String text) {
  if (b.length < offset + text.length) return false;
  for (var i = 0; i < text.length; i++) {
    if (b[offset + i] != text.codeUnitAt(i)) return false;
  }
  return true;
}

/// Detects an accepted audio format from the first bytes of a file.
AudioFormat? sniffAudio(List<int> b) {
  if (b.length < 4) return null;
  if (_ascii(b, 0, 'RIFF') && _ascii(b, 8, 'WAVE')) return AudioFormat.wav;
  if (_ascii(b, 0, 'OggS')) return AudioFormat.ogg;
  if (_ascii(b, 4, 'ftyp')) return AudioFormat.m4a;
  if (_ascii(b, 0, 'ID3')) return AudioFormat.mp3;
  if (b[0] == 0xFF) {
    if ((b[1] & 0xF6) == 0xF0) return AudioFormat.aac;
    if ((b[1] & 0xE0) == 0xE0 && (b[1] & 0x06) != 0) return AudioFormat.mp3;
  }
  return null;
}

/// Detects PNG, JPEG or WebP.
String? sniffImage(List<int> b) {
  if (b.length >= 8 && b[0] == 0x89 && _ascii(b, 1, 'PNG')) return 'image/png';
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (_ascii(b, 0, 'RIFF') && _ascii(b, 8, 'WEBP')) return 'image/webp';
  return null;
}

/// Returns an error message, or null when the audio file is acceptable.
String? checkAudioFile({
  required String name,
  required int size,
  required List<int> head,
  required int maxBytes,
}) {
  if (size == 0) return '$name is empty.';
  if (size > maxBytes) {
    return '$name is ${fileSize(size)}. Episodes can be up to '
        '${fileSize(maxBytes)}.';
  }
  if (sniffAudio(head) == null) {
    return '$name is not an MP3, M4A, AAC, OGG or WAV file.';
  }
  return null;
}

/// Returns an error message, or null when the cover image is acceptable.
String? checkImageFile({
  required String name,
  required int size,
  required List<int> head,
  required int maxBytes,
}) {
  if (size == 0) return '$name is empty.';
  if (sniffImage(head) == null) {
    return '$name is not a PNG, JPEG or WebP image.';
  }
  if (size > maxBytes) {
    return '$name is ${fileSize(size)}. Cover images can be up to '
        '${fileSize(maxBytes)}.';
  }
  return null;
}

String? requiredText(String? value, String label, {int max = 200}) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return '$label is required.';
  if (v.length > max) return '$label must be $max characters or fewer.';
  return null;
}

String? optionalText(String? value, String label, {int max = 4000}) {
  final v = value?.trim() ?? '';
  if (v.length > max) return '$label must be $max characters or fewer.';
  return null;
}

String? durationText(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return null;
  final d = parseClock(v);
  if (d == null) return 'Use minutes and seconds, like 42:15 or 1:02:05.';
  if (d.inHours >= 48) return 'Episodes can be up to 48 hours long.';
  return null;
}

/// Languages offered when creating a show (ISO 639-1 codes).
const languages = <(String, String)>[
  ('en', 'English'),
  ('fr', 'French'),
  ('es', 'Spanish'),
  ('pt', 'Portuguese'),
  ('de', 'German'),
  ('it', 'Italian'),
  ('nl', 'Dutch'),
  ('yo', 'Yoruba'),
  ('ig', 'Igbo'),
  ('ha', 'Hausa'),
  ('sw', 'Swahili'),
  ('am', 'Amharic'),
  ('zu', 'Zulu'),
  ('xh', 'Xhosa'),
  ('af', 'Afrikaans'),
  ('ar', 'Arabic'),
  ('hi', 'Hindi'),
  ('bn', 'Bengali'),
  ('ur', 'Urdu'),
  ('zh', 'Chinese'),
  ('ja', 'Japanese'),
  ('ko', 'Korean'),
  ('id', 'Indonesian'),
  ('tl', 'Tagalog'),
  ('vi', 'Vietnamese'),
  ('th', 'Thai'),
  ('tr', 'Turkish'),
  ('ru', 'Russian'),
  ('uk', 'Ukrainian'),
  ('pl', 'Polish'),
  ('ro', 'Romanian'),
  ('el', 'Greek'),
  ('he', 'Hebrew'),
  ('fa', 'Persian'),
  ('sv', 'Swedish'),
  ('no', 'Norwegian'),
  ('da', 'Danish'),
  ('fi', 'Finnish'),
];

String languageName(String code) {
  for (final (c, name) in languages) {
    if (c == code) return name;
  }
  return code;
}
