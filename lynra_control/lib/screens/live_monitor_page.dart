import 'dart:async';
import 'package:flutter/material.dart';
import '../services/lynra_ble_service.dart';
import '../models/control_program.dart';
import '../models/control_block.dart';

class LiveMonitorPage extends StatefulWidget {
  const LiveMonitorPage({super.key});

  @override
  State<LiveMonitorPage> createState() => _LiveMonitorPageState();
}

class _LiveMonitorPageState extends State<LiveMonitorPage> {
  final LynraBleService _ble = LynraBleService();

  ControlProgram? _deviceProgram;
  String? _readError;
  bool _readStarted = false;

  Future<void> _readDeviceProgram() async {
    try {
      final program = await _ble.readProgram();
      if (mounted && _ble.isConnected) setState(() => _deviceProgram = program);
    } catch (e) {
      if (mounted && _ble.isConnected) setState(() => _readError = e.toString());
    }
  }

  int _actionCursor = 0;
  bool _polling = false;
  List<(int, int)> get _actionKeys {
    final keys = <(int, int)>[];
    var ri = 0;
    for (final block in _deviceProgram?.controlBlocks ?? []) {
      for (final rule in block.groups) {
        for (var ai = 0; ai < rule.actions.length; ai++) {
          keys.add((ri, ai));
        }
        ri++;
      }
    }
    return keys;
  }

  Future<void> _poll() async {
    if (_polling || !_ble.isConnected || _ble.connecting || _ble.commandBusy) return;
    _polling = true;
    try {
      final keys = _actionKeys;
      final key = keys.isEmpty ? null : keys[_actionCursor++ % keys.length];
      await _ble.requestIo(action: key);
    } finally {
      _polling = false;
    }
  }

  String _seconds(int ms) => '${(ms / 1000).toStringAsFixed(3)} sn';

  String _hours(int ms) => '${ms ~/ 3600000}sa ${(ms % 3600000) ~/ 60000}dk ${(ms % 60000) ~/ 1000}sn';

  String _functionName(ControlAction a) => switch (a.type) {
    ControlActionType.setOutput => a.outputState ? 'ON' : 'OFF',
    ControlActionType.setLatch => 'SET',
    ControlActionType.resetLatch => 'RESET',
    ControlActionType.toggleOutput => 'TOGGLE',
    ControlActionType.onDelay => 'Açma Gecikmesi',
    ControlActionType.offDelay => 'Kapanma Gecikmesi',
    ControlActionType.onOffDelay => 'Açma / Kapanma Gecikmesi',
    ControlActionType.wipingRelay => 'Darbe Rölesi',
    ControlActionType.edgeWipingRelay => 'Kenar Tetiklemeli Darbe Rölesi',
    ControlActionType.asynchronousPulse => 'Asenkron Darbe Üreteci',
    ControlActionType.randomGenerator => 'Rastgele Üreteç',
    ControlActionType.stairwayTimer => 'Merdiven Otomatiği',
    ControlActionType.multipleFunctionTimer => 'Çok İşlevli Anahtar',
    ControlActionType.stopwatchTimer => 'Kronometre',
    ControlActionType.upDownCounter => 'İleri / Geri Sayıcı',
    ControlActionType.hoursCounter => 'Çalışma Saati Sayacı',
    ControlActionType.thresholdTrigger => 'Frekans Eşik Tetikleyici',
    _ => 'Eski fonksiyon (${a.type.name})',
  };

