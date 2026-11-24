import 'dart:async';

import '../../engine/engine.dart';
import '../protocol/match_packet.dart';

/// Lifecycle states of a peer-to-peer match transport.
enum TransportConnectionState {
  disconnected,
  hosting,
  connecting,
  connected,
  error,
}

/// Metadata advertised over local network discovery (mDNS / Bonjour) for
/// serverless nearby rooms.
class DiscoveredRoom {
  const DiscoveredRoom({
    required this.roomName,
    required this.hostAddress,
    required this.port,
    required this.ruleType,
    this.candidateAddresses = const [],
    this.turnTimeLimitSeconds,
  });

  final String roomName;
  final String hostAddress;

  /// Ordered list of all candidate addresses (subnet-matched IPv4 first,
  /// followed by other LAN IPv4s, mDNS hostname, and IPv6).
  final List<String> candidateAddresses;

  final int port;
  final RuleType ruleType;
  final int? turnTimeLimitSeconds;

  List<String> get resolvedCandidates =>
      candidateAddresses.isNotEmpty ? candidateAddresses : [hostAddress];

  String get endpoint => '$hostAddress:$port';
}

/// Abstract bidirectional transport for serverless P2P or online matches.
///
/// Step 2 will implement `LanWebSocketTransport` behind this contract; future
/// BLE GATT or cloud WebSocket transports can plug in without modifying game
/// logic.
abstract class MatchTransport {
  Stream<MatchPacket> get incomingPackets;
  Stream<TransportConnectionState> get connectionState;
  TransportConnectionState get currentState;

  Future<void> send(MatchPacket packet);
  Future<void> close();
}

/// Paired in-memory transport for deterministic Host <-> Guest unit & widget
/// testing without physical network sockets.
class LoopbackMatchTransport implements MatchTransport {
  LoopbackMatchTransport._();

  /// Creates a connected `(hostTransport, guestTransport)` pair.
  static (LoopbackMatchTransport, LoopbackMatchTransport) createPair() {
    final a = LoopbackMatchTransport._();
    final b = LoopbackMatchTransport._();
    a._peer = b;
    b._peer = a;
    a._setState(TransportConnectionState.connected);
    b._setState(TransportConnectionState.connected);
    return (a, b);
  }

  LoopbackMatchTransport? _peer;
  final StreamController<MatchPacket> _incoming =
      StreamController<MatchPacket>.broadcast();
  final StreamController<TransportConnectionState> _stateController =
      StreamController<TransportConnectionState>.broadcast();
  TransportConnectionState _state = TransportConnectionState.disconnected;

  @override
  Stream<MatchPacket> get incomingPackets => _incoming.stream;

  @override
  Stream<TransportConnectionState> get connectionState =>
      _stateController.stream;

  @override
  TransportConnectionState get currentState => _state;

  @override
  Future<void> send(MatchPacket packet) async {
    if (_state != TransportConnectionState.connected) {
      throw StateError('Cannot send packet while transport is $_state.');
    }
    // Round-trip through JSON to validate real wire serialization in tests.
    final decoded = MatchPacket.fromJsonString(packet.toJsonString());
    final peer = _peer;
    if (peer != null && !peer._incoming.isClosed) {
      peer._incoming.add(decoded);
    }
  }

  @override
  Future<void> close() async {
    _setState(TransportConnectionState.disconnected);
    final peer = _peer;
    _peer = null;
    if (peer != null && peer._peer == this) {
      peer._peer = null;
      peer._setState(TransportConnectionState.disconnected);
    }
    await _incoming.close();
    await _stateController.close();
  }

  void _setState(TransportConnectionState next) {
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }
}
