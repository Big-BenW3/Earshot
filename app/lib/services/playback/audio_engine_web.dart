import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'audio_engine.dart';

AudioEngine createAudioEngine() => WebAudioEngine();

/// One `<audio>` element for the whole session, so playback continues while
/// the person moves between pages.
class WebAudioEngine implements AudioEngine {
  WebAudioEngine() {
    _audio.preload = 'metadata';
    void on(String type, void Function() f) =>
        _audio.addEventListener(type, ((web.Event _) => f()).toJS);
    on('loadstart', () => _emit(status: EngineStatus.loading));
    on('loadedmetadata', _onMetadata);
    on('durationchange', () => _emit());
    on('timeupdate', () => _emit());
    on('play', () => _emit(status: EngineStatus.playing));
    on('playing', () => _emit(status: EngineStatus.playing, buffering: false));
    on('pause', () {
      if (!_audio.ended) _emit(status: EngineStatus.paused);
    });
    on('waiting', () => _emit(buffering: true));
    on('canplay', () => _emit(buffering: false));
    on('ended', () => _emit(status: EngineStatus.ended));
    on(
      'error',
      () =>
          _emit(status: EngineStatus.error, errorCode: _audio.error?.code ?? 0),
    );
  }

  final _audio = web.HTMLAudioElement();
  final _controller = StreamController<EngineState>.broadcast();
  EngineState _state = const EngineState();
  Duration? _pendingStart;
  bool _disposed = false;
  int _generation = 0;

  @override
  Stream<EngineState> get states => _controller.stream;
  @override
  EngineState get state => _state;

  Duration? get _duration {
    final d = _audio.duration;
    if (d.isNaN || d.isInfinite || d <= 0) return null;
    return Duration(milliseconds: (d * 1000).round());
  }

  void _onMetadata() {
    if (_disposed) return;
    final start = _pendingStart;
    _pendingStart = null;
    if (start != null && start > Duration.zero) {
      _audio.currentTime = (start.inMilliseconds / 1000).clamp(
        0,
        _audio.duration.isFinite ? _audio.duration : double.infinity,
      );
    }
    _emit(
      status: _state.status == EngineStatus.loading ? EngineStatus.ready : null,
    );
  }

  void _emit({EngineStatus? status, bool? buffering, int? errorCode}) {
    if (_disposed) return;
    _state = EngineState(
      status: status ?? _state.status,
      position: Duration(milliseconds: (_audio.currentTime * 1000).round()),
      duration: _duration,
      buffering: buffering ?? _state.buffering,
      errorCode: status == EngineStatus.error ? errorCode : null,
    );
    _controller.add(_state);
    _updatePositionState();
  }

  @override
  void load(String url, {Duration start = Duration.zero}) {
    if (_disposed) return;
    ++_generation;
    _pendingStart = start;
    _audio.src = url;
    _audio.load();
    _state = EngineState(status: EngineStatus.loading, position: start);
    _controller.add(_state);
  }

  @override
  Future<void> play() async {
    if (_disposed) return;
    final generation = _generation;
    try {
      await _audio.play().toDart;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      // Autoplay rules or a missing source; the error event reports details.
      if (_audio.error != null) {
        _emit(status: EngineStatus.error, errorCode: _audio.error!.code);
      } else {
        _emit(status: EngineStatus.paused);
      }
    }
  }

  @override
  void pause() => _audio.pause();

  @override
  void seek(Duration position) {
    if (_disposed) return;
    if (_audio.readyState == 0) {
      _pendingStart = position;
      _state = EngineState(
        status: _state.status,
        position: position,
        duration: _state.duration,
      );
      _controller.add(_state);
      return;
    }
    _audio.currentTime = position.inMilliseconds / 1000;
    _emit();
  }

  @override
  set rate(double value) {
    _audio.playbackRate = value;
    _audio.defaultPlaybackRate = value;
  }

  @override
  void setNowPlaying(NowPlayingInfo info, RemoteCommands commands) {
    final navigator = web.window.navigator;
    if (!(navigator as JSObject).has('mediaSession')) return;
    final session = navigator.mediaSession;
    session.metadata = web.MediaMetadata(
      web.MediaMetadataInit(
        title: info.title,
        artist: info.artist,
        album: info.album,
        artwork: [
          if (info.artworkUrl != null)
            web.MediaImage(src: info.artworkUrl!, sizes: '512x512'),
        ].toJS,
      ),
    );
    void handle(String action, void Function(_ActionDetails) f) {
      try {
        session.setActionHandler(action, f.toJS);
      } catch (_) {
        // Some actions are not supported in every browser.
      }
    }

    handle('play', (_) => commands.play());
    handle('pause', (_) => commands.pause());
    handle('seekbackward', (_) => commands.back());
    handle('seekforward', (_) => commands.forward());
    handle('seekto', (d) {
      final t = d.seekTime;
      if (t != null) {
        commands.seekTo(Duration(milliseconds: (t * 1000).round()));
      }
    });
  }

  void _updatePositionState() {
    final navigator = web.window.navigator;
    final d = _duration;
    if (d == null || !(navigator as JSObject).has('mediaSession')) return;
    try {
      navigator.mediaSession.setPositionState(
        web.MediaPositionState(
          duration: d.inMilliseconds / 1000,
          playbackRate: _audio.playbackRate,
          position: (_audio.currentTime).clamp(0, d.inMilliseconds / 1000),
        ),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    final navigator = web.window.navigator;
    if ((navigator as JSObject).has('mediaSession')) {
      final session = navigator.mediaSession;
      for (final action in [
        'play',
        'pause',
        'seekbackward',
        'seekforward',
        'seekto',
      ]) {
        try {
          session.setActionHandler(action, null);
        } catch (_) {}
      }
      session.metadata = null;
    }
    _audio.pause();
    _audio.src = '';
    _controller.close();
  }
}

/// The argument passed to Media Session action handlers.
extension type _ActionDetails._(JSObject _) implements JSObject {
  external double? get seekTime;
}
