
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'dart:async';

class BleConnectionPage extends StatefulWidget {
  const BleConnectionPage({super.key});

  @override
  State<BleConnectionPage> createState() => _BleConnectionPageState();
}

class _BleConnectionPageState extends State<BleConnectionPage> {
  bool scanning = false;
  final List<ScanResult> devices = [];
	Completer<void>? pendingAck;
	int? pendingSeq;
	StreamSubscription<List<int>>? notifySubscription;
	
	int calculateCRC32(List<int> data) {
		int crc = 0xFFFFFFFF;

		for (final byte in data) {
			crc ^= byte;

			for (int i = 0; i < 8; i++) {
				if ((crc & 1) != 0) {
					crc = (crc >> 1) ^ 0xEDB88320;
				} else {
					crc >>= 1;
				}
			}
		}

		return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
	}

List<int> buildFrame(
  int type,
  int seq,
  List<int> payload,
) {
  if (payload.length > 65535) {
    throw ArgumentError('Payload too large');
  }

  final frame = List<int>.filled(27 + payload.length, 0);

  frame[0] = 0x4C; // SOF
  frame[1] = 0x43;
  frame[2] = 1;    // VERSION
  frame[3] = 23;   // HEADER_LEN

  frame[16] = type;

  // SEQ: 32-bit little-endian
  for (int i = 0; i < 4; i++) {
    frame[17 + i] = (seq >> (8 * i)) & 0xFF;
  }

  // PAYLOAD LENGTH: 16-bit little-endian
  frame[21] = payload.length & 0xFF;
  frame[22] = (payload.length >> 8) & 0xFF;

  // Payload
  frame.setRange(23, 23 + payload.length, payload);

  // CRC32
  final crc = calculateCRC32(
    frame.sublist(2, 23 + payload.length),
  );

  final offset = 23 + payload.length;

  for (int i = 0; i < 4; i++) {
    frame[offset + i] = (crc >> (8 * i)) & 0xFF;
  }

  return frame;
}

	@override
	void dispose() {
		notifySubscription?.cancel();
		super.dispose();
	}
	
	
Future<bool> sendWithAck(
  BluetoothCharacteristic rx,
  List<int> frame,
  int seq,
) async {
  pendingSeq = seq;
  final ack = Completer<void>();
  pendingAck = ack;

  try {
    for (int attempt = 1; attempt <= 3; attempt++) {
      if (ack.isCompleted) return true;

      await rx.write(frame);

      debugPrint('PHONE TX: SEQ=$seq ATTEMPT=$attempt');

      try {
        await ack.future.timeout(
          const Duration(seconds: 2),
        );

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
    final permissions = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    if (permissions.values.any((p) => !p.isGranted)) {
      debugPrint('BLE permission denied');
      return;
    }

    devices.clear();
    setState(() => scanning = true);

    final subscription = FlutterBluePlus.scanResults.listen((results) {
      if (!mounted) return;

      setState(() {
        devices.clear();
        devices.addAll(results.where(
          (r) => r.advertisementData.advName == 'LynraControl' ||
                 r.device.platformName == 'LynraControl',
        ));
      });
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 8),
      );
      await FlutterBluePlus.isScanning.where((v) => !v).first;
    } catch (e) {
      debugPrint('BLE scan error: $e');
    } finally {
      await subscription.cancel();
      if (mounted) setState(() => scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BLE Cihazları')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: scanning ? null : scan,
              icon: const Icon(Icons.bluetooth_searching),
              label: Text(scanning ? 'Aranıyor...' : 'Cihazları Ara'),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final result = devices[index];
                return ListTile(
                  leading: const Icon(Icons.bluetooth),
                  title: const Text('LynraControl'),
                  subtitle: Text(result.device.remoteId.toString()),
									onTap: () async {
										try {
											await result.device.connect(
												license: License.free,
												timeout: const Duration(seconds: 10),
											);
											debugPrint('ESP32 CONNECTED');
											
											final mtu = await result.device.requestMtu(247);
											debugPrint('BLE MTU: $mtu');
											
											final services = await result.device.discoverServices();

											final service = services.firstWhere(
												(s) => s.uuid.toString() ==
														'8d21a100-64c2-4c3a-9d1e-123456789abc',
											);

											final rx = service.characteristics.firstWhere(
												(c) => c.uuid.toString() ==
														'8d21a101-64c2-4c3a-9d1e-123456789abc',
											);

											final tx = service.characteristics.firstWhere(
												(c) => c.uuid.toString() ==
														'8d21a102-64c2-4c3a-9d1e-123456789abc',
											);

											
											await notifySubscription?.cancel();

											notifySubscription = tx.onValueReceived.listen((value) {
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

												final receivedCRC =
														value[value.length - 4] |
														(value[value.length - 3] << 8) |
														(value[value.length - 2] << 16) |
														(value[value.length - 1] << 24);

												final calculatedCRC =
														calculateCRC32(value.sublist(2, value.length - 4));

												if (receivedCRC != calculatedCRC) {
													debugPrint('BLE RX: CRC ERROR');
													return;
												}

												final type = value[16];

												final seq =
														value[17] |
														(value[18] << 8) |
														(value[19] << 16) |
														(value[20] << 24);

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
											});


											await tx.setNotifyValue(true);

											
										final frame = List<int>.filled(27, 0);

										frame[0] = 0x4C; // SOF L
										frame[1] = 0x43; // SOF C
										frame[2] = 1;    // VERSION
										frame[3] = 23;   // HEADER_LEN

										// TYPE = 1 (HELLO), offset 16
										frame[16] = 1;

										// SEQ = 1, little-endian, offset 17
										frame[17] = 1;

										// LEN = 0, offset 21

										final crc = calculateCRC32(frame.sublist(2, 23));

										frame[23] = crc & 0xFF;
										frame[24] = (crc >> 8) & 0xFF;
										frame[25] = (crc >> 16) & 0xFF;
										frame[26] = (crc >> 24) & 0xFF;

										
										final helloOk = await sendWithAck(rx, frame, 1);
										if (!helloOk) return;
										
										
										
final testBytes = List<int>.generate(
  1000,
  (i) => 65 + (i % 26),
);

final programCRC = calculateCRC32(testBytes);

final beginPayload = <int>[
  0xE8, 0x03, 0x00, 0x00,
  programCRC & 0xFF,
  (programCRC >> 8) & 0xFF,
  (programCRC >> 16) & 0xFF,
  (programCRC >> 24) & 0xFF,
];

final begin = buildFrame(0x10, 2, beginPayload);

final beginOk = await sendWithAck(rx, begin, 2);
if (!beginOk) return;									
										



int seq = 3;

for (int offset = 0; offset < testBytes.length; offset += 200) {
  final end = (offset + 200 < testBytes.length)
      ? offset + 200
      : testBytes.length;

  final chunk = testBytes.sublist(offset, end);

  final dataFrame = buildFrame(0x11, seq, chunk);

  final dataOk = await sendWithAck(rx, dataFrame, seq);
  if (!dataOk) return;

  seq++;
}



										
final endFrame = buildFrame(0x12, seq, []);
final endOk = await sendWithAck(rx, endFrame, seq);
if (!endOk) return;




										} catch (e) {
											debugPrint('BLE connection error: $e');
										}
									},
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