  List<String> _parameters(ControlConditionGroup rule, ControlAction a) {
    final edge = rule.conditions.length == 1 &&
        (rule.conditions.first.trigger == ConditionTrigger.risingEdge ||
         rule.conditions.first.trigger == ConditionTrigger.fallingEdge);
    final th = 'TH: ${_seconds(a.timerTHMs)}';
    final tl = 'TL: ${_seconds(a.timerTLMs)}';
    final t = 'T: ${_seconds(a.timerTMs)}';
    final reset = 'RESET: ${a.resetInputIndex == 0 ? "YOK" : "I${a.resetInputIndex}"}';
    final warning = ['T!: ${_seconds(a.timerWarningBeforeMs)}', 'T!L: ${_seconds(a.timerWarningOffMs)}'];
    return switch (a.type) {
      ControlActionType.onOffDelay => [th, edge ? 'TA: ${_seconds(a.timerTLMs)}' : tl, reset],
      ControlActionType.wipingRelay => [t],
      ControlActionType.edgeWipingRelay => [th, tl, 'N: ${a.timerN}', if (a.timerTHRandom) 'TH rastgele', if (a.timerTLRandom) 'TL rastgele'],
      ControlActionType.asynchronousPulse || ControlActionType.randomGenerator => [th, tl],
      ControlActionType.stairwayTimer => [t, ...warning],
      ControlActionType.multipleFunctionTimer => [t, tl, ...warning],
      ControlActionType.stopwatchTimer => [t, reset],
      ControlActionType.upDownCounter => ['Sayma: I${a.counterInputIndex}', 'Yön: I${a.directionInputIndex}', reset, 'Başlangıç: ${a.counterStartValue}', 'ON: ${a.counterOn}', 'OFF: ${a.counterOff}'],
      ControlActionType.hoursCounter => ['Etkinleştir: I${a.hoursEnableInputIndex}', reset, 'Hedef: ${_hours(a.hoursTargetMs)}'],
      ControlActionType.thresholdTrigger => ['Giriş: I${a.thresholdInputIndex}', 'G_T: ${_seconds(a.thresholdGateMs)}', 'ON: ${a.thresholdOn}', 'OFF: ${a.thresholdOff}'],
      _ => [],
    };
  }

  Widget _functionValues((int, int) key, ControlAction action) {
    final values = _ble.actionValues[key];
    if (values == null) return Text(_ble.actionErrors[key] ?? 'Değer bekleniyor...');
    final theme = Theme.of(context);
    String format(int id, int value) {
      final seconds = _seconds(value);
      return switch (id) {
        7 => 'CV: $value',
        9 => 'Geçen süre: $seconds',
        14 => 'Darbe: $value',
        31 => switch (value) {0 => 'Bekliyor', 1 => 'Çalışıyor', 2 => 'Tamamlandı', _ => 'Durum: $value'},
        32 => 'CV: ${_hours(value)}',
        33 => 'Toplam: ${_hours(value)}',
        34 => 'Son ölçüm: $value darbe${action.thresholdGateMs > 0 ? " • ${(value * 1000 / action.thresholdGateMs).toStringAsFixed(2)} Hz" : ""}',
        35 => 'Çıkış: ${value == 0 ? "OFF" : "ON"}',
        36 => 'Kalan süre: $seconds',
        37 => 'Rastgele bekleme: ${value == 0 ? "OFF" : "ON"}',
        38 => 'Sürekli ON: ${value == 0 ? "OFF" : "ON"}',
        _ => 'Alan $id: $value',
      };
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 16, runSpacing: 4, children: [
        for (final e in values.entries)
          if (e.key != 31 && e.key != 35)
            Text(format(e.key, e.value), style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 4),
      Wrap(spacing: 12, runSpacing: 4, children: [
        if (values.containsKey(31)) Text(format(31, values[31]!)),
        if (values.containsKey(35)) Text(format(35, values[35]!), style: TextStyle(color: values[35] != 0 ? Colors.green : null, fontWeight: FontWeight.bold)),
      ]),
    ]);
  }

