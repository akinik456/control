import 'package:flutter/material.dart';
import '../core/control_engine.dart';
import '../models/control_program.dart';

/// Virtual-time simulator: uses the same ControlEngine as the application.
class ProgramSimulatorPage extends StatefulWidget {
  final ControlProgram program;
  const ProgramSimulatorPage({super.key, required this.program});

  @override
  State<ProgramSimulatorPage> createState() => _ProgramSimulatorPageState();
}

class _Sample {
  final int ms;
  final List<bool> inputs;
  final List<bool> outputs;
  const _Sample(this.ms, this.inputs, this.outputs);
}

class _ProgramSimulatorPageState extends State<ProgramSimulatorPage> {
  late ControlEngine _engine;
  final Map<int, bool> _inputs = {for (var i = 1; i <= 4; i++) i: false};
  final List<_Sample> _samples = [];
  int _nowMs = 0;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  void _restart() {
    _engine = ControlEngine(widget.program);
    _nowMs = 0;
    for (var i = 1; i <= 4; i++) _inputs[i] = false;
    _samples.clear();
    _scan();
  }

  void _scan() {
    _engine.scan(nowMs: _nowMs, inputs: _inputs);
    _samples.add(_Sample(
      _nowMs,
      [for (var i = 1; i <= 4; i++) _inputs[i] ?? false],
      [for (var i = 1; i <= 4; i++) _engine.output(i)],
    ));
  }

  void _advance(int durationMs) {
    setState(() {
      final end = _nowMs + durationMs;
      while (_nowMs < end) {
        _nowMs += (end - _nowMs < 100 ? end - _nowMs : 100);
        _scan();
      }
    });
  }

  void _setInput(int index, bool value) {
    setState(() {
      _inputs[index] = value;
      // An input change is evaluated on the next 1 ms scan.
      _nowMs += 1;
      _scan();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Simülasyon'), actions: [
      IconButton(tooltip: 'Baştan başlat', icon: const Icon(Icons.restart_alt),
        onPressed: () => setState(_restart)),
    ]),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Text('Sanal zaman: ${(_nowMs / 1000).toStringAsFixed(3)} sn',
          style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      const Text('Girişler (dokunarak değiştir)'),
      Wrap(spacing: 8, children: [for (var i = 1; i <= 4; i++)
        FilterChip(label: Text('I$i  ${_inputs[i]! ? 'ON' : 'OFF'}'),
          selected: _inputs[i]!, onSelected: (v) => _setInput(i, v)),
      ]),
      const SizedBox(height: 8),
      const Text('Çıkışlar'),
      Wrap(spacing: 8, children: [for (var i = 1; i <= 4; i++)
        Chip(label: Text('Q$i  ${_engine.output(i) ? 'ON' : 'OFF'}'),
          backgroundColor: _engine.output(i)
              ? Colors.green.withValues(alpha: .2) : null),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton(onPressed: () => _advance(100), child: const Text('+0.1 sn')),
        OutlinedButton(onPressed: () => _advance(1000), child: const Text('+1 sn')),
        FilledButton(onPressed: () => _advance(5000), child: const Text('+5 sn')),
        OutlinedButton(onPressed: () => setState(_restart), child: const Text('Sıfırla')),
      ]),
      const SizedBox(height: 18),
      Text('Zaman diyagramı', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      SizedBox(height: 330, child: CustomPaint(
        painter: _TimingPainter(_samples, Theme.of(context).colorScheme.onSurface),
        child: const SizedBox.expand(),
      )),
      const Text('Yeşil: girişler  •  Mavi: çıkışlar  •  Renkli kesikli çizgiler: durum değişimleri.',
        style: TextStyle(fontSize: 12)),
    ]),
  );
}

class _TimingPainter extends CustomPainter {
  final List<_Sample> samples;
  final Color ink;
  _TimingPainter(this.samples, this.ink);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 38.0;
    const right = 12.0;
    const top = 12.0;
    const lane = 37.0;
    final width = (size.width - left - right).clamp(1.0, double.infinity);
    final maxMs = samples.isEmpty ? 1000 : (samples.last.ms < 1000 ? 1000 : samples.last.ms);
    final axis = Paint()..color = ink.withValues(alpha: .18)..strokeWidth = 1;
    for (var i = 0; i < 8; i++) {
      final y = top + i * lane;
      canvas.drawLine(Offset(left, y + 24), Offset(left + width, y + 24), axis);
      final label = TextPainter(
        text: TextSpan(text: '${i < 4 ? 'I' : 'Q'}${i % 4 + 1}',
          style: TextStyle(fontSize: 12, color: ink)),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(5, y + 5));
      if (samples.isEmpty) continue;
      final signal = Paint()
        ..color = i < 4 ? Colors.green : Colors.blue
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke;
      final path = Path();
      bool state(_Sample s) => i < 4 ? s.inputs[i] : s.outputs[i - 4];
      double x(_Sample s) => left + width * s.ms / maxMs;
      double level(bool on) => y + (on ? 4 : 22);
      path.moveTo(x(samples.first), level(state(samples.first)));
      for (var j = 1; j < samples.length; j++) {
        final s = samples[j];
        path.lineTo(x(s), level(state(samples[j - 1])));
        path.lineTo(x(s), level(state(s)));
      }
      path.lineTo(left + width, level(state(samples.last)));
      canvas.drawPath(path, signal);
    }
    // Her sinyal değişimi için tüm kanalları kesen renkli kesikli çizgi.
    const eventColors = <Color>[
      Colors.green, Colors.teal, Colors.lightGreen, Colors.lime,
      Colors.blue, Colors.cyan, Colors.indigo, Colors.purple,
    ];
    bool channelState(_Sample sample, int channel) => channel < 4
        ? sample.inputs[channel]
        : sample.outputs[channel - 4];
    final bottom = top + 7 * lane + 24;
    for (var j = 1; j < samples.length; j++) {
      final previous = samples[j - 1];
      final current = samples[j];
      for (var channel = 0; channel < 8; channel++) {
        if (channelState(previous, channel) == channelState(current, channel)) {
          continue;
        }
        final eventX = left + width * current.ms / maxMs;
        final eventPaint = Paint()
          ..color = eventColors[channel].withValues(alpha: .75)
          ..strokeWidth = 1.2;
        for (var y = top; y < bottom; y += 7) {
          canvas.drawLine(
            Offset(eventX, y),
            Offset(eventX, (y + 3).clamp(top, bottom)),
            eventPaint,
          );
        }
      }
    }
    final footer = TextPainter(
      text: TextSpan(text: '0 sn                                     ${(maxMs / 1000).toStringAsFixed(1)} sn',
        style: TextStyle(fontSize: 10, color: ink)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: size.width);
    footer.paint(canvas, Offset(left, top + 8 * lane));
  }

  @override
  bool shouldRepaint(covariant _TimingPainter oldDelegate) => true;
}
