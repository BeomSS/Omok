import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models/match_rules.dart';
import '../../data/models/saved_match.dart';
import '../../engine/engine.dart';
import '../../l10n/app_strings.dart';
import '../../multiplayer/multiplayer.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/theme/app_theme.dart';
import '../game/controller/game_controller.dart';
import '../game/game_screen.dart';

enum NearbyRole { host, guest }

/// Serverless Wi-Fi / Hotspot P2P lobby for hosting a room or discovering &
/// joining a nearby peer (with manual IP:Port fallback).
class NearbyLobbyScreen extends ConsumerStatefulWidget {
  const NearbyLobbyScreen({
    super.key,
    required this.initialRole,
    this.hostStonePreference = StonePreference.random,
  });

  final NearbyRole initialRole;
  final StonePreference hostStonePreference;

  @override
  ConsumerState<NearbyLobbyScreen> createState() => _NearbyLobbyScreenState();
}

class _NearbyLobbyScreenState extends ConsumerState<NearbyLobbyScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController();

  final LanDiscoveryService _discovery = LanDiscoveryService();
  LanWebSocketTransport? _transport;
  StreamSubscription<MatchPacket>? _packetSub;
  StreamSubscription<List<DiscoveredRoom>>? _roomsSub;

  late NearbyRole _role;
  late StonePreference _hostStonePreference;
  List<DiscoveredRoom> _rooms = const [];
  bool _initializedDefaultName = false;
  bool _isBusy = false;
  bool _isHosting = false;
  bool _isScanning = false;
  bool _handedOffToGame = false;
  String? _statusText;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _role = widget.initialRole;
    _hostStonePreference = widget.hostStonePreference;

    _roomsSub = _discovery.roomsStream.listen((rooms) {
      if (mounted) {
        setState(() => _rooms = rooms);
      }
    });

    if (_role == NearbyRole.guest) {
      unawaited(_startScanning());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedDefaultName) {
      _initializedDefaultName = true;
      final s = AppStrings.of(context);
      _nameController.text =
          _role == NearbyRole.host ? s.defaultHostName : s.defaultGuestName;
    }
  }

  @override
  void dispose() {
    _roomsSub?.cancel();
    _packetSub?.cancel();
    unawaited(_discovery.dispose());
    if (!_handedOffToGame && _transport != null) {
      unawaited(_transport!.close());
    }
    _nameController.dispose();
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _startHosting() async {
    final s = AppStrings.of(context);
    final rules = ref.read(matchRulesProvider);
    final hostName = _nameController.text.trim().isEmpty
        ? s.defaultHostName
        : _nameController.text.trim();

    setState(() {
      _isBusy = true;
      _errorText = null;
      _statusText = s.openingRoomStatus;
    });

    try {
      await _cleanupPendingTransport();
      final transport = await LanWebSocketTransport.host(port: 0);
      _transport = transport;

      // Start mDNS broadcast (best-effort; IP:Port fallback still works if mDNS blocked).
      try {
        await _discovery.startBroadcast(
          roomName: s.roomBroadcastName(hostName),
          port: transport.boundPort!,
          rules: rules,
          advertisedIps: transport.localIpv4Addresses,
        );
      } catch (_) {
        // Fallback IP:Port connection remains fully functional.
      }

      _packetSub = transport.incomingPackets.listen((packet) {
        if (packet is HelloPacket) {
          _completeHostHandshake(
            transport: transport,
            hostName: hostName,
            guestName: packet.playerName,
            rules: rules,
          );
        }
      });

      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _isHosting = true;
        _statusText = s.waitingGuestStatus;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _isHosting = false;
        _errorText = s.hostOpenFailedError(e);
      });
    }
  }

  Future<void> _stopHosting() async {
    await _discovery.stopBroadcast();
    await _cleanupPendingTransport();
    if (!mounted) return;
    setState(() {
      _isHosting = false;
      _statusText = null;
    });
  }

  void _completeHostHandshake({
    required LanWebSocketTransport transport,
    required String hostName,
    required String guestName,
    required MatchRules rules,
  }) {
    if (_handedOffToGame) return;
    _handedOffToGame = true;

    final Stone hostStone;
    if (_hostStonePreference == StonePreference.random) {
      hostStone = ref.read(randomProvider).nextBool() ? Stone.black : Stone.white;
    } else {
      hostStone = _hostStonePreference == StonePreference.white
          ? Stone.white
          : Stone.black;
    }

    final startPacket = MatchStartPacket(
      matchId: DateTime.now().millisecondsSinceEpoch.toString(),
      rules: rules,
      hostStone: hostStone,
      hostName: hostName,
      guestName: guestName,
    );

    unawaited(_discovery.stopBroadcast());
    _packetSub?.cancel();
    _packetSub = null;

    unawaited(transport.send(startPacket));

    ref.read(gameControllerProvider.notifier).startNearbyP2pGame(
          transport: transport,
          isHost: true,
          localStone: hostStone,
          hostStonePreference: _hostStonePreference,
          rules: rules,
          localName: hostName,
          opponentName: guestName,
        );

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const GameScreen()),
    );
  }

  Future<void> _startScanning() async {
    setState(() {
      _isScanning = true;
      _errorText = null;
    });
    try {
      await _discovery.startDiscovery();
    } catch (_) {
      if (mounted) {
        final s = AppStrings.of(context);
        setState(() {
          _isScanning = false;
          _errorText = s.autoScanFailedError;
        });
      }
    }
  }

  Future<void> _joinEndpoint(String host, int port) =>
      _joinCandidates([host], port);

  Future<void> _joinCandidates(List<String> hosts, int port) async {
    final s = AppStrings.of(context);
    final guestName = _nameController.text.trim().isEmpty
        ? s.defaultGuestName
        : _nameController.text.trim();
    final primaryLabel = hosts.isNotEmpty ? '${hosts.first}:$port' : ':$port';

    setState(() {
      _isBusy = true;
      _errorText = null;
      _statusText = s.connectingToStatus(primaryLabel);
    });

    try {
      await _cleanupPendingTransport();
      final transport = await LanWebSocketTransport.connectAny(
        hosts: hosts,
        port: port,
      );
      _transport = transport;

      final startCompleter = Completer<MatchStartPacket>();
      _packetSub = transport.incomingPackets.listen((packet) {
        if (packet is MatchStartPacket && !startCompleter.isCompleted) {
          startCompleter.complete(packet);
        }
      });

      await transport.send(HelloPacket(playerName: guestName));

      final startPacket =
          await startCompleter.future.timeout(const Duration(seconds: 6));

      _handedOffToGame = true;
      await _discovery.stopDiscovery();
      await _packetSub?.cancel();
      _packetSub = null;

      ref.read(gameControllerProvider.notifier).startNearbyP2pGame(
            transport: transport,
            isHost: false,
            localStone: startPacket.guestStone,
            hostStonePreference: StonePreference.black,
            rules: startPacket.rules,
            localName: guestName,
            opponentName: startPacket.hostName,
          );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const GameScreen()),
      );
    } catch (_) {
      await _cleanupPendingTransport();
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _statusText = null;
        _errorText = s.joinFailedError(hosts, port);
      });
    }
  }

  Future<void> _cleanupPendingTransport() async {
    await _packetSub?.cancel();
    _packetSub = null;
    final current = _transport;
    _transport = null;
    if (current != null && !_handedOffToGame) {
      await current.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final rules = ref.watch(matchRulesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _role == NearbyRole.host ? s.nearbyHostAppBar : s.nearbyGuestAppBar,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _NetworkTipCard(),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameController,
                    enabled: !_isHosting && !_isBusy,
                    maxLength: 12,
                    decoration: InputDecoration(
                      labelText: s.nicknameLabel,
                      filled: true,
                      fillColor: AppTheme.warmCard,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  if (_errorText != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.forbiddenCrimson.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _errorText!,
                        style: const TextStyle(
                          color: AppTheme.forbiddenCrimson,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (_role == NearbyRole.host)
                    _buildHostView(s, rules)
                  else
                    _buildGuestView(s),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHostView(AppStrings s, MatchRules rules) {
    final transport = _transport;
    final ip = transport?.primaryLocalIp;
    final port = transport?.boundPort;

    if (_isHosting && port != null) {
      final addressText = ip != null ? '$ip:$port' : s.portOnlyLabel(port);
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.warmCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppTheme.accentWood.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            const CircularProgressIndicator(color: AppTheme.accentWood),
            const SizedBox(height: 16),
            Text(
              _statusText ?? s.waitingGuestStatus,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.inkPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              s.hostRulesSummary(rules),
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.inkPrimary.withValues(alpha: 0.68),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.warmSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.directAddressCaption,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.inkPrimary.withValues(alpha: 0.62),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          addressText,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.inkPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (ip != null)
                    IconButton(
                      tooltip: s.copyAddressTooltip,
                      icon: const Icon(Icons.copy_rounded, size: 19),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: addressText));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(s.addressCopiedSnackbar)),
                        );
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _stopHosting,
                child: Text(s.closeRoomButton),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.hostStoneSectionTitle,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            color: AppTheme.inkPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: StonePreference.values.map((pref) {
            final selected = _hostStonePreference == pref;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: pref == StonePreference.values.last ? 0 : 8,
                ),
                child: ChoiceChip(
                  label: SizedBox(
                    width: double.infinity,
                    child: Text(
                      s.stonePreferenceLabel(pref),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  selected: selected,
                  onSelected: (_) =>
                      setState(() => _hostStonePreference = pref),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isBusy ? null : _startHosting,
            icon: const Icon(Icons.wifi_tethering_rounded),
            label: Text(
              _isBusy ? s.openingRoomButton : s.openRoomAndWaitButton,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGuestView(AppStrings s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              s.discoveredRoomsTitle,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppTheme.inkPrimary,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _isBusy ? null : _startScanning,
              icon: _isScanning
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.accentWood,
                      ),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: Text(s.refresh),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_rooms.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.warmCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.accentWood.withValues(alpha: 0.16),
              ),
            ),
            child: Text(
              _statusText ?? s.scanningRoomsHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.inkPrimary.withValues(alpha: 0.65),
              ),
            ),
          )
        else
          ..._rooms.map(
            (room) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.meeting_room_rounded,
                    color: AppTheme.accentWood,
                  ),
                  title: Text(
                    room.roomName,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    s.roomTileSubtitle(
                      ruleType: room.ruleType,
                      turnTimeLimitSeconds: room.turnTimeLimitSeconds,
                      endpoint: room.endpoint,
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: FilledButton(
                    onPressed: _isBusy
                        ? null
                        : () => _joinCandidates(
                              room.resolvedCandidates,
                              room.port,
                            ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Text(s.join),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 20),
        Text(
          s.manualConnectTitle,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            color: AppTheme.inkPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _ipController,
                enabled: !_isBusy,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: s.hostIpFieldLabel,
                  filled: true,
                  fillColor: AppTheme.warmCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _portController,
                enabled: !_isBusy,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: s.portFieldLabel,
                  filled: true,
                  fillColor: AppTheme.warmCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isBusy ? null : _onManualConnect,
            icon: const Icon(Icons.link_rounded),
            label: Text(_isBusy ? s.connectingButton : s.directConnectButton),
          ),
        ),
      ],
    );
  }

  void _onManualConnect() {
    var ip = _ipController.text.trim();
    var port = int.tryParse(_portController.text.trim());

    // Convenience: allow pasting `192.168.0.12:51423` directly into IP field.
    if (ip.contains(':') && port == null) {
      final parts = ip.split(':');
      if (parts.length == 2) {
        ip = parts[0].trim();
        port = int.tryParse(parts[1].trim());
      }
    }

    if (ip.isEmpty || port == null || port <= 0 || port > 65535) {
      final s = AppStrings.of(context);
      setState(() {
        _errorText = s.invalidIpPortError;
      });
      return;
    }

    unawaited(_joinEndpoint(ip, port));
  }
}

class _NetworkTipCard extends StatelessWidget {
  const _NetworkTipCard();

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.warmCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.accentWood.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppTheme.accentWood,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.networkTipText,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppTheme.inkPrimary.withValues(alpha: 0.75),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
