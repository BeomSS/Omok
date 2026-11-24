import 'dart:async';
import 'dart:io';

import '../protocol/match_packet.dart';
import 'match_transport.dart';

/// Serverless LAN / Hotspot P2P transport powered by Dart's built-in `dart:io`
/// [HttpServer] and [WebSocket].
///
/// Uses dual-stack binding (IPv4 + IPv6), filters out unreachable cellular/VPN
/// interfaces, and supports multi-address fallback so iOS Personal Hotspot and
/// Android Hotspot connections succeed reliably without a central server.
class LanWebSocketTransport implements MatchTransport {
  LanWebSocketTransport._();

  HttpServer? _server;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSub;
  Timer? _heartbeatTimer;
  bool _closed = false;

  final StreamController<MatchPacket> _incoming =
      StreamController<MatchPacket>.broadcast();
  final StreamController<TransportConnectionState> _stateController =
      StreamController<TransportConnectionState>.broadcast();
  TransportConnectionState _state = TransportConnectionState.disconnected;

  int? _boundPort;
  List<String> _localIpv4Addresses = const [];
  String? _connectedAddress;
  String? _lastError;

  int? get boundPort => _boundPort;
  List<String> get localIpv4Addresses => _localIpv4Addresses;
  String? get primaryLocalIp =>
      _localIpv4Addresses.isEmpty ? null : _localIpv4Addresses.first;
  String? get connectedAddress => _connectedAddress;
  String? get lastError => _lastError;

  @override
  Stream<MatchPacket> get incomingPackets => _incoming.stream;

  @override
  Stream<TransportConnectionState> get connectionState =>
      _stateController.stream;

  @override
  TransportConnectionState get currentState => _state;

  /// Starts hosting a local WebSocket server on [port] (`0` = auto-pick free port).
  ///
  /// Attempts dual-stack IPv6 (`v6Only: false`) first so both IPv4 (`172.20.10.1`,
  /// `192.168.x.x`) and IPv6/Bonjour link-local peers can connect on the same port.
  static Future<LanWebSocketTransport> host({int port = 0}) async {
    final transport = LanWebSocketTransport._();
    try {
      HttpServer server;
      try {
        server = await HttpServer.bind(
          InternetAddress.anyIPv6,
          port,
          v6Only: false,
        );
      } catch (_) {
        server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      }

      transport._server = server;
      transport._boundPort = server.port;
      transport._localIpv4Addresses = await discoverLocalIpv4Addresses();
      transport._setState(TransportConnectionState.hosting);

      server.listen(
        (HttpRequest request) async {
          if (transport._closed) {
            request.response
              ..statusCode = HttpStatus.serviceUnavailable
              ..close();
            return;
          }

          if (transport._socket != null) {
            request.response
              ..statusCode = HttpStatus.conflict
              ..write('Room already full')
              ..close();
            return;
          }

          if (!WebSocketTransformer.isUpgradeRequest(request)) {
            request.response
              ..statusCode = HttpStatus.badRequest
              ..write('WebSocket required')
              ..close();
            return;
          }

          try {
            final ws = await WebSocketTransformer.upgrade(request);
            transport._attachSocket(ws);
          } catch (e) {
            transport._lastError = e.toString();
          }
        },
        onError: (Object err) {
          transport._lastError = err.toString();
          if (!transport._closed) {
            transport._setState(TransportConnectionState.error);
          }
        },
      );

      return transport;
    } catch (e) {
      transport._lastError = e.toString();
      transport._setState(TransportConnectionState.error);
      await transport.close();
      rethrow;
    }
  }