  List<Widget> _functions() {
    final widgets = <Widget>[];
    var ri = 0;
    for (final block in _deviceProgram!.controlBlocks) {
      for (final rule in block.groups) {
        for (var ai = 0; ai < rule.actions.length; ai++) {
          final action = rule.actions[ai];
          final params = _parameters(rule, action);
          widgets.add(Card(
            margin: const EdgeInsets.symmetric(vertical: 5),
            child: Padding(padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Q${action.outputIndex} • ${_functionName(action)}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                Text('Kural ${ri + 1} / Fonksiyon ${ai + 1}', style: Theme.of(context).textTheme.bodySmall),
                if (params.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 12, runSpacing: 4, children: [for (final p in params) Text(p, style: Theme.of(context).textTheme.bodySmall)]),
                ],
                const Divider(height: 16),
                _functionValues((ri, ai), action),
              ]),
            ),
          ));
        }
        ri++;
      }
    }
    return widgets;
  }

  Timer? _ioTimer;
  int? _startMs;
  int? _lastMs;
  final _changeTimes = List.generate(8, (_) => <int>[]);
  int _processedEvents = 0;
  int _seenLossCount = 0;
  ({int ms, int inputs, int outputs})? _previousEvent;

  void _resetChangeTimes() {
    for (final times in _changeTimes) {
      times.clear();
    }
    _processedEvents = 0;
    _seenLossCount = _ble.eventLossCount;
    _previousEvent = null;
  }

  void _updateChangeTimes() {
    final start = _startMs;
    if (start == null) return;
    final events = _ble.ioEvents;
    final count = _ble.eventCount;
    if (_seenLossCount != _ble.eventLossCount || count < _processedEvents) {
      _resetChangeTimes();
    }
    final first = count - events.length;
    if (_processedEvents < first) {
      _previousEvent = null;
      _processedEvents = first;
    }
    for (var index = _processedEvents - first; index < events.length; index++) {
      final event = events[index];
      final previous = _previousEvent;
      if (previous != null && event.ms >= start) {
        final changedInputs = previous.inputs ^ event.inputs;
        final changedOutputs = previous.outputs ^ event.outputs;
        for (var channel = 0; channel < 8; channel++) {
          final changed = channel < 4 ? changedInputs : changedOutputs;
          if ((changed & (1 << (channel % 4))) == 0) continue;
          final times = _changeTimes[channel];
          times.insert(0, event.ms - start);
          if (times.length > 5) times.removeLast();
        }
      }
      _previousEvent = event;
    }
    _processedEvents = count;
  }

  String get _elapsed {
    if (_startMs == null || _lastMs == null) return "—";
    return "${((_lastMs! - _startMs!) / 1000).toStringAsFixed(3)} sn";
  }

  @override
  void initState() {
    super.initState();
    _ble.addListener(_refresh);
    _ioTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      unawaited(_poll());
    });
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      final ms = _ble.deviceTimeMs;
      if (!_ble.isConnected) {
        _deviceProgram = null;
        _readError = null;
        _readStarted = false;
        _actionCursor = 0;
        _startMs = null;
        _lastMs = null;
        _resetChangeTimes();
      } else if (ms != null) {
        if (_startMs == null || (_lastMs != null && ms < _lastMs!)) {
          _startMs = ms;
          _resetChangeTimes();
        }
        _lastMs = ms;
        _updateChangeTimes();
      } else {
        _lastMs = null;
      }
    });
    if (_ble.isConnected && !_ble.connecting && !_ble.commandBusy && !_readStarted) {
      _readStarted = true;
      unawaited(_readDeviceProgram());
    }
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 1; i <= 4; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Flexible(flex: 1, child: GestureDetector(
              onTap: prefix == 'I' && _ble.manualMode == true && mask != null &&
                  !_ble.commandBusy && !_ble.connecting && _ble.pendingAck == null
                  ? () => _ble.setManualInput(i - 1, (mask & (1 << (i-1))) == 0)
                  : null,
              child: Chip(
              label: Text('$prefix$i  ${mask == null ? '—' : (mask & (1 << (i-1))) != 0 ? 'ON' : 'OFF'}'),
              backgroundColor: mask != null && (mask & (1 << (i-1))) != 0
                  ? (prefix == 'I' ? Colors.green : Colors.blue).withValues(alpha: .25)
                  : null,
            ))),
            const SizedBox(width: 6),
            Expanded(flex: 2, child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var j = 0; j < 5; j++)
                  Builder(builder: (context) {
                    final times = _changeTimes[(prefix == 'I' ? 0 : 4) + i - 1];
                    return Row(children: [
                      Expanded(child: Text(
                        j + 1 < times.length
                            ? ((times[j] - times[j + 1]) / 1000).toStringAsFixed(3)
                            : ' ',
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        style: const TextStyle(fontSize: 11, height: 1.15,
                          color: Colors.amber),
                      )),
                      const SizedBox(width: 4),
                      Expanded(child: Text(
                        j < times.length
                            ? (times[j] / 1000).toStringAsFixed(3)
                            : ' ',
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        style: TextStyle(fontSize: 11, height: 1.15,
                          color: j == 0 ? Theme.of(context).colorScheme.primary : null),
                      )),
                    ]);
                  }),
              ],
            )),
          ]),
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
        Row(children: [
          Expanded(flex: 2, child: OutlinedButton(
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
            onPressed: busy || _ble.scanning || (!_ble.isConnected && _ble.selectedDevice == null)
                ? null : _ble.connectOrDisconnect,
            child: Text(_ble.connecting ? 'Bekleyin...' : _ble.isConnected ? 'Bağlantıyı Kes' : 'Bağlan'),
          )),
          const SizedBox(width: 8),
          Expanded(child: FilledButton(
            onPressed: canCommand ? () => _ble.sendPlcCommand(0x20) : null,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 2)),
            child: const Text('RUN'),
          )),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(
            onPressed: canCommand ? () => _ble.sendPlcCommand(0x21) : null,
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 2)),
            child: const Text('STOP'),
          )),
          const SizedBox(width: 4),
          Expanded(child: OutlinedButton(
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 2)),
            onPressed: canCommand ? () async {
              final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
                title: const Text('RESET'),
                content: const Text('Cihaz yeniden başlayacak, BLE bağlantısı kopacak ve kayıtlı program fiziksel girişlerle otomatik çalışacak. Röle çıkışları değişebilir.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('RESET')),
                ],
              ));
              if (!mounted || confirmed != true) return;
              await _ble.restartDevice();
            } : null,
            child: const Text('RESET'),
          )),
        ]),
        const Divider(height: 28),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Fiziksel Girişler')),
            ButtonSegment(value: true, label: Text('Manuel Girişler')),
          ],
          emptySelectionAllowed: true,
          selected: _ble.manualMode == null ? <bool>{} : {_ble.manualMode!},
          onSelectionChanged: canCommand && _ble.manualMode != null ? (selection) async {
            if (selection.isEmpty) return;
            final manual = selection.first;
            if (manual) {
              final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
                title: const Text('Manuel Girişler'),
                content: const Text('Gerçek röle çıkışları değişebilir. BLE bağlantısı koparsa fiziksel girişlere otomatik dönülür. Yalnızca güvenli test ortamında kullanın.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Devam')),
                ],
              ));
              if (!mounted || confirmed != true) return;
            }
            await _ble.setManualMode(manual);
          } : null,
        ),
        const SizedBox(height: 8),
        Text('İzleme süresi: $_elapsed', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Girişler', style: theme.textTheme.titleMedium),
            _signals('I'),
          ])),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Çıkışlar', style: theme.textTheme.titleMedium),
            _signals('Q'),
          ])),
        ]),
        const Divider(height: 28),
        Text('Fonksiyonlar', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_deviceProgram != null) ...[
          Text('Program: ${_deviceProgram!.name}'),
          ..._functions(),
        ] else Text(_readError ?? (_ble.isConnected ? 'Program okunuyor...' : 'Program bilgisi henüz alınmadı.')),
        if (_readError != null && canCommand)
          TextButton(onPressed: () { setState(() => _readError = null); unawaited(_readDeviceProgram()); }, child: const Text('Tekrar oku')),
        const Divider(height: 28),
        Text('Olay kaydı: ${_ble.eventCount}  •  Taşma: ${_ble.eventLossCount}'),
        Text('Zaman diyagramı', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SizedBox(height: 330, child: CustomPaint(
          painter: _LiveTimingPainter(
            ink: theme.colorScheme.onSurface,
            nowMs: _ble.isConnected ? _lastMs : null,
            startMs: _startMs,
            events: List.of(_ble.ioEvents),
            lossCount: _ble.eventLossCount,
          ),
          child: const SizedBox.expand(),
        )),
        Text(!_ble.isConnected ? 'İzlemek için cihaza bağlanın.' :
          _ble.eventLossCount > 0 ? 'Veri kaybı oluştu. Yalnızca eldeki kayıtlar çiziliyor.' :
          'Son 10 sn • Yeşil: girişler • Mavi: çıkışlar',
          style: theme.textTheme.bodySmall),
      ]),
    );
  }
}

