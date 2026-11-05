import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/control_program.dart';

class BleConnectionPage extends StatefulWidget {
  final ControlProgram? program;

  const BleConnectionPage({super.key, this.program});

  @override
  State<BleConnectionPage> createState() => _BleConnectionPageState();
}

class _BleConnectionPageState extends State<BleConnectionPage> {
  static const String serviceUuid = '8d21a100-64c2-4c3a-9d1e-123456789abc';
  static const String writeUuid = '8d21a101-64c2-4c3a-9d1e-123456789abc';
  static const String notifyUuid = '8d21a102-64c2-4c3a-9d1e-123456789abc';

  bool scanning = false;
  bool connecting = false;
  bool commandBusy = false;
  bool isConnected = false;
  final List<ScanResult> devices = [];
  BluetoothDevice? selectedDevice;
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? connectedRx;
  StreamSubscription<List<int>>? notifySubscription;
  StreamSubscription<BluetoothConnectionState>? connectionSubscription;
  Completer<void>? pendingAck;
  int? pendingSeq;
  int nextSeq = 1;
  int? pendingStatusSeq;
  Completer<int>? pendingStatus;
  String status = 'Disconnected';
  String plcStatus = 'Unknown';

  int calculateCRC32(List<int> data) {
    int crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= byte;
      for (int i = 0; i < 8; i++) {
        crc = (crc & 1) != 0
            ? (crc >> 1) ^ 0xEDB88320
            : crc >> 1;
      }
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  List<int> buildFrame(int type, int seq, List<int> payload) {
    if (payload.length > 65535) {
      throw ArgumentError('Payload too large');
    }
    final frame = List<int>.filled(27 + payload.length, 0);
    frame[0] = 0x4C;
    frame[1] = 0x43;
    frame[2] = 1;
    frame[3] = 23;
    frame[16] = type;
    for (int i = 0; i < 4; i++) {
      frame[17 + i] = (seq >> (8 * i)) & 0xFF;
    }
    frame[21] = payload.length & 0xFF;
    frame[22] = (payload.length >> 8) & 0xFF;
    frame.setRange(23, 23 + payload.length, payload);
    final crc = calculateCRC32(frame.sublist(2, 23 + payload.length));
    final offset = 23 + payload.length;
    for (int i = 0; i < 4; i++) {
      frame[offset + i] = (crc >> (8 * i)) & 0xFF;
    }
    return frame;
  }

  void handleNotification(List<int> value) {
    if (value.length < 27 ||
        value[0] != 0x4C ||
        value[1] != 0x43 ||
        value[2] != 1 ||
        value[3] != 23) {
      debugPrint('BLE RX: INVALID FRAME');
      return;
    }
    final payloadLength = value[21] | (value[22] << 8);
    if (value.length != 27 + payloadLength) {
      debugPrint('BLE RX: INVALID LENGTH');
      return;
    }
    final receivedCRC = value[value.length - 4] |
        (value[value.length - 3] << 8) |
        (value[value.length - 2] << 16) |
        (value[value.length - 1] << 24);
    final calculatedCRC = calculateCRC32(value.sublist(2, value.length - 4));
    if (receivedCRC != calculatedCRC) {
      debugPrint('BLE RX: CRC ERROR');
      return;
    }
    final type = value[16];
    final seq = value[17] |
        (value[18] << 8) |
        (value[19] << 16) |
        (value[20] << 24);
    if (type == 0x30) {
      if (payloadLength != 1) {
        debugPrint('BLE RX: INVALID STATUS LENGTH');
        return;
      }
      final state = switch (value[23]) {
        0 => 'STOP',
        1 => 'PROGRAMMING',
        2 => 'RUN',
        _ => 'Unknown',
      };
      if (seq == pendingStatusSeq && pendingStatus != null &&
          !pendingStatus!.isCompleted) {
        pendingStatus!.complete(value[23]);
      }
      debugPrint('PLC STATUS: $state');
      if (mounted) setState(() => plcStatus = state);
      return;
    }
    if (type == 2) {
      debugPrint('BLE RX: ACK SEQ=$seq CRC=OK');
      if (seq == pendingSeq &&
          pendingAck != null &&
          !pendingAck!.isCompleted) {
        pendingAck!.complete();
      }
    } else {
      debugPrint('BLE RX: TYPE=$type SEQ=$seq CRC=OK');
    }
  }

  Future<bool> sendWithAck(
    BluetoothCharacteristic rx,
    List<int> frame,
    int seq,
  ) async {
    if (pendingAck != null) return false;
    final ack = Completer<void>();
    pendingSeq = seq;
    pendingAck = ack;
    try {
      for (int attempt = 1; attempt <= 3; attempt++) {
        if (ack.isCompleted) return true;
        await rx.write(frame);
        debugPrint('PHONE TX: SEQ=$seq ATTEMPT=$attempt');
        try {
          await ack.future.timeout(const Duration(seconds: 2));
          debugPrint('ACK CONFIRMED SEQ=$seq');
          return true;
        } on TimeoutException {
          debugPrint('ACK TIMEOUT SEQ=$seq ATTEMPT=$attempt');
        }
      }
      debugPrint('MESSAGE FAILED SEQ=$seq');
      return false;
    } finally {
      pendingAck = null;
      pendingSeq = null;
    }
  }

  Future<void> scan() async {
    if (scanning || connecting || isConnected) return;
    final permissions = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    if (permissions.values.any((p) => !p.isGranted)) {
      debugPrint('BLE permission denied');
      return;
    }
    if (!mounted) return;
    setState(() {
      scanning = true;
      devices.clear();
      selectedDevice = null;
    });
    final subscription = FlutterBluePlus.scanResults.listen((results) {
      if (!mounted) return;
      setState(() {
        devices
          ..clear()
          ..addAll(results.where((r) =>
              r.advertisementData.advName == 'LynraControl' ||
              r.device.platformName == 'LynraControl'));
      });
    });
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
      await FlutterBluePlus.isScanning.where((v) => !v).first;
    } catch (e) {
      debugPrint('BLE scan error: $e');
    } finally {
      await subscription.cancel();
      if (mounted) setState(() => scanning = false);
    }
  }