  /// Connects as a Guest to a single Host WebSocket endpoint.
  static Future<LanWebSocketTransport> connect({
    required String host,
    required int port,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final transport = LanWebSocketTransport._();
    transport._setState(TransportConnectionState.connecting);

    final uri = buildWebSocketUri(host, port);

    try {
      final ws = await WebSocket.connect(uri).timeout(timeout);
      transport._connectedAddress = host;
      transport._attachSocket(ws);
      return transport;
    } catch (e) {
      transport._lastError = e.toString();
      transport._setState(TransportConnectionState.error);
      await transport.close();
      rethrow;
    }
  }

  /// Connects to the first reachable candidate in [hosts] on [port].
  ///
  /// Essential for Personal Hotspots where a host phone exposes multiple IPs
  /// (cellular `pdp_ip0`, hotspot `bridge100` `172.20.10.1`, IPv6 `fe80::...`).
  static Future<LanWebSocketTransport> connectAny({
    required List<String> hosts,
    required int port,
    Duration perAttemptTimeout = const Duration(milliseconds: 2500),
  }) async {
    final uniqueHosts = hosts
        .map((h) => h.trim())
        .where((h) => h.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (uniqueHosts.isEmpty) {
      throw ArgumentError('At least one host address is required.');
    }

    final attempts = <String>[];
    Object? lastError;

    for (final candidate in uniqueHosts) {
      try {
        return await connect(
          host: candidate,
          port: port,
          timeout: perAttemptTimeout,
        );
      } catch (e) {
        lastError = e;
        attempts.add('$candidate ($port): ${_summarizeError(e)}');
      }
    }

    throw SocketException(
      'All candidate addresses failed: ${attempts.join(' | ')} '
      '(last: $lastError)',
    );
  }

  /// Formats a valid `ws://` URI, properly bracketing IPv6 literals and
  /// percent-encoding zone IDs (`fe80::1%en0` -> `ws://[fe80::1%25en0]:port`).
  static String buildWebSocketUri(String host, int port) {
    final trimmed = host.trim();
    if (trimmed.contains(':')) {
      final bare = trimmed.startsWith('[') && trimmed.endsWith(']')
          ? trimmed.substring(1, trimmed.length - 1)
          : trimmed;
      final encodedZone = bare.replaceAll('%', '%25');
      return 'ws://[$encodedZone]:$port';
    }
    return 'ws://$trimmed:$port';
  }

  /// Sorts [candidates] so addresses on the same `/24` subnet as any of
  /// [localIps] come first (e.g. Guest `172.20.10.2` picks Host `172.20.10.1`
  /// ahead of Host's unreachable cellular `10.x.x.x` or IPv6 link-local).
  static List<String> prioritizeAddressesForLocalSubnets(
    Iterable<String> candidates,
    List<String> localIps,
  ) {
    final localPrefixes = <String>{};
    for (final ip in localIps) {
      final prefix = _ipv4Prefix24(ip);
      if (prefix != null) {
        localPrefixes.add(prefix);
      }
    }

    final deduped = <String>[];
    final seen = <String>{};
    for (final raw in candidates) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) continue;
      if (trimmed == '0.0.0.0' || trimmed == '::' || trimmed == '::1') continue;
      deduped.add(trimmed);
    }

    int rank(String addr) {
      final isIpv6 = addr.contains(':');
      if (!isIpv6) {
        final prefix = _ipv4Prefix24(addr);
        if (prefix != null && localPrefixes.contains(prefix)) {
          return 0; // Same /24 subnet as this device (Wi-Fi or Hotspot match!)
        }
        if (addr.startsWith('172.20.10.') || addr.startsWith('192.168.43.')) {
          return 1; // Known iOS / Android Personal Hotspot subnets
        }
        if (addr.startsWith('192.168.')) {
          return 2; // Standard private LAN
        }
        if (_isRfc1918PrivateIpv4(addr)) {
          return 3; // Other private IPv4 (10.x, 172.16-31.x — may include cellular)
        }
        if (addr.startsWith('169.254.')) {
          return 6; // APIPA link-local fallback
        }
        if (addr.endsWith('.local') || addr.endsWith('.local.')) {
          return 4; // mDNS hostname
        }
        return 5;
      }

      // IPv6 addresses: prefer non-link-local over link-local (zone-sensitive).
      if (addr.toLowerCase().startsWith('fe80:')) {
        return 7;
      }
      return 5;
    }

    deduped.sort((a, b) => rank(a).compareTo(rank(b)));
    return deduped;
  }

