/// Content sniffing for claimed blobs. Walrus stores bytes without a type,
/// so the server reads a blob's first bytes from the aggregator and decides
/// the type by magic bytes, never from what the client says.
library;

enum UploadKind { audio, image }

class SniffResult {
  const SniffResult(this.kind, this.mime, this.label);
  final UploadKind kind;
  final String mime;
  final String label;

  @override
  String toString() => '$label ($mime)';
}

/// Bytes needed to decide. Fewer is fine at the end of a short stream.
const sniffLength = 16;

const _m4aBrands = {
  'M4A ',
  'M4B ',
  'M4P ',
  'mp42',
  'mp41',
  'isom',
  'iso2',
  'iso4',
  'iso5',
  'iso6',
  'dash',
  'f4a ',
  '3gp4',
  '3gp5',
  '3gp6',
};

bool _ascii(List<int> b, int offset, String text) {
  if (b.length < offset + text.length) return false;
  for (var i = 0; i < text.length; i++) {
    if (b[offset + i] != text.codeUnitAt(i)) return false;
  }
  return true;
}

/// Returns the detected type, or null when the bytes are not an accepted
/// audio or image format.
SniffResult? sniff(List<int> b) {
  if (b.length < 4) return null;

  // Images (cover art).
  if (b.length >= 8 &&
      b[0] == 0x89 &&
      _ascii(b, 1, 'PNG') &&
      b[4] == 0x0D &&
      b[5] == 0x0A &&
      b[6] == 0x1A &&
      b[7] == 0x0A) {
    return const SniffResult(UploadKind.image, 'image/png', 'PNG');
  }
  if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return const SniffResult(UploadKind.image, 'image/jpeg', 'JPEG');
  }
  if (_ascii(b, 0, 'RIFF') && _ascii(b, 8, 'WEBP')) {
    return const SniffResult(UploadKind.image, 'image/webp', 'WebP');
  }

  // Audio.
  if (_ascii(b, 0, 'RIFF') && _ascii(b, 8, 'WAVE')) {
    return const SniffResult(UploadKind.audio, 'audio/wav', 'WAV');
  }
  if (_ascii(b, 0, 'OggS')) {
    return const SniffResult(UploadKind.audio, 'audio/ogg', 'OGG');
  }
  if (_ascii(b, 4, 'ftyp') && b.length >= 12) {
    final brand = String.fromCharCodes(b.sublist(8, 12));
    if (_m4aBrands.contains(brand)) {
      return const SniffResult(UploadKind.audio, 'audio/x-m4a', 'M4A');
    }
    return null;
  }
  if (_ascii(b, 0, 'ID3')) {
    return const SniffResult(UploadKind.audio, 'audio/mpeg', 'MP3');
  }
  if (b[0] == 0xFF) {
    // ADTS AAC: 12-bit sync, layer bits 00.
    if ((b[1] & 0xF6) == 0xF0) {
      return const SniffResult(UploadKind.audio, 'audio/aac', 'AAC');
    }
    // MPEG audio frame: 11-bit sync, layer not reserved, bitrate not 1111.
    if ((b[1] & 0xE0) == 0xE0 &&
        (b[1] & 0x06) != 0 &&
        (b[1] & 0x18) != 0x08 &&
        (b[2] & 0xF0) != 0xF0) {
      return const SniffResult(UploadKind.audio, 'audio/mpeg', 'MP3');
    }
  }
  return null;
}
