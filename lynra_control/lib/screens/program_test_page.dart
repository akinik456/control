import 'dart:async';
import 'package:flutter/material.dart';
import '../models/control_program.dart';
import '../services/lynra_native_engine.dart';
import '../models/control_block.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:ui' show FontFeature;

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
	bool _autoTesting = false;
	int _autoStep = 0;
	int _autoStepStartMs = 0;
	bool _paused = true;
	double _testSpeed = 1.0;
	bool _autoCompleted = false;

  final Map<int, bool> _inputs = {
    for (var i = 1; i <= 4; i++) i: false,
  };

  int _nowMs = 0;
	int _counterMs = 0;
bool _counterRunning = false;
  DateTime? _lastTick;
	
	List<int> get _usedInputs {
  final indexes = <int>{};

  for (final block in widget.program.controlBlocks) {
    for (final rule in block.groups) {
      final conditions = rule.logicOperator == LogicOperator.not
          ? rule.conditions.take(1)
          : rule.conditions;

      for (final condition in conditions) {
        indexes.add(condition.inputIndex);
      }
    }
  }

  return indexes.where((i) => i >= 1 && i <= 4).toList()..sort();
}

List<int> get _usedOutputs {
  final indexes = <int>{};

  for (final block in widget.program.controlBlocks) {
    for (final rule in block.groups) {
      for (final action in rule.actions) {
        if (action.type != ControlActionType.delay) {
          indexes.add(action.outputIndex);
        }
      }
    }
  }

  return indexes.where((i) => i >= 1 && i <= 4).toList()..sort();
}

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
	final wasPaused = _paused;
    _engine?.dispose();
		for (var i = 0; i < _previousOutputs.length; i++) {
			_previousOutputs[i] = false;
		}
    _engine = LynraNativeEngine(widget.program);

    _nowMs = 0;
		_paused = wasPaused;
_autoTesting = false;
_autoStep = 0;
_autoStepStartMs = 0;
_autoCompleted = false;
_counterMs = 0;
    _lastTick = DateTime.now();

    for (var i = 1; i <= 4; i++) {
      _inputs[i] = false;
    }

    _scan();
  }
	
	void _startAutoTest() {
  setState(() {
    _restart();
		_counterMs = 0;
_counterRunning = true;
    _autoTesting = true;
		_paused = false;
		_autoCompleted = false;
    _autoStep = 0;
    _autoStepStartMs = 0;
    _applyAutoStep();
  });
}

