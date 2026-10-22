class MediaSourceInfo {
  const MediaSourceInfo({
    required this.kind,
    required this.name,
    this.mime,
    this.size,
    this.url,
    this.fileId,
  });

  final String kind; // local | drive | url
  final String name;
  final String? mime;
  final int? size;
  final String? url;
  final String? fileId;

  factory MediaSourceInfo.fromJson(Map<String, dynamic> j) => MediaSourceInfo(
    kind: j['kind'] as String,
    name: j['name'] as String,
    mime: j['mime'] as String?,
    size: (j['size'] as num?)?.toInt(),
    url: j['url'] as String?,
    fileId: j['fileId'] as String?,
  );

  bool sameAs(MediaSourceInfo? o) =>
      o != null &&
      o.kind == kind &&
      o.name == name &&
      o.fileId == fileId &&
      o.url == url &&
      o.size == size;
}

class Participant {
  const Participant({
    required this.id,
    required this.displayName,
    required this.online,
  });
  final String id;
  final String displayName;
  final bool online;

  factory Participant.fromJson(Map<String, dynamic> j) => Participant(
    id: j['id'] as String,
    displayName: j['displayName'] as String,
    online: j['online'] as bool,
  );
}

class RoomState {
  const RoomState({
    required this.revision,
    required this.playing,
    required this.positionMs,
    required this.updatedAt,
    required this.serverNow,
    required this.source,
    required this.hostId,
    required this.controlMode,
    required this.buffering,
    required this.participants,
  });

  final int revision;
  final bool playing;
  final int positionMs;
  final int updatedAt;
  final int serverNow;
  final MediaSourceInfo? source;
  final String hostId;
  final String controlMode;
  final List<String> buffering;
  final List<Participant> participants;

  factory RoomState.fromJson(Map<String, dynamic> j) => RoomState(
    revision: (j['revision'] as num).toInt(),
    playing: j['playing'] as bool,
    positionMs: (j['positionMs'] as num).toInt(),
    updatedAt: (j['updatedAt'] as num).toInt(),
    serverNow: (j['serverNow'] as num).toInt(),
    source: j['source'] == null
        ? null
        : MediaSourceInfo.fromJson(j['source'] as Map<String, dynamic>),
    hostId: j['hostId'] as String,
    controlMode: j['controlMode'] as String,
    buffering: (j['buffering'] as List<dynamic>).cast<String>(),
    participants: (j['participants'] as List<dynamic>)
        .map((p) => Participant.fromJson(p as Map<String, dynamic>))
        .toList(),
  );

  /// Where playback should be right now, given the current (estimated) server time.
  int targetPositionMs(int serverNowMs) {
    final t = playing ? positionMs + (serverNowMs - updatedAt) : positionMs;
    return t < 0 ? 0 : t;
  }
}

class ChatMessage {
  const ChatMessage({
    required this.fromId,
    required this.fromName,
    required this.text,
    required this.at,
  });
  final String fromId;
  final String fromName;
  final String text;
  final int at;
}

class RoomInfo {
  const RoomInfo({required this.id, required this.code, required this.name});
  final String id;
  final String code;
  final String name;

  factory RoomInfo.fromJson(Map<String, dynamic> j) => RoomInfo(
    id: j['id'] as String,
    code: j['code'] as String,
    name: j['name'] as String,
  );

  Map<String, dynamic> toJson() => {'id': id, 'code': code, 'name': name};
}

class DriveFile {
  const DriveFile({
    required this.id,
    required this.name,
    required this.mimeType,
    this.size,
  });
  final String id;
  final String name;
  final String mimeType;
  final int? size;
  bool get isFolder => mimeType == 'application/vnd.google-apps.folder';

  factory DriveFile.fromJson(Map<String, dynamic> j) => DriveFile(
    id: j['id'] as String,
    name: j['name'] as String,
    mimeType: j['mimeType'] as String,
    size: int.tryParse('${j['size'] ?? ''}'),
  );
}
