import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../util/format.dart';
import '../local_store.dart';
import 'audio_engine.dart';

const playbackSpeeds = [1.0, 1.25, 1.5, 2.0];
const skipStep = Duration(seconds: 15);

String speedLabel(double s) =>
    '${s == s.roundToDouble() ? s.toStringAsFixed(0) : s.toString()}x';

/// The one player for the whole app. It lives above the router, so the
/// audio keeps going while the person browses.
class PlayerController extends ChangeNotifier {
  PlayerController({required AudioEngine engine, required LocalStore store})
    : _engine = engine,
      _store = store {
    _speed = playbackSpeeds.contains(store.speed) ? store.speed : 1.0;
    _sub = _engine.states.listen(_onState);
  }

  final AudioEngine _engine;
  final LocalStore _store;
  late final StreamSubscription<EngineState> _sub;

  Show? _show;
  Episode? _episode;
  EngineState _state = const EngineState();
  double _speed = 1.0;
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);

  Show? get show => _show;
  Episode? get episode => _episode;
  bool get hasEpisode => _episode != null;
  bool get playing => _state.status == EngineStatus.playing;
  bool get loading =>
      _state.status == EngineStatus.loading || (_state.buffering && playing);
  bool get failed => _state.status == EngineStatus.error;
  bool get ended => _state.status == EngineStatus.ended;
  Duration get position => _state.position;
  Duration? get duration => _state.duration ?? _episode?.duration;
  double get speed => _speed;

  /// 0..1, or 0 when the length is unknown.
  double get progress {
    final d = duration;
    if (d == null || d.inMilliseconds == 0) return 0;
    return (position.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0);
  }

  String get errorMessage => _state.errorCode == 4
      ? 'This recording could not be played. Its storage period may have ended.'
      : 'Playback stopped. Check your connection and try again.';

  bool isCurrent(Episode e) => _episode?.id == e.id;

  /// Saved resume position for any episode (for list rows).
  Duration? savedPosition(Episode e) {
    if (isCurrent(e)) return position;
    return _store.position(e.id)?.position;
  }

  /// Starts [episode]. Resumes where the listener left off unless [start]
  /// is given (for example from a shared timestamp link).
  Future<void> playEpisode(
    Show show,
    Episode episode, {
    Duration? start,
  }) async {
    if (isCurrent(episode) && !failed) {
      if (start != null) seek(start);
      await _engine.play();
      return;
    }
    _saveNow();
    _show = show;
    _episode = episode;
    _state = const EngineState(status: EngineStatus.loading);
    var from = start;
    if (from == null) {
      final saved = _store.position(episode.id);
      final total = saved?.duration ?? episode.duration;
      if (saved != null &&
          (total == null || !isFinished(saved.position, total))) {
        from = saved.position;
      }
    }
    _engine.load(episode.audioUrl, start: from ?? Duration.zero);
    _state = _engine.state;
    _engine.rate = _speed;
    _engine.setNowPlaying(
      NowPlayingInfo(
        title: episode.title,
        artist: show.author,
        album: show.name,
        artworkUrl: show.coverUrl,
      ),
      RemoteCommands(
        play: () => _engine.play(),
        pause: pause,
        back: () => skip(-skipStep),
        forward: () => skip(skipStep),
        seekTo: seek,
      ),
    );
    notifyListeners();
    await _engine.play();
  }

  Future<void> toggle() async {
    if (_episode == null) return;
    if (playing) {
      pause();
    } else if (failed) {
      final show = _show!;
      final episode = _episode!;
      _episode = null;
      await playEpisode(show, episode, start: position);
    } else {
      if (ended) seek(Duration.zero);
      await _engine.play();
    }
  }

  void pause() {
    _engine.pause();
    _saveNow();
  }

  void seek(Duration to) {
    final d = duration;
    var target = to < Duration.zero ? Duration.zero : to;
    if (d != null && target > d) target = d;
    _engine.seek(target);
    _state = _engine.state;
    _saveNow();
    notifyListeners();
  }

  void skip(Duration by) => seek(position + by);

  /// Seeks to a fraction of the episode (0..1).
  void seekFraction(double f) {
    final d = duration;
    if (d == null) return;
    seek(d * f.clamp(0.0, 1.0));
  }

  void setSpeed(double value) {
    if (!playbackSpeeds.contains(value)) return;
    _speed = value;
    _engine.rate = value;
    _store.speed = value;
    notifyListeners();
  }

  void cycleSpeed() {
    final i = playbackSpeeds.indexOf(_speed);
    setSpeed(playbackSpeeds[(i + 1) % playbackSpeeds.length]);
  }

  void close() {
    _engine.pause();
    _saveNow();
    _episode = null;
    _show = null;
    _state = const EngineState();
    notifyListeners();
  }

  void _onState(EngineState s) {
    if (_episode == null) return;
    _state = s;
    final e = _episode;
    if (e != null) {
      if (s.status == EngineStatus.ended) {
        _store.savePosition(e.id, duration ?? s.position, duration);
      } else if (DateTime.now().difference(_lastSave) >
          const Duration(seconds: 5)) {
        _saveNow();
      }
    }
    notifyListeners();
  }

  void _saveNow() {
    final e = _episode;
    if (e == null) return;
    _lastSave = DateTime.now();
    _store.savePosition(e.id, position, duration);
  }

  @override
  void dispose() {
    _saveNow();
    _sub.cancel();
    _engine.dispose();
    super.dispose();
  }
}
