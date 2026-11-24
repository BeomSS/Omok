import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

import '../../data/models/match_rules.dart';
import '../../engine/engine.dart';
import 'lan_websocket_transport.dart';
import 'match_transport.dart';

/// mDNS / Bonjour service discovery wrapper (`_omok._tcp`) for serverless
/// nearby room advertising and scanning on Wi-Fi or personal hotspots.
class LanDiscoveryService {
  static const String serviceType = '_omok._tcp';

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _discoverySub;

  List<String> _localIps = const [];
  final Map<String, DiscoveredRoom> _roomsByName = {};
  final StreamController<List<DiscoveredRoom>> _roomsController =
      StreamController<List<DiscoveredRoom>>.broadcast();

  Stream<List<DiscoveredRoom>> get roomsStream => _roomsController.stream;
  List<DiscoveredRoom> get currentRooms =>
      List.unmodifiable(_roomsByName.values);

  /// Advertises a local Omok room over mDNS so nearby devices can discover it.
  Future<void> startBroadcast({
    required String roomName,
    required int port,
    required MatchRules rules,
    List<String> advertisedIps = const [],
  }) async {
    await stopBroadcast();

    final cleanIps = advertisedIps
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(4)
        .toList(growable: false);

    final service = BonsoirService(
      name: roomName,
      type: serviceType,
      port: port,
      attributes: {
        'rule': rules.ruleType.name,
        'time': rules.useTimeLimit ? '${rules.turnTimeLimitSeconds}' : '0',
        if (cleanIps.isNotEmpty) 'ip': cleanIps.first,
        if (cleanIps.isNotEmpty) 'ips': cleanIps.join(','),
      },
    );

    final broadcast = BonsoirBroadcast(service: service, printLogs: false);
    await broadcast.initialize();
    await broadcast.start();
    _broadcast = broadcast;
  }

  Future<void> stopBroadcast() async {
    final current = _broadcast;
    _broadcast = null;
    if (current != null) {
      try {
        await current.stop();
      } catch (_) {}
    }
  }

  /// Starts scanning the local network for nearby Omok rooms.
  Future<void> startDiscovery() async {
    await stopDiscovery();
    _roomsByName.clear();
    _localIps = await LanWebSocketTransport.discoverLocalIpv4Addresses();
    _emitRooms();

    final discovery = BonsoirDiscovery(type: serviceType, printLogs: false);
    await discovery.initialize();
    _discovery = discovery;

    _discoverySub = discovery.eventStream?.listen((event) {
      switch (event) {
        case BonsoirDiscoveryServiceFoundEvent():
          discovery.serviceResolver.resolveService(event.service);
        case BonsoirDiscoveryServiceResolvedEvent():
          _upsertService(event.service);
        case BonsoirDiscoveryServiceUpdatedEvent():
          _upsertService(event.service);
        case BonsoirDiscoveryServiceLostEvent():
          _roomsByName.remove(event.service.name);
          _emitRooms();
        default:
          break;
      }
    });

    await discovery.start();
  }

  Future<void> stopDiscovery() async {
    await _discoverySub?.cancel();
    _discoverySub = null;
    final current = _discovery;
    _discovery = null;
    if (current != null) {
      try {
        await current.stop();
      } catch (_) {}
    }
  }

  void _upsertService(BonsoirService service) {
    final candidates = _collectCandidateAddresses(service);
    if (candidates.isEmpty || service.port <= 0) return;

    final ruleAttr = service.attributes['rule'];
    final ruleType = ruleAttr == RuleType.freestyle.name
        ? RuleType.freestyle
        : RuleType.renju;
    final parsedTime = int.tryParse(service.attributes['time'] ?? '0') ?? 0;

    _roomsByName[service.name] = DiscoveredRoom(
      roomName: service.name,
      hostAddress: candidates.first,
      candidateAddresses: candidates,
      port: service.port,
      ruleType: ruleType,
      turnTimeLimitSeconds: parsedTime > 0 ? parsedTime : null,
    );
    _emitRooms();
  }

  /// Combines TXT-advertised LAN/Hotspot IPs, resolved Bonjour addresses, and
  /// mDNS hostname, then ranks them against this device's active `/24` subnets.
  List<String> _collectCandidateAddresses(BonsoirService service) {
    final raw = <String>[];

    final txtIps = service.attributes['ips'];
    if (txtIps != null && txtIps.isNotEmpty) {
      raw.addAll(txtIps.split(','));
    }
    final txtIp = service.attributes['ip'];
    if (txtIp != null && txtIp.isNotEmpty) {
      raw.add(txtIp);
    }

    raw.addAll(service.hostAddresses);

    if (service.hostname != null && service.hostname!.isNotEmpty) {
      raw.add(service.hostname!);
    }

    // Hotspot gateway fallback: when connected to an iOS (172.20.10.x) or
    // Android (192.168.43.x) personal hotspot, the hotspot host is always `.1`.
    for (final localIp in _localIps) {
      if (localIp.startsWith('172.20.10.') && localIp != '172.20.10.1') {
        raw.add('172.20.10.1');
      } else if (localIp.startsWith('192.168.43.') &&
          localIp != '192.168.43.1') {
        raw.add('192.168.43.1');
      }
    }

    return LanWebSocketTransport.prioritizeAddressesForLocalSubnets(
      raw,
      _localIps,
    );
  }

  void _emitRooms() {
    if (!_roomsController.isClosed) {
      _roomsController.add(List.unmodifiable(_roomsByName.values));
    }
  }

  Future<void> dispose() async {
    await stopBroadcast();
    await stopDiscovery();
    await _roomsController.close();
  }
}