  void _attachSocket(WebSocket ws) {
    _socket = ws;
    ws.pingInterval = const Duration(seconds: 5);
    _setState(TransportConnectionState.connected);
    _startHeartbeat();

    _socketSub = ws.listen(
      (dynamic raw) {
        if (raw is! String) return;
        try {
          final packet = MatchPacket.fromJsonString(raw);
          if (packet is PingPacket) {
            _sendRaw(PongPacket(timestampMs: packet.timestampMs));
            return;
          }
          if (packet is PongPacket) {
            return;
          }
          if (!_incoming.isClosed) {
            _incoming.add(packet);
          }
        } catch (_) {
          // Ignore malformed frames safely.
        }
      },
      onDone: () {
        if (!_closed) {
          _stopHeartbeat();
          _socket = null;
          _setState(TransportConnectionState.disconnected);
        }
      },
      onError: (Object err) {
        _lastError = err.toString();
        if (!_closed) {
          _stopHeartbeat();
          _socket = null;
          _setState(TransportConnectionState.disconnected);
        }
      },
      cancelOnError: true,
    );
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (_state == TransportConnectionState.connected) {
        _sendRaw(
          PingPacket(timestampMs: DateTime.now().millisecondsSinceEpoch),
        );
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _sendRaw(MatchPacket packet) {
    final ws = _socket;
    if (ws == null || ws.readyState != WebSocket.open) return;
    try {
      ws.add(packet.toJsonString());
    } catch (_) {}
  }

  @override
  Future<void> send(MatchPacket packet) async {
    final ws = _socket;
    if (ws == null || ws.readyState != WebSocket.open) {
      throw StateError('WebSocket is not connected.');
    }
    ws.add(packet.toJsonString());
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _stopHeartbeat();

    await _socketSub?.cancel();
    _socketSub = null;

    final ws = _socket;
    _socket = null;
    if (ws != null) {
      try {
        await ws.close();
      } catch (_) {}
    }

    final srv = _server;
    _server = null;
    if (srv != null) {
      try {
        await srv.close(force: true);
      } catch (_) {}
    }

    _setState(TransportConnectionState.disconnected);
    await _incoming.close();
    await _stateController.close();
  }

  void _setState(TransportConnectionState next) {
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  /// Finds active local Wi-Fi / Hotspot IPv4 addresses while filtering out
  /// unreachable cellular (`pdp_ip*`, `rmnet*`) and VPN (`utun*`, `ipsec*`)
  /// interfaces.
  static Future<List<String>> discoverLocalIpv4Addresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final candidates = <(int, String)>[];
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (_isExcludedInterfaceName(name)) {
          continue;
        }

        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          final ip = addr.address;
          if (ip.startsWith('169.254.')) continue; // Unassigned link-local

          var priority = 4;
          // iOS Personal Hotspot (`bridge100`: 172.20.10.1) & Android Hotspot (`ap0`/`swlan0`)
          if (name.startsWith('bridge') ||
              name.startsWith('ap') ||
              name.startsWith('swlan') ||
              ip.startsWith('172.20.10.') ||
              ip.startsWith('192.168.43.')) {
            priority = 0;
          } else if (name == 'en0' ||
              name.startsWith('wlan') ||
              ip.startsWith('192.168.')) {
            priority = 1;
          } else if (name.startsWith('en') || _isRfc1918PrivateIpv4(ip)) {
            priority = 2;
          }
          candidates.add((priority, ip));
        }
      }

      candidates.sort((a, b) => a.$1.compareTo(b.$1));
      return candidates.map((e) => e.$2).toSet().toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static bool _isExcludedInterfaceName(String lowerName) {
    const blockedPrefixes = [
      'pdp_ip', // iOS cellular
      'rmnet', // Android Qualcomm cellular
      'ccmni', // Android MediaTek cellular
      'seth_lte', // Android Samsung cellular
      'v4-rmnet',
      'utun', // iOS/macOS VPN / iCloud Private Relay
      'ipsec', // VPN
      'tun', // Android VPN
      'ppp',
      'awdl', // Apple Wireless Direct Link
      'llw', // Apple low-latency Wi-Fi
      'lo',
    ];
    for (final prefix in blockedPrefixes) {
      if (lowerName.startsWith(prefix)) return true;
    }
    return false;
  }

  static String? _ipv4Prefix24(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return null;
    }
    return '${parts[0]}.${parts[1]}.${parts[2]}.';
  }

  static bool _isRfc1918PrivateIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) return false;
    if (a == 10) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    return false;
  }

  static String _summarizeError(Object error) {
    if (error is TimeoutException) return 'timeout';
    if (error is SocketException) {
      return error.osError?.message ?? error.message;
    }
    return error.runtimeType.toString();
  }
}
