
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

void main() {
  runApp(const TerminalApp());
}

class TerminalApp extends StatelessWidget {
  const TerminalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Lynra Serial Terminal',
      theme: ThemeData.dark(useMaterial3: true),
      home: const TerminalPage(),
    );
  }
}

class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  List<String> _ports = [];
  String? _selectedPort;

  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _subscription;

  final _command = TextEditingController();
  final _scroll = ScrollController();

  String _log = '';

  bool get _connected => _port != null;

  @override
  void initState() {
    super.initState();
    _refreshPorts();
  }

  void _refreshPorts() {
    setState(() {
      _ports = SerialPort.availablePorts;

      if (!_ports.contains(_selectedPort)) {
        _selectedPort = _ports.isNotEmpty ? _ports.first : null;
      }
    });
  }

  void _appendLog(String text) {
    if (!mounted) return;

    setState(() {
      _log += text;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _connect() {
    if (_selectedPort == null || _connected) return;

    final port = SerialPort(_selectedPort!);

    try {
      if (!port.openReadWrite()) {
        throw Exception(SerialPort.lastError);
      }

      final config = port.config;

      try {
        config.baudRate = 115200;
        config.bits = 8;
        config.stopBits = 1;
        config.parity = SerialPortParity.none;
        config.setFlowControl(SerialPortFlowControl.none);

        port.config = config;
      } finally {
        config.dispose();
      }

      _port = port;
      _reader = SerialPortReader(port);

      _subscription = _reader!.stream.listen(
        (data) {
          _appendLog(ascii.decode(data, allowInvalid: true));
        },
        onError: (Object error) {
          _appendLog('\n[RX ERROR] $error\n');
        },
      );

      _appendLog('[CONNECTED] $_selectedPort\n');
    } catch (e) {
      _disconnect();
      if (port.isOpen) port.close();
      port.dispose();
      _appendLog('[ERROR] $e\n');
    }
  }

  void _disconnect({bool silent = false}) {
    _subscription?.cancel();
    _subscription = null;

    _reader?.close();
    _reader = null;

    final port = _port;
    _port = null;

    if (port != null) {
      if (port.isOpen) port.close();
      port.dispose();
    }

    if (!silent) {
      _appendLog('\n[DISCONNECTED]\n');
    }
  }

  void _send() {
    final command = _command.text.trim();

    if (!_connected || command.isEmpty) return;

    try {
      final data = Uint8List.fromList(
        ascii.encode('$command\r\n'),
      );

      final written = _port!.write(data);

      _appendLog('\nTX > $command\n');

      if (written != data.length) {
        _appendLog('[ERROR] Incomplete write\n');
      }

      _command.clear();
    } catch (e) {
      _appendLog('[TX ERROR] $e\n');
    }
  }

  @override
  void dispose() {
    _disconnect(silent: true);
    _command.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lynra Serial Terminal'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                DropdownButton<String>(
                  value: _selectedPort,
                  hint: const Text('COM Port'),
                  items: _ports.map((port) {
                    return DropdownMenuItem(
                      value: port,
                      child: Text(port),
                    );
                  }).toList(),
                  onChanged: _connected
                      ? null
                      : (value) {
                          setState(() {
                            _selectedPort = value;
                          });
                        },
                ),
                IconButton(
                  tooltip: 'Refresh ports',
                  onPressed: _connected ? null : _refreshPorts,
                  icon: const Icon(Icons.refresh),
                ),
                const SizedBox(width: 16),
                const Text('115200 / 8N1'),
                const SizedBox(width: 16),
                FilledButton(
                  onPressed: _connected
                      ? () => _disconnect()
                      : _selectedPort != null
                          ? _connect
                          : null,
                  child: Text(
                    _connected ? 'Disconnect' : 'Connect',
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() => _log = '');
                  },
                  child: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF101418),
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: SelectableText(
                    _log,
                    style: const TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 14,
                      color: Color(0xFF9DE8AE),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _command,
                    enabled: _connected,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Enter command...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _connected ? _send : null,
                  child: const Text('Send'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
