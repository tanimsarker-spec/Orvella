import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:web_socket_channel/io.dart';

import '../../core/config.dart';

/// Serves byte ranges of ONE user-selected file to the server relay.
/// The server never learns the path, and only [path] can ever be read.
class HostMediaService {
  HostMediaService({
    required this.serverUrl,
    required this.roomId,
    required this.tokenProvider,
    required this.path,
  });

  final String serverUrl;
  final String roomId;
  final Future<String> Function() tokenProvider;
  final String path;

  static const _chunk = 256 * 1024;

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  bool _stopped = false;
  int _attempt = 0;
  final _cancelled = <int>{};

  /// Total bytes sent to the server since start (for measured upload stats).
  int bytesSent = 0;

  Future<void> start() => _open();

  Future<void> _open() async {
    if (_stopped) return;
    try {
      final token = await tokenProvider();
      final channel = IOWebSocketChannel.connect(
        Uri.parse(wsUrl(serverUrl, '/media/host', {'room': roomId})),
        headers: {'Authorization': 'Bearer $token'},
      );
      await channel.ready;
      if (_stopped) {
        await channel.sink.close();
        return;
      }
      _channel = channel;
      _attempt = 0;
      _sub = channel.stream.listen(
        _onMessage,
        onDone: _onClosed,
        onError: (Object _) => _onClosed(),
      );
    } catch (_) {
      _onClosed();
    }
  }

  void _onClosed() {
    _sub?.cancel();
    _sub = null;
    final code = _channel?.closeCode;
    _channel = null;
    if (_stopped || code == 4409 || code == 4403 || code == 4404) return;
    if (_retry?.isActive ?? false) return;
    _attempt += 1;
    _retry = Timer(
      Duration(
        milliseconds: min(30000, 500 * pow(2, min(_attempt, 6)).toInt()),
      ),
      _open,
    );
  }

  void _onMessage(dynamic data) {
    if (data is! String) return;
    try {
      final m = jsonDecode(data) as Map<String, dynamic>;
      final id = (m['id'] as num).toInt();
      if (m['type'] == 'cancel') {
        _cancelled.add(id);
      } else if (m['type'] == 'range') {
        unawaited(
          _serve(id, (m['start'] as num).toInt(), (m['end'] as num).toInt()),
        );
      }
    } catch (_) {}
  }

  Future<void> _serve(int id, int start, int end) async {
    final channel = _channel;
    if (channel == null) return;
    RandomAccessFile? raf;
    try {
      raf = await File(path).open();
      final length = await raf.length();
      final last = min(end, length - 1);
      var pos = start;
      await raf.setPosition(pos);
      while (pos <= last && !_cancelled.contains(id) && _channel == channel) {
        final bytes = await raf.read(min(_chunk, last - pos + 1));
        if (bytes.isEmpty) break;
        final frame = Uint8List(4 + bytes.length);
        ByteData.view(frame.buffer).setUint32(0, id);
        frame.setRange(4, frame.length, bytes);
        channel.sink.add(frame);
        bytesSent += bytes.length;
        pos += bytes.length;
        // Let the event loop run so cancel messages and other ranges are handled.
        await Future<void>.delayed(Duration.zero);
      }
      if (!_cancelled.contains(id))
        channel.sink.add(jsonEncode({'type': 'end', 'id': id}));
    } catch (_) {
      channel.sink.add(jsonEncode({'type': 'error', 'id': id}));
    } finally {
      _cancelled.remove(id);
      await raf?.close();
    }
  }

  Future<void> stop() async {
    _stopped = true;
    _retry?.cancel();
    await _sub?.cancel();
    await _channel?.sink.close();
  }
}
