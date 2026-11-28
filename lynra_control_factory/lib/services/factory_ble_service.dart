import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class FactoryBleService extends ChangeNotifier {
  static const String serviceUuid =
      '8d21a100-64c2-4c3a-9d1e-123456789abc';

  static const String writeUuid =
      '8d21a101-64c2-4c3a-9d1e-123456789abc';

  static const String notifyUuid =
      '8d21a102-64c2-4c3a-9d1e-123456789abc';

  int _nextSeq = 1;
bool scanning = false;
bool connecting = false;
bool isConnected = false;
StreamSubscription<List<int>>? _notifySubscription;

StreamSubscription<BluetoothConnectionState>?
    _connectionSubscription;

Completer<List<int>>? _pendingResponse;

int? _pendingSeq;
int? _pendingType;
String status = 'Disconnected';

final List<ScanResult> devices = [];

BluetoothDevice? selectedDevice;
BluetoothDevice? connectedDevice;
BluetoothCharacteristic? connectedRx;

Future<void> scan() async {
  if (scanning || connecting || isConnected) return;

  scanning = true;
  devices.clear();
  selectedDevice = null;
  status = 'Scanning...';

  notifyListeners();

  final subscription =
      FlutterBluePlus.scanResults.listen((results) {
    devices
      ..clear()
      ..addAll(results.where((r) =>
          r.advertisementData.advName == 'LynraControl' ||
          r.device.platformName == 'LynraControl'));

    notifyListeners();
  });

  try {
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 8),
    );

    await FlutterBluePlus.isScanning
        .where((v) => !v)
        .first;

    status = '${devices.length} device(s) found';
  } catch (e) {
    status = 'Scan error: $e';
  } finally {
    await subscription.cancel();

    scanning = false;
    notifyListeners();
  }
}

void selectDevice(BluetoothDevice device) {
  selectedDevice = device;
  notifyListeners();
}
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

  List<int> buildFrame(
      int type, int seq, List<int> payload) {

    final frame = List<int>.filled(
        27 + payload.length, 0);

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

    final crc = calculateCRC32(
        frame.sublist(2, 23 + payload.length));

    final offset = 23 + payload.length;

    for (int i = 0; i < 4; i++) {
      frame[offset + i] = (crc >> (8 * i)) & 0xFF;
    }

    return frame;
  }

  bool verifyFrame(List<int> data) {
    if (data.length < 27 ||
        data[0] != 0x4C ||
        data[1] != 0x43 ||
        data[2] != 1 ||
        data[3] != 23) {
      return false;
    }

    final length = data[21] | (data[22] << 8);

    if (data.length != 27 + length) {
      return false;
    }

    final offset = data.length - 4;

    final receivedCRC =
        data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);

    return receivedCRC ==
        calculateCRC32(data.sublist(2, offset));
  }
	
