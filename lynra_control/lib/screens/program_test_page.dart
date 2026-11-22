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
  // Keep the latest five transition timestamps for each physical I/O.
  final Map<int, List<int>> _inputChangeMs = {};
  final Map<int, List<int>> _outputChangeMs = {};

  void _recordChange(Map<int, List<int>> history, int index) {
    final ticks = history.putIfAbsent(index, () => <int>[]);
    ticks.insert(0, _counterMs);
    if (ticks.length > 5) ticks.removeLast();
  }
	bool _soundEnabled = true;
	bool _autoTesting = false;
  bool _autoPaused = false;
  int _autoPauseAtMs = 0;
	int _autoStep = 0;
	int _autoStepStartMs = 0;
	double _testSpeed = 1.0;
	bool _autoCompleted = false;

  final Map<int, bool> _inputs = {
    for (var i = 1; i <= 4; i++) i: false,
  };

  int _nowMs = 0;
	int _counterMs = 0;
bool _counterRunning = false;
  DateTime? _lastTick;
	
  // Collect every physical input referenced by a rule, including
  // auxiliary timer/counter inputs that are not part of EGER conditions.
  Map<int, Set<String>> _ruleInputRoles(ControlConditionGroup rule) {
    final roles = <int, Set<String>>{};

    void add(int index, String role) {
      if (index < 1 || index > 4) return;
      roles.putIfAbsent(index, () => <String>{}).add(role);
    }

    final conditions = rule.conditionGroups.isNotEmpty
        ? rule.conditionGroups.expand((group) => group.conditions)
        : rule.conditions;
    for (final condition in conditions) {
      add(condition.inputIndex, '');
    }

    for (final action in rule.actions) {
      switch (action.type) {
        case ControlActionType.upDownCounter:
          add(action.counterInputIndex, 'Cnt');
          add(action.directionInputIndex, 'Dir');
          add(action.resetInputIndex, 'RESET');
          break;
        case ControlActionType.hoursCounter:
          add(action.hoursEnableInputIndex, 'EN');
          add(action.resetInputIndex, 'RESET');
          add(action.hoursResetAllInputIndex, 'Ral');
          break;
        case ControlActionType.thresholdTrigger:
          add(action.thresholdInputIndex, 'Fre');
          break;
        default:
          // Timer RESET inputs (including stopwatch) are optional for
          // some timer types; index 0 means no external input.
          if (ControlAction.timerTypes.contains(action.type)) {
            add(action.resetInputIndex, 'RESET');
          }
      }
    }
    return roles;
  }

  List<int> get _usedInputs {
    final indexes = <int>{};
    for (final block in widget.program.controlBlocks) {
      for (final rule in block.groups) {
        indexes.addAll(_ruleInputRoles(rule).keys);
      }
    }
    return indexes.toList()..sort();
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

  // Reset the engine and I/O without changing the independent stopwatch.
  void _resetSimulation({bool restartAuto = false}) {
    _engine?.dispose();
    for (var i = 0; i < _previousOutputs.length; i++) {
      _previousOutputs[i] = false;
    }
    _engine = LynraNativeEngine(widget.program);
    _nowMs = 0;
    _inputChangeMs.clear();
    _outputChangeMs.clear();
    _autoTesting = restartAuto;
    _autoPaused = false;
    _autoPauseAtMs = 0;
    _autoStep = 0;
    _autoStepStartMs = 0;
    _autoCompleted = false;
    _lastTick = DateTime.now();
    for (var i = 1; i <= 4; i++) {
      _inputs[i] = false;
    }
    _scan();
    if (restartAuto) _applyAutoStep();
  }

  void _restart() {
    _resetSimulation();
    _counterMs = 0;
    _counterRunning = false;
  }

  void _startAutoTest() {
    setState(() {
      _resetSimulation(restartAuto: true);
      _counterMs = 0;
      _counterRunning = true;
    });
  }

  // Restart the sweep from step one if active, and reset the stopwatch.
  // Preserve the stopwatch running/stopped state when using refresh.
  void _resetSimulationButton() {
    setState(() {
      _resetSimulation(restartAuto: _autoTesting);
      _counterMs = 0;
    });
  }

// Insert an all-OFF interval between combinations so edge triggers
// can be exercised again. This is an input sweep, not a PASS/FAIL test.
List<int> get _autoMasks {
  final inputs = _usedInputs;
  final masks = <int>[0];
  for (var combination = 1; combination < (1 << inputs.length); combination++) {
    var mask = 0;
    for (var bit = 0; bit < inputs.length; bit++) {
      if ((combination & (1 << bit)) != 0) mask |= 1 << (inputs[bit] - 1);
    }
    masks.add(mask);
    masks.add(0);
  }
  return masks;
}

void _applyAutoStep() {
  final mask = _autoMasks[_autoStep];
  for (var i = 1; i <= 4; i++) {
    final next = (mask & (1 << (i - 1))) != 0;
    if (_inputs[i] != next) _recordChange(_inputChangeMs, i);
    _inputs[i] = next;
  }
  _scan();
}

int get _autoStepDurationMs {
  var maxDelay = 0;
  for (final block in widget.program.controlBlocks) {
    for (final rule in block.groups) {
      for (final action in rule.actions) {
        // Include the new C engine's timer parameters.
        final duration = action.timerTMs +
            action.timerTHMs + action.timerTLMs +
            action.timerWarningBeforeMs + action.timerWarningOffMs;
        if (duration > maxDelay) maxDelay = duration;
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

    if (elapsed <= 0 || (_autoPaused && !_counterRunning)) return;

    setState(() {
      // Advance the visible stopwatch in sync with each engine scan.
      // Previously it jumped to the end of the 50 ms frame before scanning,
      // causing output transitions to inherit a timestamp from the future.
      final advanceMs = (elapsed * _testSpeed).round();
      final scanStartMs = _nowMs;
      final counterStartMs = _counterMs;
      final end = scanStartMs + advanceMs;

      while (_nowMs < end) {
        final step = (end - _nowMs).clamp(1, 10);
        _nowMs += step;
        if (_counterRunning) {
          _counterMs = counterStartMs + (_nowMs - scanStartMs);
        }
        _scan();
      }		
			if (_autoTesting &&
    _nowMs - _autoStepStartMs >= _autoStepDurationMs) {
        if (_autoStep + 1 >= _autoMasks.length) {
          _autoTesting = false;
          _autoCompleted = true;
        } else {
          _autoStep++;
          _autoStepStartMs = _nowMs;
          _applyAutoStep();
        }
			}
    });
  }
void _scan() {
  _engine!.scan(nowMs: _nowMs, inputs: _inputs);

  bool? relayState;

  for (var i = 1; i <= 4; i++) {
    final current = _engine!.output(i);

    if (current != _previousOutputs[i - 1]) {
      _recordChange(_outputChangeMs, i);
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
      _recordChange(_inputChangeMs, index);
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
  setState(() {
    _counterMs = 0;
    _inputChangeMs.clear();
    _outputChangeMs.clear();
  });
}
void _stopAutoTest() {
  setState(() {
    _autoTesting = false;
    _autoPaused = true;
    _autoPauseAtMs = _nowMs;
    _autoCompleted = false;
    _counterRunning = false;
  });
}

void _resumeAutoTest() {
  setState(() {
    // Manual stopwatch use while paused may have advanced engine time.
    // Do not count that interval toward the current automatic step.
    _autoStepStartMs += _nowMs - _autoPauseAtMs;
    _autoPaused = false;
    _autoTesting = true;
    _counterRunning = true;
    _lastTick = DateTime.now();
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

Row(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    FilledButton.tonalIcon(
      onPressed: _autoTesting
          ? _stopAutoTest
          : (_autoPaused ? _resumeAutoTest : _startAutoTest),
      icon: Icon(_autoTesting
          ? Icons.stop
          : (_autoPaused ? Icons.play_arrow : Icons.auto_mode)),
      label: Text(_autoTesting
          ? 'Otomatik Durdur'
          : (_autoPaused ? 'Otomatik Devam Et' : 'Otomatik Başlat')),
    ),
    const SizedBox(width: 8),
    IconButton(
      tooltip: _autoTesting ? 'Otomatik testi baştan başlat' : 'Simülasyonu sıfırla',
      onPressed: _resetSimulationButton,
      icon: const Icon(Icons.restart_alt),
    ),
  ],
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

if (_autoTesting || _autoPaused || _autoCompleted) ...[
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: LinearProgressIndicator(
      value: (_autoStep + 1) / _autoMasks.length,
    ),
  ),
  const SizedBox(height: 4),
  Text(
  _autoCompleted
      ? 'Giriş taraması tamamlandı '
      : 'Giriş adımı ${_autoStep + 1} / ${_autoMasks.length}',
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
	
  String _timeText(int ms) {
    if (ms % 1000 == 0) return '${ms ~/ 1000} sn';
    return '${(ms / 1000).toStringAsFixed(3)} sn';
  }

  String _actionTitle(ControlActionType type) => switch (type) {
    ControlActionType.onOffDelay => 'Açma / Kapanma Gecikmesi',
    ControlActionType.wipingRelay => 'Darbe Rölesi',
    ControlActionType.edgeWipingRelay => 'Kenar Tetiklemeli Darbe',
    ControlActionType.asynchronousPulse => 'Asenkron Darbe',
    ControlActionType.randomGenerator => 'Rastgele Darbe',
    ControlActionType.stairwayTimer => 'Merdiven Otomatiği',
    ControlActionType.multipleFunctionTimer => 'Çok İşlevli Anahtar',
    ControlActionType.stopwatchTimer => 'Kronometre',
    ControlActionType.upDownCounter => 'İleri / Geri Sayıcı',
    ControlActionType.hoursCounter => 'Çalışma Saati Sayacı',
    ControlActionType.thresholdTrigger => 'Frekans Eşik Tetikleyici',
    ControlActionType.setOutput => 'ON / OFF',
    ControlActionType.setLatch => 'SET',
    ControlActionType.resetLatch => 'RESET',
    ControlActionType.toggleOutput => 'TOGGLE',
    _ => type.name,
  };

  List<String> _actionParameters(ControlAction a) {
    final p = <String>[];
    void t(String key, int ms) => p.add('$key: ${_timeText(ms)}');
    switch (a.type) {
      case ControlActionType.onOffDelay:
        t('TH', a.timerTHMs); t('TL', a.timerTLMs);
        break;
      case ControlActionType.wipingRelay:
      case ControlActionType.stopwatchTimer:
        t('T', a.timerTMs);
        break;
      case ControlActionType.edgeWipingRelay:
      case ControlActionType.asynchronousPulse:
      case ControlActionType.randomGenerator:
        t('TH', a.timerTHMs); t('TL', a.timerTLMs);
        break;
      case ControlActionType.stairwayTimer:
        t('T', a.timerTMs);
        t('T!', a.timerWarningBeforeMs);
        t('TA', a.timerWarningOffMs);
        break;
      case ControlActionType.multipleFunctionTimer:
        t('T', a.timerTMs); t('TA', a.timerTLMs);
        t('T!', a.timerWarningBeforeMs);
        break;
      case ControlActionType.upDownCounter:
        p.add('Başlangıç: ${a.counterStartValue}');
        p.add('ON: ${a.counterOn}'); p.add('OFF: ${a.counterOff}');
        break;
      case ControlActionType.hoursCounter:
        t('Hedef', a.hoursTargetMs);
        break;
      case ControlActionType.thresholdTrigger:
        t('G_T', a.thresholdGateMs);
        p.add('ON: ${a.thresholdOn}'); p.add('OFF: ${a.thresholdOff}');
        break;
      default:
        break;
    }
    if (ControlAction.timerTypes.contains(a.type)) {
      if (a.timerTHRandom) p.add('TH: RANDOM');
      if (a.timerTLRandom) p.add('TL: RANDOM');
      if (a.timerRepeat) p.add('TEKRAR');
      if (a.timerRetrigger) p.add('YENİDEN TETİKLE');
      if (a.virtualStart) p.add('SANAL GİRİŞ');
    }
    return p;
  }

  Widget _ruleParameters(ControlConditionGroup rule) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final a in rule.actions) ...[
          const SizedBox(height: 6),
          Text('Q${a.outputIndex} · ${_actionTitle(a.type)}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          if (_actionParameters(a).isNotEmpty)
            Wrap(
              spacing: 6, runSpacing: 4,
              children: [
                for (final param in _actionParameters(a))
                  Chip(label: Text(param, style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero),
              ],
            ),
        ],
      ],
    );
  }

	Widget _ruleCard(int ruleNumber, ControlConditionGroup rule) {
  final inputRoles = _ruleInputRoles(rule);
  final inputs = inputRoles.keys.toList()..sort();

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
        _ruleParameters(rule),
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
                        _inputLabel(i, inputRoles[i]!),
                        _inputs[i]!,
                        isInput: true,
                        changeMs: _inputChangeMs[i],
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
                      changeMs: _outputChangeMs[i],
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

  String _inputLabel(int index, Set<String> roles) {
    final labels = roles.where((role) => role.isNotEmpty).toList()..sort();
    return labels.isEmpty ? 'I$index' : 'I$index ${labels.join('/')}';
  }

  Widget _ioCard(
    String label,
    bool active, {
    required bool isInput,
    List<int>? changeMs,
  }) {
    final color = isInput
        ? (active ? Colors.green : Colors.grey)
        : (active ? Colors.amber : Colors.red);

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
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
    ),
        const SizedBox(width: 5),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (changeMs == null || changeMs.isEmpty)
                const Text('—', style: TextStyle(fontSize: 11))
              else
                for (final tick in changeMs)
                  Text(
                    (tick / 1000).toStringAsFixed(2),
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}