class _LiveTimingPainter extends CustomPainter {
  final Color ink;
  final int? nowMs;
  final int? startMs;
  final List<({int ms, int inputs, int outputs})> events;
  final int lossCount;

  _LiveTimingPainter({required this.ink, required this.nowMs,
    required this.startMs, required this.events, required this.lossCount});

  @override
  void paint(Canvas canvas, Size size) {
    const left = 38.0, top = 12.0, lane = 37.0;
    final width = size.width - left - 12;
    if (width <= 0) return;
    final end = nowMs;
    final begin = (end ?? 0) - 10000;
    double x(int ms) => left + width * (ms - begin) / 10000;
    final axis = Paint()..color = ink.withValues(alpha: .18)..strokeWidth = 1;
    void label(String value, double px, double py, {double font = 12}) {
      final tp = TextPainter(text: TextSpan(text: value,
        style: TextStyle(fontSize: font, color: ink)),
        textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(px, py));
    }
    for (var i = 0; i <= 10; i++) {
      final px = left + width * i / 10;
      canvas.drawLine(Offset(px, top), Offset(px, top + 7 * lane + 24), axis);
    }
    label('-10 sn', left, 309, font: 10);
    label('-5 sn', left + width / 2 - 12, 309, font: 10);
    label('0', left + width - 6, 309, font: 10);
    for (var i = 0; i < 8; i++) {
      final y = top + i * lane;
      canvas.drawLine(Offset(left, y + 24), Offset(left + width, y + 24), axis);
      label('${i < 4 ? 'I' : 'Q'}${i % 4 + 1}', 5, y + 5);
    }
    if (end == null || startMs == null || events.isEmpty) return;
    final visibleStart = begin > startMs! ? begin : startMs!;
    if (visibleStart > end) return;
    final samples = events.where((e) => e.ms <= end).toList();
    if (samples.isEmpty) return;
    var first = 0;
    while (first + 1 < samples.length && samples[first + 1].ms < visibleStart) {
      first++;
    }
    final drawStart = samples[first].ms > visibleStart ? samples[first].ms : visibleStart;
    bool state(({int ms, int inputs, int outputs}) e, int channel) =>
      ((channel < 4 ? e.inputs : e.outputs) & (1 << (channel % 4))) != 0;
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(left, top, left + width, top + 7 * lane + 25));
    const colors = <Color>[Colors.green, Colors.teal, Colors.lightGreen, Colors.lime,
      Colors.blue, Colors.cyan, Colors.indigo, Colors.purple];
    for (var j = first + 1; j < samples.length; j++) {
      final e = samples[j];
      if (e.ms < visibleStart) continue;
      for (var i = 0; i < 8; i++) {
        if (state(samples[j - 1], i) == state(e, i)) continue;
        final paint = Paint()..color = colors[i].withValues(alpha: .55)..strokeWidth = 1;
        for (double y = top; y < top + 7 * lane + 24; y += 7) {
          canvas.drawLine(Offset(x(e.ms), y), Offset(x(e.ms), y + 3), paint);
        }
      }
    }
    for (var i = 0; i < 8; i++) {
      final y = top + i * lane;
      double level(bool on) => y + (on ? 4 : 22);
      var previous = state(samples[first], i);
      final path = Path()..moveTo(x(drawStart), level(previous));
      for (var j = first + 1; j < samples.length; j++) {
        final e = samples[j];
        final next = state(e, i);
        if (next == previous) continue;
        path.lineTo(x(e.ms), level(previous));
        path.lineTo(x(e.ms), level(next));
        previous = next;
      }
      path.lineTo(x(end), level(previous));
      canvas.drawPath(path, Paint()..color = (i < 4 ? Colors.green : Colors.blue)
        ..strokeWidth = 2.2..style = PaintingStyle.stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LiveTimingPainter oldDelegate) => true;
}
