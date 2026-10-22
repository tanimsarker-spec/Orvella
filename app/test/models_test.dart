import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orvella/core/config.dart';
import 'package:orvella/core/mime.dart';
import 'package:orvella/core/models.dart';
import 'package:orvella/core/session.dart';

Map<String, dynamic> _state({bool playing = true}) => {
  'revision': 3,
  'playing': playing,
  'positionMs': 10000,
  'updatedAt': 1000,
  'serverNow': 1500,
  'source': {'kind': 'local', 'name': 'a.mp4', 'size': 10, 'mime': 'video/mp4'},
  'hostId': 'h',
  'controlMode': 'everyone',
  'buffering': ['x'],
  'participants': [
    {'id': 'h', 'displayName': 'Host', 'online': true},
  ],
};

void main() {
  test('RoomState parses server JSON', () {
    final s = RoomState.fromJson(_state());
    expect(s.source!.kind, 'local');
    expect(s.buffering, ['x']);
    expect(s.participants.single.displayName, 'Host');
  });

  test('target position advances only while playing', () {
    expect(RoomState.fromJson(_state()).targetPositionMs(3000), 12000);
    expect(
      RoomState.fromJson(_state(playing: false)).targetPositionMs(3000),
      10000,
    );
  });

  test('jwtExpSeconds reads exp and tolerates junk', () {
    final payload = base64Url
        .encode(utf8.encode(jsonEncode({'exp': 1234})))
        .replaceAll('=', '');
    expect(jwtExpSeconds('h.$payload.s'), 1234);
    expect(jwtExpSeconds('junk'), isNull);
  });

  test('wsUrl switches scheme', () {
    expect(
      wsUrl('https://x.example', '/ws', {'room': 'r'}),
      'wss://x.example/ws?room=r',
    );
    expect(wsUrl('http://localhost:8080', '/ws'), 'ws://localhost:8080/ws');
  });

  test('mime guessing', () {
    expect(videoMimeForFileName('Movie.MKV'), 'video/x-matroska');
    expect(videoMimeForFileName('a.mp4'), 'video/mp4');
  });
}
