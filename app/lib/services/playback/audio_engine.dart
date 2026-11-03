/// The audio element behind the player, behind an interface for tests.
library;

import 'dart:async';

import 'audio_engine_stub.dart'
    if (dart.library.js_interop) 'audio_engine_web.dart'
    as impl;

enum EngineStatus { idle, loading, ready, playing, paused, ended, error }

class EngineState {
  const EngineState({
    this.status = EngineStatus.idle,
    this.position = Duration.zero,
    this.duration,
    this.buffering = false,
    this.errorCode,
  });

  final EngineStatus status;
  final Duration position;
  final Duration? duration;
  final bool buffering;

  /// MediaError code (4 = source not supported or not found).
  final int? errorCode;

  bool get playing => status == EngineStatus.playing;
}

/// Lock-screen and headset metadata (Media Session API on the web).
class NowPlayingInfo {
  const NowPlayingInfo({
    required this.title,
    required this.artist,
    required this.album,
    this.artworkUrl,
  });
  final String title;
  final String artist;
  final String album;
  final String? artworkUrl;
}

/// Hardware and lock-screen buttons.
class RemoteCommands {
  const RemoteCommands({
    required this.play,
    required this.pause,
    required this.back,
    required this.forward,
    required this.seekTo,
  });
  final void Function() play;
  final void Function() pause;
  final void Function() back;
  final void Function() forward;
  final void Function(Duration) seekTo;
}

abstract class AudioEngine {
  Stream<EngineState> get states;
  EngineState get state;

  /// Points the element at [url]; playback streams with range requests.
  void load(String url, {Duration start = Duration.zero});
  Future<void> play();
  void pause();
  void seek(Duration position);
  set rate(double value);
  void setNowPlaying(NowPlayingInfo info, RemoteCommands commands);
  void dispose();
}

AudioEngine createAudioEngine() => impl.createAudioEngine();
