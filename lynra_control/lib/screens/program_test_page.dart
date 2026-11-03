import 'dart:async';
import 'package:flutter/material.dart';
import '../models/control_program.dart';
import '../services/lynra_native_engine.dart';
import 'package:audioplayers/audioplayers.dart';

class ProgramTestPage extends StatefulWidget {
  final ControlProgram program;

  const ProgramTestPage({super.key, required this.program});

  @override
  State<ProgramTestPage> createState() => _ProgramTestPageState();
}

class _ProgramTestPageState extends State<ProgramTestPage> {
  LynraNativeEngine? _engine;
  Timer? _timer;
	final AudioPlayer _relayPlayer = AudioPlayer();
	final List<bool> _previousOutputs = List.filled(4, false);
	bool _soundEnabled = true;

  final Map<int, bool> _inputs = {
    for (var i = 1; i <= 4; i++) i: false,
  };

  int _nowMs = 0;
  DateTime? _lastTick;

  @override
  void initState() {
    super.initState();
    _restart();
    _timer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _tick(),
    );
  }

  void _restart() {
    _engine?.dispose();
		for (var i = 0; i < _previousOutputs.length; i++) {
			_previousOutputs[i] = false;
		}
    _engine = LynraNativeEngine(widget.program);

    _nowMs = 0;
    _lastTick = DateTime.now();

    for (var i = 1; i <= 4; i++) {
      _inputs[i] = false;
    }

    _scan();
  }

  void _tick() {
    if (!mounted || _engine == null) return;

    final now = DateTime.now();
    final elapsed = now.difference(_lastTick!).inMilliseconds;
    _lastTick = now;

    if (elapsed <= 0) return;

    setState(() {
      final end = _nowMs + elapsed;

      while (_nowMs < end) {
        final step = (end - _nowMs).clamp(1, 10);
        _nowMs += step;
        _scan();
      }		
			
    });
  }
void _scan() {
  _engine!.scan(nowMs: _nowMs, inputs: _inputs);

  bool? relayState;

  for (var i = 1; i <= 4; i++) {
    final current = _engine!.output(i);

    if (current != _previousOutputs[i - 1]) {
      relayState = current;
    }

    _previousOutputs[i - 1] = current;
  }

  if (relayState != null && _soundEnabled) {
    final sound = relayState
        ? 'sounds/relay_click.wav'
        : 'sounds/relay_release.wav';

    _relayPlayer.stop().then((_) {
      if (mounted && _soundEnabled) {
        return _relayPlayer.play(AssetSource(sound));
      }
    });
  }
}
  void _setInput(int index) {
    setState(() {
      _inputs[index] = !_inputs[index]!;
      _nowMs += 1;
      _scan();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _engine?.dispose();
    super.dispose();
		_relayPlayer.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Program Testi'),
        actions: [
					IconButton(
						tooltip: _soundEnabled ? 'Sesi kapat' : 'Sesi aç',
						icon: Icon(
							_soundEnabled ? Icons.volume_up : Icons.volume_off,
						),
						onPressed: () {
							setState(() => _soundEnabled = !_soundEnabled);
						},
					),
          IconButton(
            tooltip: 'Sıfırla',
            icon: const Icon(Icons.restart_alt),
            onPressed: () => setState(_restart),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Çalışma süresi: ${(_nowMs / 1000).toStringAsFixed(1)} sn',
          ),
          const SizedBox(height: 24),

          Text(
            'GİRİŞLER',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),

          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var i = 1; i <= 4; i++)
                InkWell(
                  onTap: () => _setInput(i),
                  child: _ioCard(
                    'I$i',
                    _inputs[i]!,
                    isInput: true,
                  ),
                ),
            ],
          ),

          const SizedBox(height: 32),

          Text(
            'ÇIKIŞLAR',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),

          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var i = 1; i <= 4; i++)
                _ioCard(
                  'Q$i',
                  _engine!.output(i),
                  isInput: false,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ioCard(
    String label,
    bool active, {
    required bool isInput,
  }) {
    final color = isInput
        ? (active ? Colors.green : Colors.grey)
        : (active ? Colors.amber : Colors.red);

    return Container(
      width: 110,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(
            isInput
                ? (active ? Icons.toggle_on : Icons.toggle_off)
                : Icons.lightbulb,
            size: 42,
            color: color,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(active ? 'ON' : 'OFF'),
        ],
      ),
    );
  }
}