void _applyAutoStep() {
  final inputs = _usedInputs;
  final total = 1 << inputs.length;

  if (_autoStep >= total) {
  _autoStep = 0;
}

  for (var i = 1; i <= 4; i++) {
    _inputs[i] = false;
  }

  for (var bit = 0; bit < inputs.length; bit++) {
    _inputs[inputs[bit]] = (_autoStep & (1 << bit)) != 0;
  }

  _scan();
}
int get _autoStepDurationMs {
  var maxDelay = 0;

  for (final block in widget.program.controlBlocks) {
    for (final rule in block.groups) {
      if (rule.onDelayMs > maxDelay) {
        maxDelay = rule.onDelayMs;
      }

      if (rule.offDelayMs > maxDelay) {
        maxDelay = rule.offDelayMs;
      }

      for (final action in rule.actions) {
        if (action.onDelayMs > maxDelay) {
          maxDelay = action.onDelayMs;
        }

        if (action.offDelayMs > maxDelay) {
          maxDelay = action.offDelayMs;
        }
      }
    }
  }

  return maxDelay > 500 ? maxDelay + 500 : 1000;
}
  void _tick() {
    if (!mounted || _engine == null) return;

    final now = DateTime.now();
    final elapsed = now.difference(_lastTick!).inMilliseconds;
    _lastTick = now;

    if (elapsed <= 0) return;

    setState(() {
		if (_counterRunning) {
  _counterMs += (elapsed * _testSpeed).round();
}
      final end = _nowMs + (elapsed * _testSpeed).round();

      while (_nowMs < end) {
        final step = (end - _nowMs).clamp(1, 10);
        _nowMs += step;
        _scan();
      }		
			if (_autoTesting &&
    _nowMs - _autoStepStartMs >= _autoStepDurationMs) {
				_autoStep++;
				_autoStepStartMs = _nowMs;
				_applyAutoStep();
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
	if (_autoTesting) return;
    setState(() {
      _inputs[index] = !_inputs[index]!;
      _scan();
    });
  }
	void _startCounter() {
  setState(() => _counterRunning = true);
}

void _stopCounter() {
  setState(() => _counterRunning = false);
}

void _resetCounter() {
  setState(() => _counterMs = 0);
}
	void _pauseTest() {
  setState(() => _paused = true);
}
void _stopAutoTest() {
  setState(() {
    _autoTesting = false;
    _autoCompleted = false;
  });
}
void _resumeTest() {
  setState(() {
    _lastTick = DateTime.now();
    _paused = false;
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
          
        ],
      ),
      body: Padding(
  padding: const EdgeInsets.all(4),
  child: Column(
    children: [
          Card(
  elevation: 2,
  child: Padding(
    padding: const EdgeInsets.all(4),
    child: Column(
      children: [
        const Text(
          'TEST KONTROL',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          '${(_counterMs / 1000).toStringAsFixed(3)} sn',
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _counterRunning ? null : _startCounter,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Başlat'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _counterRunning ? _stopCounter : null,
                icon: const Icon(Icons.stop),
                label: const Text('Durdur'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _resetCounter,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Sıfırla'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

FilledButton.tonalIcon(
  onPressed: _autoTesting ? _stopAutoTest : _startAutoTest,
  icon: Icon(
    _autoTesting ? Icons.stop : Icons.auto_mode,
  ),
  label: Text(
    _autoTesting ? 'Otomatik Durdur' : 'Otomatik Başlat',
  ),
),

const SizedBox(height: 4),

Row(
  children: [
    const SizedBox(width: 12),
    const Text('Hız'),
    Expanded(
      child: Slider(
        min: 0.25,
        max: 4.0,
        divisions: 15,
        value: _testSpeed,
        onChanged: (value) {
          setState(() => _testSpeed = value);
        },
      ),
    ),
    SizedBox(
      width: 52,
      child: Text(
        '${_testSpeed.toStringAsFixed(2)}×',
        textAlign: TextAlign.center,
      ),
    ),
  ],
),

if (_autoTesting || _autoCompleted) ...[
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: LinearProgressIndicator(
      value: (_autoStep + 1) / (1 << _usedInputs.length),
    ),
  ),
  const SizedBox(height: 4),
  Text(
  'Test ${_autoStep + 1} / ${1 << _usedInputs.length}',
),
],

      ],
    ),
  ),
),
          
Expanded(
  child: ListView(
    children: [
      for (final (index, rule) in [
        for (final block in widget.program.controlBlocks)
          ...block.groups,
      ].indexed)
        _ruleCard(index + 1, rule),
    ],
  ),
),
					
					
        ],
				),
      ),
    );
  }
	
	Widget _ruleCard(int ruleNumber, ControlConditionGroup rule) {
  final inputs = (rule.logicOperator == LogicOperator.not
          ? rule.conditions.take(1)
          : rule.conditions)
      .map((c) => c.inputIndex)
      .where((i) => i >= 1 && i <= 4)
      .toSet()
      .toList()
    ..sort();

  final outputs = rule.actions
      .where((a) => a.type != ControlActionType.delay)
      .map((a) => a.outputIndex)
      .where((i) => i >= 1 && i <= 4)
      .toSet()
      .toList()
    ..sort();

  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      border: Border.all(
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      children: [
        Text(
          'KURAL $ruleNumber',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: [
                  for (final i in inputs) ...[
                    InkWell(
                      onTap: () => _setInput(i),
                      child: _ioCard(
                        'I$i',
                        _inputs[i]!,
                        isInput: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  for (final i in outputs) ...[
                    _ioCard(
                      'Q$i',
                      _engine!.output(i),
                      isInput: false,
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
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
      width: 92,
      padding: const EdgeInsets.all(6),
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
            size: 34,
            color: color,
          ),
          const SizedBox(height: 4),
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