  Future<void> connectOrDisconnect() async {
    if (connecting || commandBusy) return;
    if (isConnected) {
      await disconnect();
    } else {
      final device = selectedDevice;
      if (device != null) await connect(device);
    }
  }

  Future<void> connect(BluetoothDevice device) async {
    if (connecting || isConnected) return;
    setState(() {
      connecting = true;
      status = 'Connecting...';
      plcStatus = 'Unknown';
    });
    try {
      await device.connect(
        license: License.free,
        timeout: const Duration(seconds: 10),
      );
      debugPrint('ESP32 CONNECTED');
      final mtu = await device.requestMtu(247);
      debugPrint('BLE MTU: $mtu');
      final services = await device.discoverServices();
      final service = services.firstWhere((s) => s.uuid.toString() == serviceUuid);
      final rx = service.characteristics.firstWhere((c) => c.uuid.toString() == writeUuid);
      final tx = service.characteristics.firstWhere((c) => c.uuid.toString() == notifyUuid);

      await notifySubscription?.cancel();
      notifySubscription = tx.onValueReceived.listen(handleNotification);
      await tx.setNotifyValue(true);
      nextSeq = 1;
      final seq = nextSeq++;
      final helloOk = await sendWithAck(rx, buildFrame(1, seq, []), seq);
      if (!helloOk) throw StateError('HELLO ACK not received');
      // Request the current PLC state after subscribing to notifications.
      final statusSeq = nextSeq++;
      final statusOk = await sendWithAck(
        rx, buildFrame(0x31, statusSeq, []), statusSeq);
      if (!statusOk) debugPrint('PLC STATUS REQUEST FAILED');

      await connectionSubscription?.cancel();
      connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected &&
            connectedDevice?.remoteId == device.remoteId) {
          debugPrint('ESP32 DISCONNECTED');
          connectedDevice = null;
          connectedRx = null;
          isConnected = false;
          pendingAck = null;
          pendingSeq = null;
          if (mounted) setState(() {
            status = 'Disconnected';
            plcStatus = 'Unknown';
          });
        }
      });

      if (!mounted) {
        await device.disconnect();
        return;
      }
      setState(() {
        connectedDevice = device;
        connectedRx = rx;
        isConnected = true;
        status = 'Connected';
      });
    } catch (e) {
      debugPrint('BLE connection error: $e');
      try {
        await device.disconnect();
      } catch (_) {}
      if (mounted) {
        setState(() {
          connectedDevice = null;
          connectedRx = null;
          isConnected = false;
          status = 'Connection failed';
          plcStatus = 'Unknown';
        });
      }
    } finally {
      if (mounted) setState(() => connecting = false);
    }
  }

  Future<void> disconnect() async {
    final device = connectedDevice;
    if (device == null || connecting || commandBusy) return;
    setState(() => connecting = true);
    try {
      await device.disconnect();
    } catch (e) {
      debugPrint('BLE disconnect error: $e');
    } finally {
      await notifySubscription?.cancel();
      notifySubscription = null;
      await connectionSubscription?.cancel();
      connectionSubscription = null;
      connectedDevice = null;
      connectedRx = null;
      isConnected = false;
      pendingAck = null;
      pendingSeq = null;
      if (mounted) {
        setState(() {
          connecting = false;
          status = 'Disconnected';
          plcStatus = 'Unknown';
        });
      }
    }
  }

  Future<void> sendPlcCommand(int type) async {
    final rx = connectedRx;
    if (!isConnected || rx == null || commandBusy || pendingAck != null) return;
    setState(() => commandBusy = true);
    try {
      final seq = nextSeq++;
      final ok = await sendWithAck(rx, buildFrame(type, seq, []), seq);
      debugPrint('PLC ${type == 0x20 ? 'RUN' : 'STOP'}: ${ok ? 'ACK' : 'FAILED'}');
    } catch (e) {
      debugPrint('PLC COMMAND ERROR: $e');
    } finally {
      if (mounted) setState(() => commandBusy = false);
    }
  }

  Future<void> sendProgram() async {
    final rx = connectedRx;
    final program = widget.program;
    if (!isConnected || rx == null || program == null ||
        commandBusy || pendingAck != null) return;
    setState(() => commandBusy = true);
    try {
      final programBytes = utf8.encode(jsonEncode(program.toJson()));
      debugPrint('REAL PROGRAM SIZE: ${programBytes.length} bytes');
      if (programBytes.isEmpty || programBytes.length > 32768) {
        debugPrint('PROGRAM SIZE INVALID');
        return;
      }
      final programCRC = calculateCRC32(programBytes);
      final beginPayload = <int>[
        for (int i = 0; i < 4; i++) (programBytes.length >> (8 * i)) & 0xFF,
        for (int i = 0; i < 4; i++) (programCRC >> (8 * i)) & 0xFF,
      ];
      var seq = nextSeq++;
      if (!await sendWithAck(rx, buildFrame(0x10, seq, beginPayload), seq)) return;
      for (int offset = 0; offset < programBytes.length; offset += 200) {
        final end = offset + 200 < programBytes.length
            ? offset + 200
            : programBytes.length;
        seq = nextSeq++;
        final chunk = programBytes.sublist(offset, end);
        if (!await sendWithAck(rx, buildFrame(0x11, seq, chunk), seq)) return;
      }
      seq = nextSeq++;
      final endSeq = seq;
      final statusResult = Completer<int>();
      pendingStatusSeq = endSeq;
      pendingStatus = statusResult;
      try {
        final ok = await sendWithAck(rx, buildFrame(0x12, endSeq, []), endSeq);
        if (!ok) {
          debugPrint('PROGRAM END: ACK NOT RECEIVED - RESULT UNKNOWN');
          return;
        }
        // ACK confirms frame reception, not successful program activation.
        final result = await statusResult.future.timeout(const Duration(seconds: 3));
        if (result == 2) {
          debugPrint('PROGRAM LOAD SUCCESS: PLC RUN');
        } else {
          debugPrint('PROGRAM LOAD FAILED: PLC STATUS=$result');
        }
      } on TimeoutException {
        debugPrint('PROGRAM END: STATUS TIMEOUT - RESULT UNKNOWN');
      } finally {
        pendingStatusSeq = null;
        pendingStatus = null;
      }
    } catch (e) {
      debugPrint('PROGRAM SEND ERROR: $e');
    } finally {
      if (mounted) setState(() => commandBusy = false);
    }
  }

  @override
  void dispose() {
    notifySubscription?.cancel();
    connectionSubscription?.cancel();
    connectedDevice?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = connecting || commandBusy || pendingAck != null;
    final canCommand = isConnected && !busy;
    return Scaffold(
      appBar: AppBar(title: const Text('LynraControl BLE')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('BLE: $status'),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('PLC: $plcStatus',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: FilledButton.icon(
              onPressed: scanning || busy || isConnected ? null : scan,
              icon: const Icon(Icons.bluetooth_searching),
              label: Text(scanning ? 'Aranıyor...' : 'Cihaz Ara'),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final device = devices[index].device;
                return RadioListTile<String>(
                  title: const Text('LynraControl'),
                  subtitle: Text(device.remoteId.toString()),
                  value: device.remoteId.toString(),
                  groupValue: selectedDevice?.remoteId.toString(),
                  onChanged: isConnected || busy
                      ? null
                      : (_) => setState(() => selectedDevice = device),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  onPressed: busy || (!isConnected && selectedDevice == null)
                      ? null
                      : connectOrDisconnect,
                  child: Text(connecting
                      ? 'Please wait...'
                      : isConnected ? 'Disconnect' : 'Connect'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: canCommand && widget.program != null
                      ? sendProgram
                      : null,
                  child: const Text('Send Program'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: canCommand ? () => sendPlcCommand(0x20) : null,
                        child: const Text('RUN'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: canCommand ? () => sendPlcCommand(0x21) : null,
                        child: const Text('STOP'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
