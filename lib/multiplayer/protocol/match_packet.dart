import 'dart:convert';

import '../../data/models/match_rules.dart';
import '../../engine/engine.dart';

/// Protocol version checked during initial Host <-> Guest handshake.
const int kP2pProtocolVersion = 1;

/// Sealed wire-protocol messages exchanged over serverless P2P transports
/// (LAN WebSocket today, BLE GATT or online WebSocket in the future).
sealed class MatchPacket {
  const MatchPacket();

  String get type;

  Map<String, dynamic> toPayload();

  String toJsonString() => jsonEncode({
        'type': type,
        ...toPayload(),
      });

  static MatchPacket fromJsonString(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final type = map['type'] as String? ?? '';
    return switch (type) {
      'hello' => HelloPacket.fromJson(map),
      'match_start' => MatchStartPacket.fromJson(map),
      'move' => MovePacket.fromJson(map),
      'move_ack' => MoveAckPacket.fromJson(map),
      'undo_request' => UndoRequestPacket.fromJson(map),
      'undo_response' => UndoResponsePacket.fromJson(map),
      'timeout' => TimeoutPacket.fromJson(map),
      'rematch_request' => const RematchRequestPacket(),
      'rematch_response' => RematchResponsePacket.fromJson(map),
      'leave' => const LeavePacket(),
      'ping' => PingPacket.fromJson(map),
      'pong' => PongPacket.fromJson(map),
      _ => throw FormatException('Unknown MatchPacket type: $type'),
    };
  }
}

/// Initial handshake sent by Guest (and replied by Host) upon connection.
final class HelloPacket extends MatchPacket {
  const HelloPacket({
    required this.playerName,
    this.protocolVersion = kP2pProtocolVersion,
  });

  factory HelloPacket.fromJson(Map<String, dynamic> json) => HelloPacket(
        playerName: json['playerName'] as String? ?? 'Player',
        protocolVersion: json['protocolVersion'] as int? ?? 1,
      );

  final String playerName;
  final int protocolVersion;

  @override
  String get type => 'hello';

  @override
  Map<String, dynamic> toPayload() => {
        'playerName': playerName,
        'protocolVersion': protocolVersion,
      };
}

/// Host-authoritative match start configuration synchronized to Guest.
final class MatchStartPacket extends MatchPacket {
  const MatchStartPacket({
    required this.matchId,
    required this.rules,
    required this.hostStone,
    required this.hostName,
    required this.guestName,
  });

  factory MatchStartPacket.fromJson(Map<String, dynamic> json) =>
      MatchStartPacket(
        matchId: json['matchId'] as String? ?? '',
        rules: MatchRules.fromJson(
          (json['rules'] as Map<String, dynamic>?) ?? const {},
        ),
        hostStone: Stone.fromCode(json['hostStone'] as int? ?? Stone.black.code),
        hostName: json['hostName'] as String? ?? 'Host',
        guestName: json['guestName'] as String? ?? 'Guest',
      );

  final String matchId;
  final MatchRules rules;
  final Stone hostStone;
  final String hostName;
  final String guestName;

  Stone get guestStone => hostStone.opponent;

  @override
  String get type => 'match_start';

  @override
  Map<String, dynamic> toPayload() => {
        'matchId': matchId,
        'rules': rules.toJson(),
        'hostStone': hostStone.code,
        'hostName': hostName,
        'guestName': guestName,
      };
}

/// Stone placement proposal/broadcast with 1-based move sequence number.
final class MovePacket extends MatchPacket {
  const MovePacket({
    required this.seq,
    required this.coordinate,
    required this.stone,
  });

  factory MovePacket.fromJson(Map<String, dynamic> json) => MovePacket(
        seq: json['seq'] as int,
        coordinate: Coordinate.fromIndex(json['index'] as int),
        stone: Stone.fromCode(json['stone'] as int),
      );

  final int seq;
  final Coordinate coordinate;
  final Stone stone;

  @override
  String get type => 'move';

