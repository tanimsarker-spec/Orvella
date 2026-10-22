import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/io.dart';

import 'config.dart';
import 'models.dart';

enum ConnectionStatus { connecting, connected, reconnecting, closed }

/// Room control channel. Carries sync/chat messages only, never video bytes.
/// Reconnects with backoff and re-fetches a fresh token each attempt.
class RoomConnection {
  RoomConnection({
    required this.serverUrl,
    required this.roomId,
    required this.tokenProvider,
  });

  final String serverUrl;
  final String roomId;
  final Future<String> Function() tokenProvider;

  final _states = StreamController<RoomState>.broadcast();
  final _chat = StreamController<ChatMessage>.broadcast();
  final _status = StreamController<ConnectionStatus>.broadcast();
  final _errors = StreamController<String>.broadcast();

  Stream<RoomState> get states => _states.stream;
  Stream<ChatMessage> get chat => _chat.stream;
  Stream<ConnectionStatus> get statusStream => _status.stream;
  Stream<String> get errors => _errors.stream;

  RoomState? lastState;
  ConnectionStatus status = ConnectionStatus.connecting;

  /// Estimated (server clock - local clock), from the lowest-latency ping seen.
  int clockOffsetMs = 0;
  int _bestRtt = 1 << 30;
  int get serverNowMs => DateTime.now().millisecondsSinceEpoch + clockOffsetMs;

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _ping;
  Timer? _retry;
  bool _closed = false;
  int _attempt = 0;

  Future<void> connect() => _open();

  void _setStatus(ConnectionStatus s) {
    status = s;
    if (!_status.isClosed) _status.add(s);
  }

  Future<void> _open() async {
    if (_closed) return;
    _setStatus(
      _attempt == 0
          ? ConnectionStatus.connecting
          : ConnectionStatus.reconnecting,
    );
    try {
      final token = await tokenProvider();
      final channel = IOWebSocketChannel.connect(
        Uri.parse(wsUrl(serverUrl, '/ws', {'room': roomId})),
        headers: {'Authorization': 'Bearer $token'},
      );
      await channel.ready;
      if (_closed) {
        await channel.sink.close();
        return;
      }
      _channel = channel;
      _attempt = 0;
      _bestRtt = 1 << 30;
      _setStatus(ConnectionStatus.connected);
      _sub = channel.stream.listen(
        _onData,
        onDone: _onClosed,
        onError: (Object _) => _onClosed(),
      );
      _ping?.cancel();
      _sendPing();
      _ping = Timer.periodic(
        const Duration(seconds: 10),
        (timer) => _sendPing(),
      );
    } catch (_) {
      _onClosed();
    }
  }

  void _onClosed() {
    final code = _channel?.closeCode;
    _sub?.cancel();
    _sub = null;
    _ping?.cancel();
    _channel = null;
    if (_closed) return;
    if (code == 4403 || code == 4404) {
      _errors.add(code == 4404 ? 'room_not_found' : 'not_a_member');
      _setStatus(ConnectionStatus.closed);
      _closed = true;
      return;
    }
    if (_retry?.isActive ?? false) return;
    _attempt += 1;
    final delay = Duration(
      milliseconds: min(30000, 500 * pow(2, min(_attempt, 6)).toInt()),
    );
    _setStatus(ConnectionStatus.reconnecting);
    _retry = Timer(delay, _open);
  }

  void _sendPing() =>
      _send({'type': 'ping', 't': DateTime.now().millisecondsSinceEpoch});

  void _onData(dynamic data) {
    if (data is! String) return;
    final Map<String, dynamic> m;
    try {
      m = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (m['type']) {
      case 'state':
        final s = RoomState.fromJson(m);
        lastState = s;
        _states.add(s);
      case 'chat':
        final from = m['from'] as Map<String, dynamic>;
        _chat.add(
          ChatMessage(
            fromId: from['id'] as String,
            fromName: from['displayName'] as String,
            text: m['text'] as String,
            at: (m['at'] as num).toInt(),
          ),
        );
      case 'pong':
        final now = DateTime.now().millisecondsSinceEpoch;
        final rtt = now - (m['t'] as num).toInt();
        if (rtt <= _bestRtt) {
          _bestRtt = rtt;
          clockOffsetMs = (m['serverTime'] as num).toInt() + rtt ~/ 2 - now;
        } else {
          _bestRtt += 20; // slowly forget old best so we can adapt
        }
      case 'error':
        _errors.add((m['code'] as String?) ?? 'error');
    }
  }

  void _send(Map<String, dynamic> m) {
    if (status == ConnectionStatus.connected) _channel?.sink.add(jsonEncode(m));
  }

  void play(int positionMs) =>
      _send({'type': 'play', 'positionMs': positionMs});
  void pause(int positionMs) =>
      _send({'type': 'pause', 'positionMs': positionMs});
  void seek(int positionMs) =>
      _send({'type': 'seek', 'positionMs': positionMs});
  void setBuffering(bool value) => _send({'type': 'buffering', 'value': value});
  void sendChat(String text) => _send({'type': 'chat', 'text': text});
  void setSource(Map<String, dynamic> source) =>
      _send({'type': 'setSource', 'source': source});
  void setControlMode(String mode) =>
      _send({'type': 'setControlMode', 'mode': mode});

  Future<void> dispose() async {
    _closed = true;
    _retry?.cancel();
    _ping?.cancel();
    await _sub?.cancel();
    await _channel?.sink.close();
    await _states.close();
    await _chat.close();
    await _status.close();
    await _errors.close();
  }
}
