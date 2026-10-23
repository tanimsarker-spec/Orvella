import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/models.dart';
import '../../core/room_connection.dart';

/// Group voice chat using a WebRTC mesh (one audio connection per other person).
/// Signaling goes through the room socket; audio never touches the Orvella server
/// except through the TURN relay when a direct path is impossible.
class VoiceChat {
  VoiceChat({
    required this.connection,
    required this.userId,
    required this.iceServers,
  });

  final RoomConnection connection;
  final String userId;
  final Future<List<Map<String, dynamic>>> Function() iceServers;

  final ValueNotifier<bool> joined = ValueNotifier(false);
  final ValueNotifier<bool> muted = ValueNotifier(false);
  final ValueNotifier<Set<String>> peers = ValueNotifier(<String>{});
  final ValueNotifier<String?> error = ValueNotifier(null);

  MediaStream? _local;
  List<Map<String, dynamic>> _servers = const [];
  final Map<String, RTCPeerConnection> _pcs = {};
  final Map<String, List<RTCIceCandidate>> _pending = {};
  StreamSubscription<SignalMessage>? _sub;
  bool _disposed = false;

  Future<void> join(Iterable<String> everyone) async {
    if (joined.value) return;
    error.value = null;
    try {
      _local = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
    } catch (_) {
      error.value = 'Orvella needs microphone permission to start voice chat.';
      return;
    }
    try {
      _servers = await iceServers();
    } catch (_) {
      _servers = const [
        {'urls': 'stun:stun.l.google.com:19302'},
      ];
    }
    _sub = connection.signals.listen(_onSignal);
    muted.value = false;
    joined.value = true;
    for (final id in everyone) {
      if (id != userId) connection.sendSignal(id, {'kind': 'hello'});
    }
  }

  void toggleMute() {
    muted.value = !muted.value;
    for (final t in _local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !muted.value;
    }
  }

  Future<void> leave(Iterable<String> everyone) async {
    if (!joined.value) return;
    for (final id in everyone) {
      if (id != userId) connection.sendSignal(id, {'kind': 'bye'});
    }
    await _teardown();
  }

  Future<void> _teardown() async {
    await _sub?.cancel();
    _sub = null;
    for (final id in _pcs.keys.toList()) {
      await _close(id);
    }
    _pending.clear();
    final local = _local;
    _local = null;
    if (local != null) {
      for (final t in local.getTracks()) {
        await t.stop();
      }
      await local.dispose();
    }
    peers.value = <String>{};
    if (!_disposed) joined.value = false;
  }

  Future<void> _onSignal(SignalMessage s) async {
    if (!joined.value) return;
    try {
      switch (s.data['kind']) {
        case 'hello':
          await _offerTo(s.from);
        case 'offer':
          await _onOffer(s.from, s.data);
        case 'answer':
          await _onAnswer(s.from, s.data);
        case 'candidate':
          await _onCandidate(s.from, s.data);
        case 'bye':
          _pending.remove(s.from);
          await _close(s.from);
      }
    } catch (e) {
      error.value = 'Voice connection problem. Try leaving and joining again.';
    }
  }

  Future<RTCPeerConnection> _createPc(String peerId) async {
    final pc = await createPeerConnection({
      'iceServers': _servers,
      'sdpSemantics': 'unified-plan',
    });
    final local = _local;
    if (local != null) {
      for (final t in local.getAudioTracks()) {
        await pc.addTrack(t, local);
      }
    }
    pc.onIceCandidate = (c) {
      if (c.candidate != null) {
        connection.sendSignal(peerId, {
          'kind': 'candidate',
          'candidate': {
            'candidate': c.candidate,
            'sdpMid': c.sdpMid,
            'sdpMLineIndex': c.sdpMLineIndex,
          },
        });
      }
    };
    pc.onConnectionState = (state) {
      if (_disposed) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        peers.value = {...peers.value, peerId};
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        peers.value = {...peers.value}..remove(peerId);
      }
    };
    _pcs[peerId] = pc;
    return pc;
  }

  Future<void> _close(String peerId) async {
    final pc = _pcs.remove(peerId);
    if (pc != null) await pc.close();
    if (!_disposed) peers.value = {...peers.value}..remove(peerId);
  }

  Future<void> _offerTo(String peerId) async {
    await _close(peerId);
    final pc = await _createPc(peerId);
    final offer = await pc.createOffer({'offerToReceiveAudio': true});
    await pc.setLocalDescription(offer);
    connection.sendSignal(peerId, {
      'kind': 'offer',
      'sdp': offer.sdp,
      'type': offer.type,
    });
  }

  Future<void> _onOffer(String peerId, Map<String, dynamic> d) async {
    await _close(peerId);
    final pc = await _createPc(peerId);
    await pc.setRemoteDescription(
      RTCSessionDescription(d['sdp'] as String?, d['type'] as String?),
    );
    await _drain(peerId, pc);
    final answer = await pc.createAnswer({'offerToReceiveAudio': true});
    await pc.setLocalDescription(answer);
    connection.sendSignal(peerId, {
      'kind': 'answer',
      'sdp': answer.sdp,
      'type': answer.type,
    });
  }

  Future<void> _onAnswer(String peerId, Map<String, dynamic> d) async {
    final pc = _pcs[peerId];
    if (pc == null) return;
    await pc.setRemoteDescription(
      RTCSessionDescription(d['sdp'] as String?, d['type'] as String?),
    );
    await _drain(peerId, pc);
  }

  Future<void> _onCandidate(String peerId, Map<String, dynamic> d) async {
    final raw = d['candidate'];
    if (raw is! Map) return;
    final c = RTCIceCandidate(
      raw['candidate'] as String?,
      raw['sdpMid'] as String?,
      raw['sdpMLineIndex'] as int?,
    );
    final pc = _pcs[peerId];
    if (pc == null || await pc.getRemoteDescription() == null) {
      _pending.putIfAbsent(peerId, () => []).add(c);
    } else {
      await pc.addCandidate(c);
    }
  }

  Future<void> _drain(String peerId, RTCPeerConnection pc) async {
    final list = _pending.remove(peerId) ?? const <RTCIceCandidate>[];
    for (final c in list) {
      await pc.addCandidate(c);
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _teardown();
    joined.dispose();
    muted.dispose();
    peers.dispose();
    error.dispose();
  }
}
