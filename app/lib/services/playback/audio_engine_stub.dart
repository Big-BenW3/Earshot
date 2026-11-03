import 'dart:async';

import 'audio_engine.dart';

AudioEngine createAudioEngine() => FakeAudioEngine();

/// A scriptable engine for tests and the Dart VM.
class FakeAudioEngine implements AudioEngine {
  final _controller = StreamController<EngineState>.broadcast();
  EngineState _state = const EngineState();
  String? loadedUrl;
  double currentRate = 1;
  NowPlayingInfo? nowPlaying;
  RemoteCommands? commands;
  bool failPlay = false;

  /// Duration reported once a source loads.
  Duration fakeDuration = const Duration(minutes: 30);

  @override
  Stream<EngineState> get states => _controller.stream;
  @override
  EngineState get state => _state;

  void emit(EngineState s) {
    _state = s;
    _controller.add(s);
  }

  @override
  void load(String url, {Duration start = Duration.zero}) {
    loadedUrl = url;
    emit(
      EngineState(
        status: EngineStatus.ready,
        position: start,
        duration: fakeDuration,
      ),
    );
  }

  @override
  Future<void> play() async {
    if (failPlay) {
      emit(
        EngineState(
          status: EngineStatus.error,
          position: _state.position,
          duration: _state.duration,
          errorCode: 4,
        ),
      );
      return;
    }
    emit(
      EngineState(
        status: EngineStatus.playing,
        position: _state.position,
        duration: _state.duration,
      ),
    );
  }

  @override
  void pause() => emit(
    EngineState(
      status: EngineStatus.paused,
      position: _state.position,
      duration: _state.duration,
    ),
  );

  @override
  void seek(Duration position) => emit(
    EngineState(
      status: _state.status,
      position: position,
      duration: _state.duration,
    ),
  );

  @override
  set rate(double value) => currentRate = value;

  @override
  void setNowPlaying(NowPlayingInfo info, RemoteCommands commands) {
    nowPlaying = info;
    this.commands = commands;
  }

  @override
  void dispose() => _controller.close();
}
