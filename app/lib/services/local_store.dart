import 'platform/browser.dart';

/// Small things remembered on this device: resume positions and playback
/// speed. (Hosts' shows come from their signed-in address, not the device.)
class LocalStore {
  LocalStore(this._browser);

  final Browser _browser;

  static const _pos = 'earshot.pos.';
  static const _speed = 'earshot.speed';

  /// Saved position for an episode, or null.
  ({Duration position, Duration? duration})? position(String episodeId) {
    final raw = _browser.read('$_pos$episodeId');
    if (raw == null) return null;
    final parts = raw.split('|');
    final p = int.tryParse(parts.first);
    if (p == null) return null;
    final d = parts.length > 1 ? int.tryParse(parts[1]) : null;
    return (
      position: Duration(seconds: p),
      duration: d == null ? null : Duration(seconds: d),
    );
  }

  void savePosition(String episodeId, Duration position, Duration? duration) {
    _browser.write(
      '$_pos$episodeId',
      '${position.inSeconds}|${duration?.inSeconds ?? ''}|'
          '${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  void clearPosition(String episodeId) => _browser.remove('$_pos$episodeId');

  double get speed => double.tryParse(_browser.read(_speed) ?? '') ?? 1.0;
  set speed(double value) => _browser.write(_speed, '$value');
}
