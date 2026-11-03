import 'dart:math';

final _random = Random.secure();

const _idAlphabet = 'abcdefghijkmnpqrstuvwxyz23456789';

/// A short random id for episodes, safe in URLs and hard to guess.
String newId([int length = 10]) => List.generate(
  length,
  (_) => _idAlphabet[_random.nextInt(_idAlphabet.length)],
).join();
