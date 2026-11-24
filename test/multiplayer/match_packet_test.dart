import 'package:flutter_test/flutter_test.dart';
import 'package:omok/data/models/match_rules.dart';
import 'package:omok/engine/engine.dart';
import 'package:omok/multiplayer/multiplayer.dart';

void main() {
  group('MatchPacket wire serialization', () {
    test('round-trips all packet types accurately through JSON', () {
      final packets = <MatchPacket>[
        const HelloPacket(playerName: '호스트'),
        const MatchStartPacket(
          matchId: 'room-123',
          rules: MatchRules(
            ruleType: RuleType.freestyle,
            useTimeLimit: true,
            turnTimeLimitSeconds: 45,
            undoLimit: UndoLimit.three,
          ),
          hostStone: Stone.black,
          hostName: '호스트',
          guestName: '게스트',
        ),
        const MovePacket(
          seq: 1,
          coordinate: Coordinate(7, 7),
          stone: Stone.black,
        ),
        const MoveAckPacket(seq: 1, accepted: true),
        const UndoRequestPacket(
          requesterStone: Stone.white,
          currentMoveCount: 4,
        ),
        const UndoResponsePacket(accepted: false),
        const TimeoutPacket(winner: Stone.black),
        const RematchRequestPacket(),
        const RematchResponsePacket(accepted: true),
        const LeavePacket(),
        const PingPacket(timestampMs: 123456),
        const PongPacket(timestampMs: 123456),
      ];

      for (final packet in packets) {
        final decoded = MatchPacket.fromJsonString(packet.toJsonString());
        expect(decoded.type, packet.type);
        expect(decoded.toPayload(), packet.toPayload());
      }
    });
  });

  group('LoopbackMatchTransport', () {
    test('delivers packets bidirectionally and propagates disconnect', () async {
      final (host, guest) = LoopbackMatchTransport.createPair();
      expect(host.currentState, TransportConnectionState.connected);
      expect(guest.currentState, TransportConnectionState.connected);

      final guestFuture = guest.incomingPackets.first;
      await host.send(
        const MovePacket(
          seq: 1,
          coordinate: Coordinate(7, 7),
          stone: Stone.black,
        ),
      );

      final received = await guestFuture;
      expect(received, isA<MovePacket>());
      final move = received as MovePacket;
      expect(move.coordinate, const Coordinate(7, 7));
      expect(move.stone, Stone.black);

      await host.close();
      expect(host.currentState, TransportConnectionState.disconnected);
      expect(guest.currentState, TransportConnectionState.disconnected);
    });
  });
}
