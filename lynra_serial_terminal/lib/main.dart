
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
  final _rule = TextEditingController(text: '1');
  final _action = TextEditingController(text: '1');
  final _cursor = TextEditingController(text: '0');
  final _offset = TextEditingController(text: '0');

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
    if (_sendCommand(command)) _command.clear();
  }

  bool _sendCommand(String command) {

    if (!_connected || command.isEmpty) return false;

    try {
      final data = Uint8List.fromList(
        ascii.encode('$command\r\n'),
      );

      final written = _port!.write(data);

      _appendLog('\nTX > $command\n');

      if (written != data.length) {
        _appendLog('[ERROR] Incomplete write\n');
        return false;
      }
      return true;
    } catch (e) {
      _appendLog('[TX ERROR] $e\n');
      return false;
    }
  }

  @override
  void dispose() {
    _disconnect(silent: true);
    _command.dispose();
    _scroll.dispose();
    _rule.dispose();
    _action.dispose();
    _cursor.dispose();
    _offset.dispose();
    super.dispose();
  }

  Widget _quick(String command, {String? label}) {
    return OutlinedButton(
      onPressed: _connected ? () => _sendCommand(command) : null,
      child: Text(label ?? command),
    );
  }

  Widget _number(TextEditingController controller, String label) {
    return SizedBox(
      width: 110,
      child: TextField(
        controller: controller,
        enabled: _connected,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, isDense: true,
          border: const OutlineInputBorder()),
      ),
    );
  }

  void _parameterCommand(String prefix, List<TextEditingController> fields,
      int min, int max) {
    final values = <int>[];
    for (final field in fields) {
      final raw = field.text.trim();
      final value = int.tryParse(raw);
      if (!RegExp(r'^[0-9]+$').hasMatch(raw) ||
          value == null || value < min || value > max) {
        _appendLog('\n[ERROR] Invalid parameter ($min–$max)\n');
        return;
      }
      values.add(value);
    }
    _sendCommand('$prefix ${values.join(' ')}');
  }

  Widget _parameterButton(String label, List<TextEditingController> fields,
      int min, int max) {
    return OutlinedButton(
      onPressed: _connected
          ? () => _parameterCommand(label, fields, min, max) : null,
      child: Text(label),
    );
  }

  Widget _quickPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final cmd in ['GET INFO', 'GET STATE', 'GET IO', 'GET RULES',
            'GET ACTION ALL', 'GET PROGRAM INFO', 'RUN', 'STOP',
            'MANUAL ON', 'MANUAL OFF']) _quick(cmd),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 4, children: [
          for (var i = 1; i <= 4; i++)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text('I$i  '),
              _quick('SET I$i 1', label: 'ON'),
              const SizedBox(width: 4),
              _quick('SET I$i 0', label: 'OFF'),
            ]),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 16, runSpacing: 8, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            _number(_rule, 'Rule'), const SizedBox(width: 4),
            _number(_action, 'Action'), const SizedBox(width: 4),
            _parameterButton('GET ACTION', [_rule, _action], 1, 256),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            _number(_cursor, 'Cursor'), const SizedBox(width: 4),
            _parameterButton('GET EVENTS', [_cursor], 0, 4294967295),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            _number(_offset, 'Offset'), const SizedBox(width: 4),
            _parameterButton('GET PROGRAM DATA', [_offset], 0, 4294967295),
          ]),
        ]),
      ],
    );
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
            Flexible(
              flex: 1,
              child: SingleChildScrollView(child: _quickPanel()),
            ),
            const SizedBox(height: 12),
            Expanded(
              flex: 2,
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
