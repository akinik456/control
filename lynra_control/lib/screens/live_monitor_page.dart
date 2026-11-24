import 'dart:async';
import 'package:flutter/material.dart';
import '../services/lynra_ble_service.dart';

class LiveMonitorPage extends StatefulWidget {
  const LiveMonitorPage({super.key});

  @override
  State<LiveMonitorPage> createState() => _LiveMonitorPageState();
}

class _LiveMonitorPageState extends State<LiveMonitorPage> {
  final LynraBleService _ble = LynraBleService();

  Timer? _ioTimer;

  @override
  void initState() {
    super.initState();
    _ble.addListener(_refresh);
    _ioTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      unawaited(_ble.requestIo());
    });
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ioTimer?.cancel();
    _ble.removeListener(_refresh);
    _ble.dispose();
    super.dispose();
  }

  Widget _signals(String prefix) {
    final mask = !_ble.isConnected ? null :
        (prefix == 'I' ? _ble.inputMask : _ble.outputMask);
    return Wrap(spacing: 8, runSpacing: 4, children: [
      for (var i = 1; i <= 4; i++)
        Chip(
          label: Text('$prefix$i  ${mask == null ? '—' : (mask & (1 << (i-1))) != 0 ? 'ON' : 'OFF'}'),
          backgroundColor: mask != null && (mask & (1 << (i-1))) != 0
              ? (prefix == 'I' ? Colors.green : Colors.blue).withValues(alpha: .25)
              : null,
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final busy = _ble.connecting || _ble.commandBusy || _ble.pendingAck != null;
    final canCommand = _ble.isConnected && !busy;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Canlı İzle')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          const Icon(Icons.bluetooth),
          const SizedBox(width: 8),
          Expanded(child: Text('BLE: ${_ble.status}')),
          Text(_ble.isConnected ? _ble.plcStatus : '—',
            style: theme.textTheme.titleMedium?.copyWith(
              color: _ble.isConnected && _ble.plcStatus == 'RUN' ? Colors.green : null)),
        ]),
        if (!_ble.isConnected) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _ble.scanning || busy ? null : _ble.scan,
            icon: const Icon(Icons.bluetooth_searching),
            label: Text(_ble.scanning ? 'Aranıyor...' : 'Cihaz Ara'),
          ),
          for (final result in _ble.devices)
            RadioListTile<String>(
              title: const Text('LynraControl'),
              subtitle: Text(result.device.remoteId.toString()),
              value: result.device.remoteId.toString(),
              groupValue: _ble.selectedDevice?.remoteId.toString(),
              onChanged: busy ? null : (_) => _ble.selectDevice(result.device),
            ),
        ] else ...[
          const SizedBox(height: 8),
          Text('LynraControl — ${_ble.connectedDevice?.remoteId ?? ""}'),
        ],
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: busy || _ble.scanning || (!_ble.isConnected && _ble.selectedDevice == null)
              ? null : _ble.connectOrDisconnect,
          child: Text(_ble.connecting ? 'Bekleyin...' : _ble.isConnected ? 'Bağlantıyı Kes' : 'Bağlan'),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: FilledButton(
            onPressed: canCommand ? () => _ble.sendPlcCommand(0x20) : null,
            child: const Text('RUN'),
          )),
          const SizedBox(width: 12),
          Expanded(child: OutlinedButton(
            onPressed: canCommand ? () => _ble.sendPlcCommand(0x21) : null,
            child: const Text('STOP'),
          )),
        ]),
        const Divider(height: 28),
        Text('Girişler', style: theme.textTheme.titleMedium),
        _signals('I'),
        const SizedBox(height: 8),
        Text('Çıkışlar', style: theme.textTheme.titleMedium),
        _signals('Q'),
        const Divider(height: 28),
        Text('Fonksiyonlar', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text('Program bilgisi henüz alınmadı.'),
        const Divider(height: 28),
        Text('Zaman diyagramı', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SizedBox(height: 330, child: CustomPaint(
          painter: _EmptyTimingPainter(theme.colorScheme.onSurface),
          child: const SizedBox.expand(),
        )),
        Text(_ble.isConnected ? 'Zaman diyagramı henüz etkin değil.' : 'İzlemek için cihaza bağlanın.',
          style: theme.textTheme.bodySmall),
      ]),
    );
  }
}

class _EmptyTimingPainter extends CustomPainter {
  final Color ink;
  _EmptyTimingPainter(this.ink);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 38.0;
    final axis = Paint()..color = ink.withValues(alpha: .18)..strokeWidth = 1;
    for (var i = 0; i < 8; i++) {
      final y = 12.0 + i * 37;
      canvas.drawLine(Offset(left, y + 24), Offset(size.width - 12, y + 24), axis);
      final label = TextPainter(
        text: TextSpan(text: '${i < 4 ? 'I' : 'Q'}${i % 4 + 1}',
          style: TextStyle(fontSize: 12, color: ink)),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(5, y + 5));
    }
  }

  @override
  bool shouldRepaint(covariant _EmptyTimingPainter oldDelegate) => oldDelegate.ink != ink;
}