void handleNotification(List<int> data) {
  if (!verifyFrame(data)) return;

  final type = data[16];

  final seq = data[17] |
      (data[18] << 8) |
      (data[19] << 16) |
      (data[20] << 24);

  final response = _pendingResponse;

  if (seq == _pendingSeq &&
      type == _pendingType &&
      response != null &&
      !response.isCompleted) {

    response.complete(
      data.sublist(23, data.length - 4),
    );
  }
}	
Future<List<int>> request(
  int type,
  int responseType,
  List<int> payload,
) async {
  final rx = connectedRx;

  if (rx == null || _pendingResponse != null) {
    throw StateError('BLE not ready');
  }

  final seq = _nextSeq++;
  final response = Completer<List<int>>();

  _pendingSeq = seq;
  _pendingType = responseType;
  _pendingResponse = response;

  try {
    await rx.write(buildFrame(type, seq, payload));

    return await response.future.timeout(
      const Duration(seconds: 3),
    );
  } finally {
    _pendingSeq = null;
    _pendingType = null;
    _pendingResponse = null;
  }
}	
Future<void> connect() async {
  final device = selectedDevice;

  if (device == null ||
      scanning ||
      connecting ||
      isConnected ||
      _disposed) return;

  connecting = true;
  status = 'Connecting...';
  notifyListeners();

  try {
    connectedDevice = device;

    await device.connect(
      license: License.free,
      timeout: const Duration(seconds: 10),
    );

    if (Platform.isAndroid) {
      await device.requestMtu(247);
    }

    final services = await device.discoverServices();

    final service = services.firstWhere(
      (s) => s.uuid.toString() == serviceUuid,
    );

    connectedRx = service.characteristics.firstWhere(
      (c) => c.uuid.toString() == writeUuid,
    );

    final tx = service.characteristics.firstWhere(
      (c) => c.uuid.toString() == notifyUuid,
    );

    await _notifySubscription?.cancel();

    _notifySubscription =
        tx.onValueReceived.listen(handleNotification);

    await tx.setNotifyValue(true);

    _nextSeq = 1;

    await request(0x01, 0x02, []);

    await _connectionSubscription?.cancel();

    _connectionSubscription =
        device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        connectedDevice = null;
        connectedRx = null;
        isConnected = false;
        status = 'Disconnected';
        notifyListeners();
      }
    });

    if (_disposed || !device.isConnected) {
      throw StateError('Connection closed');
    }

    isConnected = true;
    status = 'Connected - HELLO OK';

  } catch (e) {
    await _notifySubscription?.cancel();
    await _connectionSubscription?.cancel();

    try {
      await device.disconnect();
    } catch (_) {}

    connectedDevice = null;
    connectedRx = null;
    isConnected = false;
    status = 'Connection error: $e';

  } finally {
    connecting = false;
    notifyListeners();
  }
}
Future<void> disconnect() async {
  final device = connectedDevice;

  if (device == null ||
      connecting ||
      _pendingResponse != null) return;

  connecting = true;
  notifyListeners();

  try {
    await device.disconnect();
  } catch (e) {
    status = 'Disconnect error: $e';
  } finally {
    await _notifySubscription?.cancel();
    await _connectionSubscription?.cancel();

    _notifySubscription = null;
    _connectionSubscription = null;

    connectedDevice = null;
    connectedRx = null;

    isConnected = false;
    connecting = false;

    status = 'Disconnected';

    notifyListeners();
  }
}
	bool _disposed = false;

@override
void notifyListeners() {
  if (!_disposed) {
    super.notifyListeners();
  }
}
Future<String> readDeviceId() async {
  if (!isConnected) {
    throw StateError('Cihaz bağlı değil.');
  }

  final data = await request(0x62, 0x63, []);

  if (data.length != 6) {
    throw const FormatException('Geçersiz cihaz kimliği.');
  }

  return data
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}
Future<bool> readWifiLicense() async {
  if (!isConnected) {
    throw StateError('Cihaz bağlı değil.');
  }

  final data = await request(0x64, 0x65, []);

  if (data.length != 1 || data[0] > 1) {
    throw const FormatException('Geçersiz lisans durumu.');
  }

  return data[0] == 1;
}
Future<bool> activateWifiLicense(String code) async {
  if (!isConnected) {
    throw StateError('Cihaz bağlı değil.');
  }

  if (!RegExp(r'^[A-Za-z0-9_-]{86}$').hasMatch(code)) {
    throw const FormatException('Geçersiz aktivasyon kodu.');
  }

  final data = await request(
    0x66,
    0x67,
    code.codeUnits,
  );

  if (data.length != 1 || data[0] > 1) {
    throw const FormatException('Geçersiz aktivasyon cevabı.');
  }

  return data[0] == 1;
}
@override
void dispose() {
  _disposed = true;

  if (scanning) {
    unawaited(FlutterBluePlus.stopScan());
  }

  _notifySubscription?.cancel();
  _connectionSubscription?.cancel();
  connectedDevice?.disconnect();

  super.dispose();
}
}