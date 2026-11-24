import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omok/data/models/match_rules.dart';
import 'package:omok/data/models/saved_match.dart';
import 'package:omok/data/repositories/local_storage_repository.dart';
import 'package:omok/engine/engine.dart';
import 'package:omok/features/game/controller/game_controller.dart';
import 'package:omok/multiplayer/multiplayer.dart';
import 'package:omok/shared/providers/app_providers.dart';
import 'package:omok/shared/services/sound_service.dart';

ProviderContainer _createDeviceContainer() {
  final storage = InMemoryStorageRepository();
  storage.saveSettings(
    storage.loadSettings().copyWith(confirmBeforePlace: false),
  );
  return ProviderContainer(
    overrides: [
      storageRepositoryProvider.overrideWithValue(storage),
      soundServiceProvider.overrideWithValue(const SilentSoundService()),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LanWebSocketTransport real local TCP WebSocket', () {
    test('connects Host and Guest over 127.0.0.1 and exchanges MatchPackets',
        () async {
      final host = await LanWebSocketTransport.host(port: 0);
      addTearDown(host.close);
      expect(host.boundPort, isNotNull);
      expect(host.currentState, TransportConnectionState.hosting);

      final guest = await LanWebSocketTransport.connect(
        host: '127.0.0.1',
        port: host.boundPort!,
      );
      addTearDown(guest.close);

      expect(guest.currentState, TransportConnectionState.connected);

      final hostReceivedHello = host.incomingPackets.first;
      await guest.send(const HelloPacket(playerName: '테스터'));
      final hello = await hostReceivedHello;
      expect(hello, isA<HelloPacket>());
      expect((hello as HelloPacket).playerName, '테스터');

      final guestReceivedMove = guest.incomingPackets.first;
      await host.send(
        const MovePacket(
          seq: 1,
          coordinate: Coordinate(7, 7),
          stone: Stone.black,
        ),
      );
      final move = await guestReceivedMove;
      expect(move, isA<MovePacket>());
      expect((move as MovePacket).coordinate, const Coordinate(7, 7));

      await host.close();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(host.currentState, TransportConnectionState.disconnected);
    });

    test('prioritizes same-/24 iOS hotspot IP ahead of cellular & IPv6 link-local',
        () {
      final ranked = LanWebSocketTransport.prioritizeAddressesForLocalSubnets(
        const [
          'fe80::1234:5678%en0',
          '10.123.45.67', // Unreachable cellular IP
          'beom-iphone.local',
          '172.20.10.1', // Reachable iOS Personal Hotspot gateway
        ],
        const ['172.20.10.2'], // Guest iPhone on iOS hotspot
      );

      expect(ranked.first, '172.20.10.1');
      expect(ranked.last, 'fe80::1234:5678%en0');
      expect(
        LanWebSocketTransport.buildWebSocketUri('fe80::1234%en0', 50000),
        'ws://[fe80::1234%25en0]:50000',
      );
    });

    test('connectAny automatically falls back past unreachable candidate to live host',
        () async {
      final host = await LanWebSocketTransport.host(port: 0);
      addTearDown(host.close);

      // First address is unreachable / invalid, second is live dual-stack loopback.
      final guest = await LanWebSocketTransport.connectAny(
        hosts: const ['invalid.local.nonexistent', '127.0.0.1'],
        port: host.boundPort!,
        perAttemptTimeout: const Duration(milliseconds: 800),
      );
      addTearDown(guest.close);

      expect(guest.currentState, TransportConnectionState.connected);
      expect(guest.connectedAddress, '127.0.0.1');
    });
  });

  group('Nearby P2P GameController full synchronization', () {
    test('synchronizes moves, undo consent, win detection, rematch, and leave',
        () async {
      final (hostTransport, guestTransport) =
          LoopbackMatchTransport.createPair();
      final hostContainer = _createDeviceContainer();
      final guestContainer = _createDeviceContainer();
      addTearDown(() async {
        hostContainer.dispose();
        guestContainer.dispose();
        await hostTransport.close();
        await guestTransport.close();
      });

      const rules = MatchRules(
        ruleType: RuleType.renju,
        useTimeLimit: false,
        undoLimit: UndoLimit.three,
      );

      final hostCtrl = hostContainer.read(gameControllerProvider.notifier);
      final guestCtrl = guestContainer.read(gameControllerProvider.notifier);

      hostCtrl.startNearbyP2pGame(
        transport: hostTransport,
        isHost: true,
        localStone: Stone.black,
        hostStonePreference: StonePreference.black,
        rules: rules,
        localName: '방장',
        opponentName: '참가자',
      );
      guestCtrl.startNearbyP2pGame(
        transport: guestTransport,
        isHost: false,
        localStone: Stone.white,
        hostStonePreference: StonePreference.black,
        rules: rules,
        localName: '참가자',
        opponentName: '방장',
      );

      // 1. Host (Black) plays (7,7) -> synced to Guest.
      hostCtrl.onIntersectionTapped(const Coordinate(7, 7));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(hostContainer.read(gameControllerProvider).board.moveCount, 1);
      expect(guestContainer.read(gameControllerProvider).board.moveCount, 1);
      expect(guestContainer.read(gameControllerProvider).isHumanTurn, isTrue);

      // 2. Guest (White) plays (6,7) -> synced to Host.
      guestCtrl.onIntersectionTapped(const Coordinate(6, 7));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(hostContainer.read(gameControllerProvider).board.moveCount, 2);
      expect(hostContainer.read(gameControllerProvider).isHumanTurn, isTrue);

      // 3. Guest requests Undo -> Host accepts -> both revert to 1 move.
      guestCtrl.undo();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        hostContainer.read(gameControllerProvider).hasIncomingUndoRequest,
        isTrue,
      );
      hostCtrl.respondToUndoRequest(true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(hostContainer.read(gameControllerProvider).board.moveCount, 1);
      expect(guestContainer.read(gameControllerProvider).board.moveCount, 1);
      expect(hostContainer.read(gameControllerProvider).undosUsed, 1);
      expect(guestContainer.read(gameControllerProvider).undosUsed, 1);

      // 4. Complete 5-in-a-row for Host (Black).
      final sequence = [
        (false, const Coordinate(6, 5)), // 2 W
        (true, const Coordinate(7, 8)), // 3 B
        (false, const Coordinate(6, 6)), // 4 W
        (true, const Coordinate(7, 9)), // 5 B
        (false, const Coordinate(6, 7)), // 6 W
        (true, const Coordinate(7, 10)), // 7 B
        (false, const Coordinate(6, 8)), // 8 W
        (true, const Coordinate(7, 11)), // 9 B -> Win!
      ];
      for (final (isHostTurn, coord) in sequence) {
        if (isHostTurn) {
          hostCtrl.onIntersectionTapped(coord);
        } else {
          guestCtrl.onIntersectionTapped(coord);
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(
        hostContainer.read(gameControllerProvider).result.status,
        GameStatus.blackWin,
      );
      expect(
        guestContainer.read(gameControllerProvider).result.status,
        GameStatus.blackWin,
      );

      // 5. Guest requests rematch -> Host accepts -> both reset to 0 moves!
      guestCtrl.requestP2pRematch();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        hostContainer.read(gameControllerProvider).hasIncomingRematchRequest,
        isTrue,
      );
      hostCtrl.respondToRematchRequest(true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(hostContainer.read(gameControllerProvider).board.moveCount, 0);
      expect(guestContainer.read(gameControllerProvider).board.moveCount, 0);
      expect(hostContainer.read(gameControllerProvider).isGameOver, isFalse);

      // 6. Host leaves -> Guest is notified of disconnect.
      hostCtrl.pauseAndLeave();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        guestContainer.read(gameControllerProvider).isOpponentDisconnected,
        isTrue,
      );
    });
  });
}
