import 'package:flutter/material.dart';

import '../models/control_program.dart';
import '../services/lynra_ble_service.dart';

class BleConnectionPage extends StatefulWidget {
  final ControlProgram? program;

  final bool connectionOnly;

const BleConnectionPage({
  super.key,
  this.program,
  this.connectionOnly = false,
});

  @override
  State<BleConnectionPage> createState() => _BleConnectionPageState();
}

class _BleConnectionPageState extends State<BleConnectionPage> {
  final LynraBleService _ble = LynraBleService();

  @override
  void initState() {
    super.initState();
    _ble.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ble.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = _ble.connecting || _ble.commandBusy || _ble.pendingAck != null;
    final canCommand = _ble.isConnected && !busy;
    return Scaffold(
      appBar: AppBar(title: const Text('LynraControl BLE')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('BLE: ${_ble.status}'),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('PLC: ${_ble.plcStatus}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: FilledButton.icon(
              onPressed: _ble.scanning || busy || _ble.isConnected ? null : _ble.scan,
              icon: const Icon(Icons.bluetooth_searching),
              label: Text(_ble.scanning ? 'Aranıyor...' : 'Cihaz Ara'),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _ble.devices.length,
              itemBuilder: (context, index) {
                final device = _ble.devices[index].device;
                return RadioListTile<String>(
                  title: const Text('LynraControl'),
                  subtitle: Text(device.remoteId.toString()),
                  value: device.remoteId.toString(),
                  groupValue: _ble.selectedDevice?.remoteId.toString(),
                  onChanged: _ble.isConnected || busy
                      ? null
                      : (_) => _ble.selectDevice(device),
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
                  onPressed: busy || (!_ble.isConnected && _ble.selectedDevice == null)
                      ? null
                      : _ble.connectOrDisconnect,
                  child: Text(_ble.connecting
                      ? 'Please wait...'
                      : _ble.isConnected ? 'Disconnect' : 'Connect'),
                ),
								if (!widget.connectionOnly) ...[
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: canCommand && widget.program != null
                      ? () => _ble.sendProgram(widget.program)
                      : null,
                  child: const Text('Send Program'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: canCommand ? () => _ble.sendPlcCommand(0x20) : null,
                        child: const Text('RUN'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: canCommand ? () => _ble.sendPlcCommand(0x21) : null,
                        child: const Text('STOP'),
                      ),
                    ),
										
										
                  ],
                ),
								],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