  @override
  Map<String, dynamic> toPayload() => {
        'seq': seq,
        'index': coordinate.index,
        'stone': stone.code,
      };
}

/// Host acknowledgement confirming or rejecting a move sequence.
final class MoveAckPacket extends MatchPacket {
  const MoveAckPacket({
    required this.seq,
    required this.accepted,
    this.reason,
  });

  factory MoveAckPacket.fromJson(Map<String, dynamic> json) => MoveAckPacket(
        seq: json['seq'] as int,
        accepted: json['accepted'] as bool? ?? false,
        reason: json['reason'] as String?,
      );

  final int seq;
  final bool accepted;
  final String? reason;

  @override
  String get type => 'move_ack';

  @override
  Map<String, dynamic> toPayload() => {
        'seq': seq,
        'accepted': accepted,
        if (reason != null) 'reason': reason,
      };
}

/// Request from one player asking opponent's consent to undo the last move.
final class UndoRequestPacket extends MatchPacket {
  const UndoRequestPacket({
    required this.requesterStone,
    required this.currentMoveCount,
  });

  factory UndoRequestPacket.fromJson(Map<String, dynamic> json) =>
      UndoRequestPacket(
        requesterStone: Stone.fromCode(json['requesterStone'] as int),
        currentMoveCount: json['currentMoveCount'] as int,
      );

  final Stone requesterStone;
  final int currentMoveCount;

  @override
  String get type => 'undo_request';

  @override
  Map<String, dynamic> toPayload() => {
        'requesterStone': requesterStone.code,
        'currentMoveCount': currentMoveCount,
      };
}

final class UndoResponsePacket extends MatchPacket {
  const UndoResponsePacket({required this.accepted});

  factory UndoResponsePacket.fromJson(Map<String, dynamic> json) =>
      UndoResponsePacket(accepted: json['accepted'] as bool? ?? false);

  final bool accepted;

  @override
  String get type => 'undo_response';

  @override
  Map<String, dynamic> toPayload() => {'accepted': accepted};
}

/// Host-authoritative timeout verdict when a player's turn clock hits 0.
final class TimeoutPacket extends MatchPacket {
  const TimeoutPacket({required this.winner});

  factory TimeoutPacket.fromJson(Map<String, dynamic> json) => TimeoutPacket(
        winner: Stone.fromCode(json['winner'] as int),
      );

  final Stone winner;

  @override
  String get type => 'timeout';

  @override
  Map<String, dynamic> toPayload() => {'winner': winner.code};
}

final class RematchRequestPacket extends MatchPacket {
  const RematchRequestPacket();

  @override
  String get type => 'rematch_request';

  @override
  Map<String, dynamic> toPayload() => const {};
}

final class RematchResponsePacket extends MatchPacket {
  const RematchResponsePacket({required this.accepted});

  factory RematchResponsePacket.fromJson(Map<String, dynamic> json) =>
      RematchResponsePacket(accepted: json['accepted'] as bool? ?? false);

  final bool accepted;

  @override
  String get type => 'rematch_response';

  @override
  Map<String, dynamic> toPayload() => {'accepted': accepted};
}

final class LeavePacket extends MatchPacket {
  const LeavePacket();

  @override
  String get type => 'leave';

  @override
  Map<String, dynamic> toPayload() => const {};
}

final class PingPacket extends MatchPacket {
  const PingPacket({required this.timestampMs});

  factory PingPacket.fromJson(Map<String, dynamic> json) => PingPacket(
        timestampMs: json['ts'] as int? ?? 0,
      );

  final int timestampMs;

  @override
  String get type => 'ping';

  @override
  Map<String, dynamic> toPayload() => {'ts': timestampMs};
}

final class PongPacket extends MatchPacket {
  const PongPacket({required this.timestampMs});

  factory PongPacket.fromJson(Map<String, dynamic> json) => PongPacket(
        timestampMs: json['ts'] as int? ?? 0,
      );

  final int timestampMs;

  @override
  String get type => 'pong';

  @override
  Map<String, dynamic> toPayload() => {'ts': timestampMs};
}
