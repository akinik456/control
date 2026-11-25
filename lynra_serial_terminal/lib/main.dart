
import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
  bool _reading = false;
  int _received = 0, _total = 0;
  Uint8List? _verifiedProgram;
  Completer<String>? _reply;
  String _rxLine = '';
  bool get _ready => _connected && !_reading;

  void _receive(Uint8List data) {
    final text = ascii.decode(data, allowInvalid: true);
    _appendLog(text);
    for (final c in text.codeUnits) {
      if (c == 13 || c == 10) {
        final line = _rxLine;
        _rxLine = '';
        final reply = _reply;
        if (reply != null && !reply.isCompleted &&
            (line.startsWith('OK') || line.startsWith('ERR'))) {
          reply.complete(line);
        }
      } else {
        _rxLine += String.fromCharCode(c);
        if (_rxLine.length > 4096) _rxLine = '';
      }
    }
  }

  Future<String> _request(String command) async {
    final reply = Completer<String>();
    _reply = reply;
    try {
      if (!_sendCommand(command, automatic: true)) {
        throw Exception('Send failed');
      }
      final line = await reply.future.timeout(const Duration(seconds: 3));
      if (line.startsWith('ERR')) throw Exception(line);
      return line;
    } finally {
      _reply = null;
    }
  }

  int _crc32(List<int> bytes) {
    var crc = 0xFFFFFFFF;
    for (final b in bytes) {
      crc ^= b;
      for (var i = 0; i < 8; i++) {
        crc = (crc >> 1) ^ ((crc & 1) != 0 ? 0xEDB88320 : 0);
      }
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  Future<void> _readProgram() async {
    if (!_ready) return;
    setState(() {
      _reading = true;
      _received = _total = 0;
      _verifiedProgram = null;
    });
    try {
      final info = await _request('GET PROGRAM INFO');
      final m = RegExp(r'^OK SIZE=([0-9]+) CRC=([0-9A-Fa-f]{8})$').firstMatch(info);
      if (m == null) throw Exception('Invalid program info');
      final size = int.parse(m.group(1)!);
      final crc = int.parse(m.group(2)!, radix: 16);
      if (size <= 0 || size > 32768) throw Exception('Invalid program size');
      if (!mounted) return;
      setState(() => _total = size);
      final bytes = BytesBuilder(copy: false);
      while (bytes.length < size) {
        final offset = bytes.length;
        final line = await _request('GET PROGRAM DATA $offset');
        final chunk = RegExp(r'^OK OFFSET=([0-9]+) COUNT=([0-9]+) DATA=([0-9A-Fa-f]+)$').firstMatch(line);
        if (chunk == null) throw Exception('Invalid program data');
        final count = int.parse(chunk.group(2)!);
        final hex = chunk.group(3)!;
        final expected = size - offset > 200 ? 200 : size - offset;
        if (int.parse(chunk.group(1)!) != offset || count != expected || hex.length != count * 2) {
          throw Exception('Invalid offset or count');
        }
        bytes.add(List<int>.generate(count, (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16)));
        if (!mounted) return;
        setState(() => _received = bytes.length);
      }
      final result = bytes.takeBytes();
      if (result.length != size || _crc32(result) != crc) throw Exception('CRC32 mismatch');
      jsonDecode(utf8.decode(result));
      if (!mounted) return;
      setState(() => _verifiedProgram = result);
      _appendLog('\n[PROGRAM OK] $size bytes, CRC32 verified\n');
    } catch (e) {
      _appendLog('\n[PROGRAM ERROR] $e\n');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _saveProgram() async {
    final bytes = _verifiedProgram;
    if (bytes == null || _reading) return;
    final controller = TextEditingController(text: '${Directory.current.path}${Platform.pathSeparator}lynra_program.json');
    final path = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Save program JSON'),
      content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Full file path')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
      ],
    ));
    // Dispose after the dialog route has finished its closing animation.
    Future<void>.delayed(const Duration(milliseconds: 500), controller.dispose);
    if (path == null || path.isEmpty || !mounted) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        _appendLog('\n[SAVE ERROR] File already exists; choose another path.\n');
        return;
      }
      await file.writeAsBytes(bytes, flush: true);
      _appendLog('\n[SAVED] ${file.path}\n');
    } catch (e) {
      _appendLog('\n[SAVE ERROR] $e\n');
    }
  }


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
          _receive(data);
        },
        onError: (Object error) {
          _appendLog('\n[RX ERROR] $error\n');
          final reply = _reply;
          if (reply != null && !reply.isCompleted) reply.completeError(error);
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
    final reply = _reply;
    if (reply != null && !reply.isCompleted) reply.completeError(StateError('Disconnected'));
    _rxLine = '';
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

  bool _sendCommand(String command, {bool automatic = false}) {

    if (!_connected || command.isEmpty || (_reading && !automatic)) return false;

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
      onPressed: _ready ? () => _sendCommand(command) : null,
      child: Text(label ?? command),
    );
  }

  Widget _number(TextEditingController controller, String label) {
    return SizedBox(
      width: 110,
      child: TextField(
        controller: controller,
        enabled: _ready,
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
      onPressed: _ready
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
          FilledButton(onPressed: _ready ? _readProgram : null, child: const Text('READ PROGRAM')),
          OutlinedButton(onPressed: !_reading && _verifiedProgram != null ? _saveProgram : null, child: const Text('SAVE JSON')),
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
                  onPressed: _reading ? null : _connected
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
            if (_reading || _total > 0) ...[
              LinearProgressIndicator(value: _total == 0 ? null : _received / _total),
              Text('$_received / $_total bytes${_total > 0 ? " (${(_received * 100 / _total).floor()}%)" : ""}'),
              const SizedBox(height: 8),
            ],
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
                    enabled: _ready,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Enter command...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _ready ? _send : null,
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
