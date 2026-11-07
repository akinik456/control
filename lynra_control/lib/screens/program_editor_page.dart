import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../models/control_block.dart';
import '../models/control_program.dart';
import '../core/widgets/control_circuit_painter.dart';
import 'program_simulator_page.dart';
import 'ble_connection_page.dart';
import 'program_test_page.dart';

/// Structured EGER-ISE editor. No free-form program text or block cards.
class ProgramEditorPage extends StatefulWidget {
  const ProgramEditorPage({super.key});
  @override
  State<ProgramEditorPage> createState() => _ProgramEditorPageState();
}

class _ProgramEditorPageState extends State<ProgramEditorPage> {
  final _name = TextEditingController(text: 'Yeni Program');
  late final ControlProgram _program = ControlProgram(
    name: 'Yeni Program',
    controlBlocks: [ControlBlock(id: 'main', groups: [_makeRule()])],
  );
  int _id = 0;



  ControlConditionGroup _makeRule() => ControlConditionGroup(
    id: 'rule_${++_id}',
    conditions: [InputCondition(inputIndex: 1)],
    actions: [ControlAction.timer(ControlActionType.onDelay)],
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  List<ControlConditionGroup> get _rules => _program.controlBlocks.first.groups;

  Future<T?> _choose<T>(String title, List<(T, String)> choices) =>
      showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (title.isNotEmpty)
  ListTile(title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
            ...choices.map((c) => ListTile(
              title: Text(c.$2),
              onTap: () => Navigator.pop(ctx, c.$1),
            )),
          ]),
        ),
      );

  Future<int?> _duration(String title, int currentMs) async {
    var input = (currentMs / 1000).toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          initialValue: input,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Süre (saniye)',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => input = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(input.replaceAll(',', '.'));
              if (value != null && value.isFinite && value >= 0 && value <= 86400) {
                Navigator.pop(ctx, (value * 1000).round());
              }
            },
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  Future<int?> _blinkCountDialog(int current) async {
    var input = current.toString();
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Darbe sayısı (N)'),
        content: TextFormField(
          initialValue: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '0 = sürekli, 1–9 = darbe sayısı',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => input = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(onPressed: () {
            final n = int.tryParse(input.trim());
            if (n != null && n >= 0 && n <= 9) Navigator.pop(ctx, n);
          }, child: const Text('Tamam')),
        ],
      ),
    );
  }

  Widget _token(String text, VoidCallback onTap, {Color? color}) =>
      ActionChip(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        side: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.55)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
        label: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
      );

  Widget _sectionLabel(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text, style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        )),
      );

  ControlAction _makeAction(ControlActionType type) => switch (type) {
        ControlActionType.delay => ControlAction.delay(),
        ControlActionType.setLatch => ControlAction.set(),
        ControlActionType.resetLatch => ControlAction.reset(),
        ControlActionType.toggleOutput => ControlAction.toggle(),
        ControlActionType.blinkOutput => ControlAction.blink(),
        ControlActionType.stairwayOutput => ControlAction.stairway(),
        ControlActionType.multiSwitchOutput => ControlAction.multiSwitch(),
        ControlActionType.stopwatchOutput => ControlAction.stopwatch(),
        _ => ControlAction.output(),
      };

  // Siemens-style function selection. Unsupported functions remain UI-only
  // until their distinct data model and runtime behavior are implemented.
  static const _timerFunctions = <String>[
    'Açılma Gecikmesi',
    'Kapanma Gecikmesi',
    'Açılma / Kapanma Gecikmesi',
    'Kalıcı Açılma Gecikmesi',
    'Darbe Rölesi',
    'Kenar Tetiklemeli Darbe Rölesi',
    'Asenkron Darbe Üreteci',
    'Rastgele Zamanlı Darbe Üreteci',
    'Merdiven Otomatiği',
    'Çok İşlevli Anahtar',
    'Kronometre',
  ];

  ControlActionType _timerType(String name) => switch (name) {
    'Açılma Gecikmesi' => ControlActionType.onDelay,
    'Kapanma Gecikmesi' => ControlActionType.offDelay,
    'Açılma / Kapanma Gecikmesi' => ControlActionType.onOffDelay,
    'Kalıcı Açılma Gecikmesi' => ControlActionType.retentiveOnDelay,
    'Darbe Rölesi' => ControlActionType.wipingRelay,
    'Kenar Tetiklemeli Darbe Rölesi' => ControlActionType.edgeWipingRelay,
    'Asenkron Darbe Üreteci' => ControlActionType.asynchronousPulse,
    'Rastgele Zamanlı Darbe Üreteci' => ControlActionType.randomGenerator,
    'Merdiven Otomatiği' => ControlActionType.stairwayTimer,
    'Çok İşlevli Anahtar' => ControlActionType.multipleFunctionTimer,
    'Kronometre' => ControlActionType.stopwatchTimer,
    _ => ControlActionType.onDelay,
  };

  void _selectTimer(ControlConditionGroup rule, String name,
      {ControlAction? replace}) {
    setState(() {
      final action = ControlAction.timer(_timerType(name),
          outputIndex: replace?.outputIndex ?? 1);
      if (replace == null) {
        rule.actions.add(action);
      } else {
        final index = rule.actions.indexOf(replace);
        if (index >= 0) rule.actions[index] = action;
      }
    });
  }

  String _timerName(ControlAction action) => switch (action.type) {
    ControlActionType.onDelay => 'Açılma Gecikmesi',
    ControlActionType.offDelay => 'Kapanma Gecikmesi',
    ControlActionType.onOffDelay => 'Açılma / Kapanma Gecikmesi',
    ControlActionType.retentiveOnDelay => 'Kalıcı Açılma Gecikmesi',
    ControlActionType.wipingRelay => 'Darbe Rölesi',
    ControlActionType.edgeWipingRelay => 'Kenar Tetiklemeli Darbe Rölesi',
    ControlActionType.asynchronousPulse => 'Asenkron Darbe Üreteci',
    ControlActionType.randomGenerator => 'Rastgele Zamanlı Darbe Üreteci',
    ControlActionType.stairwayTimer => 'Merdiven Otomatiği',
    ControlActionType.multipleFunctionTimer => 'Çok İşlevli Anahtar',
    ControlActionType.stopwatchTimer => 'Kronometre',
    _ => 'Eski fonksiyon',
  };

  int _timerValue(ControlAction action, String key) => switch (key) {
    'T' => action.timerTMs,
    'TH' => action.timerTHMs,
    'TL' => action.timerTLMs,
    'N' => action.timerN,
    'T!' => action.timerWarningBeforeMs,
    'T!L' => action.timerWarningOffMs,
    _ => 0,
  };

  void _setTimerValue(ControlAction action, String key, int value) {
    switch (key) {
      case 'T': action.timerTMs = value;
      case 'TH': action.timerTHMs = value;
      case 'TL': action.timerTLMs = value;
      case 'N': action.timerN = value;
      case 'T!': action.timerWarningBeforeMs = value;
      case 'T!L': action.timerWarningOffMs = value;
    }
  }

  List<(String, String)> _timerParams(String name) => switch (name) {
    'Açılma Gecikmesi' => [('T', 'ON gecikmesi')],
    'Kapanma Gecikmesi' => [('T', 'OFF gecikmesi')],
    'Açılma / Kapanma Gecikmesi' => [('TH', 'ON gecikmesi'), ('TL', 'OFF gecikmesi')],
    'Kalıcı Açılma Gecikmesi' => [('T', 'Gecikme')],
    'Darbe Rölesi' => [('T', 'Darbe süresi')],
    'Kenar Tetiklemeli Darbe Rölesi' => [('TH', 'Darbe süresi'), ('TL', 'Ara süresi'), ('N', 'Darbe sayısı')],
    'Asenkron Darbe Üreteci' => [('TH', 'ON süresi'), ('TL', 'OFF süresi')],
    'Rastgele Zamanlı Darbe Üreteci' => [('TH', 'ON gecikmesi üst sınırı'), ('TL', 'OFF gecikmesi üst sınırı')],
    'Merdiven Otomatiği' => [('T', 'Kapanma süresi'), ('T!', 'Ön uyarı zamanı'), ('T!L', 'Uyarı kesintisi')],
    'Çok İşlevli Anahtar' => [('T', 'Kapanma süresi'), ('TL', 'Uzun basma eşiği'), ('T!', 'Ön uyarı zamanı'), ('T!L', 'Uyarı kesintisi')],
    _ => [],
  };

  Widget _timerParameterPreview(ControlAction action) {
    final name = _timerName(action);
    if (name == 'Kronometre') {
      return _delayToken('Zaman birimi: ${action.stopwatchTimeBase}', () async {
        final unit = await _choose<String>('Kronometre zaman birimi', [
          ('hours', 'Saat'), ('minutes', 'Dakika'), ('seconds', 'Saniye'),
          ('hundredths', '1/100 saniye'),
        ]);
        if (unit != null && mounted) {
          setState(() => action.stopwatchTimeBase = unit);
        }
      });
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (final param in _timerParams(name)) ...[
        _delayToken(param.$1 == 'N'
            ? 'N=${action.timerN}'
            : '${param.$1} ${_seconds(_timerValue(action, param.$1))}', () async {
          final current = _timerValue(action, param.$1);
          final next = param.$1 == 'N'
              ? await _blinkCountDialog(current)
              : await _duration('${param.$1} – ${param.$2}', current);
          if (next != null && mounted && (param.$1 != 'N' || next >= 1)) {
            setState(() => _setTimerValue(action, param.$1, next));
          }
        }),
        const SizedBox(width: 3),
      ],
    ]);
  }

  Future<void> _chooseTimer(ControlConditionGroup rule,
      {ControlAction? replace}) async {
    final name = await _choose<String>('Zaman fonksiyonu', [
      for (final name in _timerFunctions) (name, name),
    ]);
    if (name != null && mounted) _selectTimer(rule, name, replace: replace);
  }

  void _addAction(ControlConditionGroup rule, ControlActionType type) => setState(() {
    if (type == ControlActionType.stopwatchOutput) {
      rule.conditions
        ..clear()
        ..add(InputCondition(inputIndex: 1))
        ..add(InputCondition(inputIndex: 2));
      rule.actions
        ..clear()
        ..add(ControlAction.stopwatch());
    } else {
      rule.actions.add(_makeAction(type));
    }
  });

  Widget _quickAction(ControlConditionGroup rule, IconData icon,
      String label, ControlActionType type, Color color) => OutlinedButton(
        onPressed: () => _addAction(rule, type),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (type == ControlActionType.blinkOutput)
            const SizedBox(
              width: 34,
              height: 22,
              child: CustomPaint(painter: _BlinkWavePainter()),
            )
          else
            Icon(icon, color: color, size: 22),
          const SizedBox(height: 5),
          Text(label, style: const TextStyle(fontSize: 11)),
        ]),
      );

  String _triggerName(ConditionTrigger t) => switch (t) {
    ConditionTrigger.highLevel => 'ON',
    ConditionTrigger.lowLevel => 'OFF',
    ConditionTrigger.risingEdge => 'OFF → ON geçişinde (yükselen kenar)',
    ConditionTrigger.fallingEdge => 'ON → OFF geçişinde (düşen kenar)',
  };

  String _seconds(int ms) => '${(ms / 1000).toStringAsFixed(ms % 1000 == 0 ? 0 : ms % 100 == 0 ? 1 : ms % 10 == 0 ? 2 : 3)} sn';

  Widget _groupFrame(Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.65)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );

  Widget _condition(ControlConditionGroup rule, InputCondition condition) => _groupFrame(Wrap(
    spacing: 5,
    runSpacing: 3,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      _token('I${condition.inputIndex}', () async {
        final v = await _choose<int>('Giriş seç', [for (var i = 1; i <= 4; i++) (i, 'I$i')]);
        if (v != null) setState(() => condition.inputIndex = v);
      }, color: Colors.blue),
      _token(_triggerName(condition.trigger), () async {
        final v = await _choose<ConditionTrigger>('Giriş koşulu', [
          (ConditionTrigger.highLevel, 'ON olduğu sürece'),
          (ConditionTrigger.lowLevel, 'OFF olduğu sürece'),
          (ConditionTrigger.risingEdge, 'ON olursa (yükselen kenar)'),
          (ConditionTrigger.fallingEdge, 'OFF olursa (düşen kenar)'),
        ]);
        if (v != null) setState(() {
          condition.trigger = v;
          condition.expectedState = v == ConditionTrigger.highLevel || v == ConditionTrigger.risingEdge;
        });
      }),
      if (rule.conditions.length > 1)
        IconButton(tooltip: 'Koşulu sil', onPressed: () => setState(() => rule.conditions.remove(condition)), icon: const Icon(Icons.close, size: 18, color: Colors.redAccent)),
    ],
  ));

  Widget _action(ControlConditionGroup rule, ControlAction action) {
    final delete = IconButton(
      tooltip: 'İşlemi sil',
      onPressed: () => setState(() => rule.actions.remove(action)),
      icon: const Icon(Icons.close, size: 18, color: Colors.redAccent),
      constraints: const BoxConstraints(minWidth: 26, minHeight: 40),
      padding: EdgeInsets.zero,
    );
    if (action.type == ControlActionType.delay) {
      return SizedBox(width: 160, child: _groupFrame(Wrap(spacing: 5, runSpacing: 3,
        crossAxisAlignment: WrapCrossAlignment.center, children: [
          _token('${_seconds(action.durationMs)} BEKLE', () async {
            final v = await _duration('Bekleme süresi', action.durationMs);
            if (v != null) setState(() => action.durationMs = v);
          }),
          delete,
        ])));
    }

    final output = _outputToken('Q${action.outputIndex}', () async {
      final v = await _choose<int>('Çıkış seç',
          [for (var i = 1; i <= 4; i++) (i, 'Q$i')]);
      if (v != null) setState(() => action.outputIndex = v);
    }, color: Colors.deepOrange);
    final operation = _operationToken(_timerName(action), () async {
      await _chooseTimer(rule, replace: action);
    });

    return Container(
      width: 160,
      padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.65)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          output, const SizedBox(width: 1), operation, delete,
        ]),
      ),
    );
  }

  // Slightly narrower output controls, without changing text size or height.
  Widget _outputToken(String text, VoidCallback onTap, {Color? color}) => ActionChip(
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
    side: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.55)),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
    label: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    onPressed: onTap,
    visualDensity: VisualDensity.compact,
  );

  // Only output-operation controls use compact horizontal padding.
  Widget _operationToken(String text, VoidCallback onTap) => ActionChip(
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
    side: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.55)),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 7),
    label: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
    onPressed: onTap,
    visualDensity: VisualDensity.compact,
  );

  Widget _delayToken(String text, VoidCallback onTap) => ActionChip(
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
    side: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.55)),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
    label: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
    onPressed: onTap,
    visualDensity: VisualDensity.compact,
  );

  Future<void> _editBlinkTime(ControlAction action, bool isOn) async {
    final min = isOn ? action.blinkOnMinMs : action.blinkOffMinMs;
    final max = isOn ? action.blinkOnMaxMs : action.blinkOffMaxMs;
    final fixed = isOn ? action.durationMs : action.offDurationMs;
    final mode = await _choose<String>(isOn ? 'BLINK ON' : 'BLINK OFF', [
      ('fixed', 'Sabit süre'),
      ('random', 'RANDOM (min–max)'),
    ]);
    if (mode == null || !mounted) return;
    if (mode == 'fixed') {
      final v = await _duration('Sabit süre', fixed);
      if (v != null && v > 0 && mounted) setState(() {
        if (isOn) { action.durationMs = v; action.blinkOnMinMs = 0; action.blinkOnMaxMs = 0; }
        else { action.offDurationMs = v; action.blinkOffMinMs = 0; action.blinkOffMaxMs = 0; }
      });
      return;
    }
    final lower = await _duration('RANDOM minimum süre', min > 0 ? min : fixed);
    if (lower == null || !mounted) return;
    final upper = await _duration('RANDOM maksimum süre', max > 0 ? max : fixed);
    if (upper == null || !mounted) return;
    if (lower <= 0 || upper < lower) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('RANDOM: 0 < minimum ≤ maksimum olmalı')),
      );
      return;
    }
    setState(() {
      if (isOn) { action.blinkOnMinMs = lower; action.blinkOnMaxMs = upper; }
      else { action.blinkOffMinMs = lower; action.blinkOffMaxMs = upper; }
    });
  }

  Widget _actionDelayPreview(ControlAction action) {
    if (action.type == ControlActionType.delay) return const SizedBox.shrink();
    return _timerParameterPreview(action);
  }

  Widget _ruleEditor(ControlConditionGroup rule, int index) {
    final primary = Theme.of(context).colorScheme.primary;
    final outline = Theme.of(context).colorScheme.outline;
    return Container(
      key: ValueKey(rule.id),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: primary.withValues(alpha: 0.75)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
          child: Row(children: [
            Text('KURAL ${index + 1}', style: TextStyle(
              fontWeight: FontWeight.bold, color: primary, fontSize: 15)),
            const Spacer(),
            IconButton(tooltip: 'Yukarı',
              onPressed: index == 0 ? null : () => setState(() {
                _rules.removeAt(index); _rules.insert(index - 1, rule);
              }), icon: const Icon(Icons.arrow_upward, size: 20)),
            IconButton(tooltip: 'Aşağı',
              onPressed: index == _rules.length - 1 ? null : () => setState(() {
                _rules.removeAt(index); _rules.insert(index + 1, rule);
              }), icon: const Icon(Icons.arrow_downward, size: 20)),
            IconButton(tooltip: 'Kuralı sil',
              onPressed: () => setState(() => _rules.remove(rule)),
              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent)),
          ]),
        ),
        Divider(height: 1, color: outline.withValues(alpha: 0.3)),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionLabel('EĞER'),
            const SizedBox(height: 6),
            for (var i = 0;
							i < (rule.logicOperator == LogicOperator.not
									? (rule.conditions.isEmpty ? 0 : 1)
									: rule.conditions.length);
							i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    _condition(rule, rule.conditions[i]),
                    if (rule.conditions.length > 1)
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        InkWell(
                          onTap: i == 0 ? null : () => setState(() {
                            final item = rule.conditions.removeAt(i);
                            rule.conditions.insert(i - 1, item);
                          }),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(Icons.keyboard_arrow_up, size: 20,
                              color: i == 0 ? Theme.of(context).disabledColor : primary),
                          ),
                        ),
                        InkWell(
                          onTap: i == rule.conditions.length - 1 ? null : () => setState(() {
                            final item = rule.conditions.removeAt(i);
                            rule.conditions.insert(i + 1, item);
                          }),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(Icons.keyboard_arrow_down, size: 20,
                              color: i == rule.conditions.length - 1 ? Theme.of(context).disabledColor : primary),
                          ),
                        ),
                      ]),
                    const SizedBox(width: 5),
                    if (i < rule.conditions.length - 1 ||
											(i == 0 && rule.logicOperator == LogicOperator.not))
										_token(switch (rule.logicOperator) {
											LogicOperator.and => 'VE',
											LogicOperator.or => 'VEYA',
											LogicOperator.xor => 'FARKLIYSA',
											LogicOperator.andEdge => 'VE (Kenar)',
											LogicOperator.nand => 'VE DEĞİL',
											LogicOperator.nandEdge => 'VE DEĞİL (Kenar)',
											LogicOperator.nor => 'VEYA DEĞİL',
											LogicOperator.not => 'DEĞİL',
										}, () async {
											final v = await _choose<LogicOperator>('', [
												(LogicOperator.and, 'VE'),
												(LogicOperator.or, 'VEYA'),
												(LogicOperator.xor, 'FARKLIYSA'),
												(LogicOperator.andEdge, 'VE (Kenar)'),
												(LogicOperator.nand, 'VE DEĞİL'),
												(LogicOperator.nandEdge, 'VE DEĞİL (Kenar)'),
												(LogicOperator.nor, 'VEYA DEĞİL'),
												(LogicOperator.not, 'DEĞİL'),
											]);
											if (v != null) {
												setState(() => rule.logicOperator = v);
											}
										})
									else if (rule.logicOperator != LogicOperator.not)
										_token('Koşul ekle', () => setState(() =>
											rule.conditions.add(InputCondition(inputIndex: 1)))),
                  ]),
                ),
              ),
            if (rule.conditions.isEmpty)
              _token('Koşul ekle', () => setState(() =>
                rule.conditions.add(InputCondition(inputIndex: 1)))),
            if (rule.onDelayMs > 0)
              Text('${_seconds(rule.onDelayMs)} boyunca koşul sağlanırsa'),
            const SizedBox(height: 12),
            Divider(height: 1, color: primary.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            _sectionLabel('İSE'),
            const Text('Zaman fonksiyonları: arayüz taslağı; henüz cihaza aktarılabilir değil.', style: TextStyle(fontSize: 11)),
            const SizedBox(height: 6),
            // Fixed columns keep every action, delay and arrow aligned.
            for (var i = 0; i < rule.actions.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: LayoutBuilder(builder: (context, constraints) {
                  const actionWidth = 160.0;
                  const arrowsWidth = 24.0;
                  const gap = 3.0;
                  final available = constraints.maxWidth;
                  final delayWidth = available - actionWidth - arrowsWidth - gap * 2;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: available,
                      child: Row(children: [
                        SizedBox(
                          width: actionWidth,
                          child: _action(rule, rule.actions[i]),
                        ),
                        const SizedBox(width: gap),
                        Expanded(
                          child: rule.actions[i].type == ControlActionType.delay
                              ? const SizedBox.shrink()
                              : Align(
                                  alignment: Alignment.centerRight,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: _actionDelayPreview(rule.actions[i]),
                                  ),
                                ),
                        ),
                        const SizedBox(width: gap),
                        SizedBox(
                          width: arrowsWidth,
                          child: rule.actions.length > 1
                              ? Column(mainAxisSize: MainAxisSize.min, children: [
                                  InkWell(
                                    onTap: i == 0 ? null : () => setState(() {
                                      final item = rule.actions.removeAt(i);
                                      rule.actions.insert(i - 1, item);
                                    }),
                                    child: Padding(
                                      padding: const EdgeInsets.all(2),
                                      child: Icon(Icons.keyboard_arrow_up, size: 20,
                                        color: i == 0 ? Theme.of(context).disabledColor : primary),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: i == rule.actions.length - 1 ? null : () => setState(() {
                                      final item = rule.actions.removeAt(i);
                                      rule.actions.insert(i + 1, item);
                                    }),
                                    child: Padding(
                                      padding: const EdgeInsets.all(2),
                                      child: Icon(Icons.keyboard_arrow_down, size: 20,
                                        color: i == rule.actions.length - 1 ? Theme.of(context).disabledColor : primary),
                                    ),
                                  ),
                                ])
                              : const SizedBox.shrink(),
                        ),
                      ]),
                    ),
                  );
                }),
              ),
            _token('İşlem ekle', () => _chooseTimer(rule)),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Hızlı İşlem Ekle',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              childrenPadding: const EdgeInsets.fromLTRB(0, 0, 0, 6),
              children: [
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final name in _timerFunctions)
                    SizedBox(
                      width: 142,
                      child: OutlinedButton(
                        onPressed: () => _selectTimer(rule, name),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(name, textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11)),
                      ),
                    ),
                ]),
              ],
              ),
            ),
            const SizedBox(height: 6),
            Divider(height: 1, color: primary.withValues(alpha: 0.7)),
            const SizedBox(height: 10),
            Text('Çalışma Şekli', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Wrap(spacing: 5, runSpacing: 4, children: [
              _token(rule.runPolicy == RuleRunPolicy.once
                  ? '1 kez çalış' : 'Tekrarla (koşullar sağlanıyorsa)', () async {
                final v = await _choose<RuleRunPolicy>('Çalışma şekli', [
                  (RuleRunPolicy.once, '1 kez çalış'),
                  (RuleRunPolicy.repeat, 'Tekrarla (koşullar sağlanıyorsa)'),
                ]);
                if (v != null) setState(() => rule.runPolicy = v);
              }),

            ]),
          ]),
        ),
      ]),
    );
  }

  void _openDiagram() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (ctx) => Scaffold(
        appBar: AppBar(title: const Text('Program Şeması')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          for (var i = 0; i < _rules.length; i++)
            Card(child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Kural ${i + 1}', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 8),
                ControlCircuitDiagram(group: _rules[i]),
              ]),
            )),
        ]),
      ),
    ));
  }

  String _summaryCondition(InputCondition c) =>
      'I${c.inputIndex} ${_triggerName(c.trigger)}';

  String _summaryOperator(LogicOperator op) => switch (op) {
    LogicOperator.and => 'VE',
    LogicOperator.or => 'VEYA',
    LogicOperator.xor => 'FARKLIYSA',
		LogicOperator.andEdge => 'VE (Kenar)',
		LogicOperator.nand => 'VE DEĞİL',
		LogicOperator.nandEdge => 'VE DEĞİL (Kenar)',
		LogicOperator.nor => 'VEYA DEĞİL',
		LogicOperator.not => 'DEĞİL',
  };

  // Program is embedded in the URL; no Firebase or additional package needed.
  // Browser counterpart must decode Base64URL and decompress gzip.
  Future<void> _createShareLink() async {
    _program.name = _name.text.trim();
    final jsonBytes = utf8.encode(jsonEncode(_program.toJson()));
    final compressed = gzip.encode(jsonBytes);
    final payload = base64UrlEncode(compressed).replaceAll('=', '');
    final link = 'https://lynra.app/plc/#p=$payload';

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Program Linki'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Program: ${_program.name}'),
              const SizedBox(height: 8),
              Text('JSON: ${jsonBytes.length} bayt · Sıkıştırılmış: ${compressed.length} bayt'),
              const SizedBox(height: 12),
              const Text('Linki kopyalayıp WhatsApp üzerinden gönderebilirsin.'),
              const SizedBox(height: 8),
              SelectableText(link, maxLines: 4),
              if (link.length > 8000) ...[
                const SizedBox(height: 12),
                const Text('Uyarı: Bu link çok uzun. Bazı uygulamalarda paylaşım sorunları olabilir.'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Kapat'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Program linki kopyalandı')),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Linki Kopyala'),
          ),
        ],
      ),
    );
  }

  void _openSummary() {
    final primary = Theme.of(context).colorScheme.primary;
    final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    final normal = base.copyWith(height: 1.5);
    final keyword = normal.copyWith(color: primary, fontWeight: FontWeight.bold);
    final input = normal.copyWith(color: Colors.blue.shade700, fontWeight: FontWeight.bold);
    final output = normal.copyWith(color: Colors.deepOrange.shade700, fontWeight: FontWeight.bold);
    final heading = normal.copyWith(fontWeight: FontWeight.bold);
    final spans = <InlineSpan>[];
    void add(String value, [TextStyle? style]) =>
        spans.add(TextSpan(text: value, style: style ?? normal));

    if (_rules.isEmpty) add('Henüz kural eklenmedi.');
    for (var i = 0; i < _rules.length; i++) {
      final rule = _rules[i];
      if (i > 0) add('\n');
      add('KURAL ${i + 1}\n', heading);
      add('EĞER ', keyword);
      if (rule.conditions.isEmpty) {
        add('(koşul yok)');
      } else {
  if (rule.logicOperator == LogicOperator.not) {
    if (rule.conditions.isNotEmpty) {
      final condition = rule.conditions.first;
      add('DEĞİL ', keyword);
      add('I${condition.inputIndex}', input);
      add(' ${_triggerName(condition.trigger)}');
    }
  } else {
    for (var c = 0; c < rule.conditions.length; c++) {
      if (c > 0) {
        add(' ${_summaryOperator(rule.logicOperator)} ', keyword);
      }

      final condition = rule.conditions[c];
      add('I${condition.inputIndex}', input);
      add(' ${_triggerName(condition.trigger)}');
    }
  }
}
      // A TON waits for the complete logical condition, not each input separately.
      if (rule.onDelayMs > 0) {
        add(', ${_seconds(rule.onDelayMs)} boyunca koşul sağlanırsa');
      }
      add('\n');
      add('İSE ', keyword);
      if (rule.actions.isEmpty) {
        add('(işlem yok)');
      } else {
        for (var a = 0; a < rule.actions.length; a++) {
          if (a > 0) add(' → ');
          final action = rule.actions[a];
          if (action.type == ControlActionType.delay) {
            add('${_seconds(action.durationMs)} bekle');
          } else {
            add('Q${action.outputIndex}', output);
            add(switch (action.type) {
              ControlActionType.onDelay || ControlActionType.offDelay || ControlActionType.onOffDelay || ControlActionType.retentiveOnDelay || ControlActionType.wipingRelay || ControlActionType.edgeWipingRelay || ControlActionType.asynchronousPulse || ControlActionType.randomGenerator || ControlActionType.stairwayTimer || ControlActionType.multipleFunctionTimer || ControlActionType.stopwatchTimer => ' ${_timerName(action)}',
              ControlActionType.setLatch => ' SET',
              ControlActionType.resetLatch => ' RESET',
              ControlActionType.toggleOutput => ' DEĞİŞTİR',
              ControlActionType.stairwayOutput => ' MERDİVEN (T ${_seconds(action.durationMs)} / Uyarı ${_seconds(action.stairWarningBeforeMs)} / Kesinti ${_seconds(action.stairWarningOffMs)} / Tekrar ${action.stairRetrigger ? 'Açık' : 'Kapalı'})',
              ControlActionType.multiSwitchOutput => ' ÇOK İŞLEVLİ (T ${_seconds(action.durationMs)} / Uzun ${_seconds(action.multiLongPressMs)} / Uyarı ${_seconds(action.stairWarningBeforeMs)} / Kesinti ${_seconds(action.stairWarningOffMs)})',
              ControlActionType.stopwatchOutput => ' KRONOMETRE (EN: I${rule.conditions.isNotEmpty ? rule.conditions[0].inputIndex : 1} / RESET: I${rule.conditions.length > 1 ? rule.conditions[1].inputIndex : 2} / T ${_seconds(action.durationMs)})',
              ControlActionType.blinkOutput => ' YANIP SÖN (Başlangıç ${_seconds(action.blinkStartDelayMs)} / ON ${action.blinkOnMinMs > 0 ? 'RANDOM ${_seconds(action.blinkOnMinMs)}–${_seconds(action.blinkOnMaxMs)}' : _seconds(action.durationMs)} / OFF ${action.blinkOffMinMs > 0 ? 'RANDOM ${_seconds(action.blinkOffMinMs)}–${_seconds(action.blinkOffMaxMs)}' : _seconds(action.offDurationMs)} / N=${action.blinkCount})',
              _ => action.outputState ? ' ON' : ' OFF',
            });
          }
        }
      }
      // Describe the return behavior only when it is unambiguous.
      final levelConditions = rule.conditions.every((c) =>
          c.trigger == ConditionTrigger.highLevel ||
          c.trigger == ConditionTrigger.lowLevel);
      final outputActions = rule.actions.where((a) =>
          a.type == ControlActionType.setOutput).toList();
      final simpleContinuous = rule.executionMode == RuleExecutionMode.continuous &&
          levelConditions && rule.actions.length == 1 && outputActions.length == 1;
      if (simpleContinuous) {
        final a = outputActions.first;
        add('\nKoşul artık sağlanmazsa ');
        if (rule.offDelayMs > 0) add('${_seconds(rule.offDelayMs)} sonra ');
        add('Q${a.outputIndex}', output);
        add(a.outputState ? ' OFF olur.' : ' ON olur.');
      } else if (rule.actions.any((a) => a.type == ControlActionType.setLatch || a.type == ControlActionType.resetLatch)) {
        for (final action in rule.actions) {
          if (action.type == ControlActionType.setLatch) {
            add('\nQ${action.outputIndex}', output);
            add(' ON olur ve başka bir komut değiştirmedikçe ON kalır.');
          } else if (action.type == ControlActionType.resetLatch) {
            add('\nQ${action.outputIndex}', output);
            add(' OFF olur ve başka bir komut değiştirmedikçe OFF kalır.');
          }
        }
      } else if (rule.actions.any((a) => a.type == ControlActionType.blinkOutput)) {
        add('\nN=0 ise koşul sağlandığı sürece yanıp söner; N>0 ise tetiklemede belirlenen sayıda darbe üretir.');
      } else if (rule.actions.any((a) => a.type == ControlActionType.toggleOutput)) {
        for (final action in rule.actions) {
          if (action.type == ControlActionType.toggleOutput) {
            add('\nQ${action.outputIndex}', output);
            add(' mevcut durumunun tersine geçer (ON ise OFF, OFF ise ON).');
          }
        }
      } else if (rule.offDelayMs > 0) {
        add('\nOFF gecikmesi: ${_seconds(rule.offDelayMs)}.');
      }
       add(rule.runPolicy == RuleRunPolicy.once
           ? '\nÇalışma şekli: 1 kez çalış.'
           : '\nÇalışma şekli: Tekrarla (koşullar sağlanıyorsa).');
      add('\n');
    }

    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (ctx) => Scaffold(
        appBar: AppBar(title: const Text('Program Özeti'), actions: [
					IconButton(
						tooltip: 'Program Testi',
						icon: const Icon(Icons.science_outlined),
						onPressed: () {
							_program.name = _name.text.trim();

							Navigator.of(context).push(
								MaterialPageRoute<void>(
									builder: (_) => ProgramTestPage(program: _program),
								),
							);
						},
					),
          IconButton(
            tooltip: 'Program Şeması',
            icon: const Icon(Icons.account_tree_outlined),
            onPressed: () {
              Navigator.of(ctx).pop();
              _openDiagram();
            },
          ),
          IconButton(
            tooltip: 'Link Oluştur',
            icon: const Icon(Icons.link_outlined),
            onPressed: _createShareLink,
          ),
					IconButton(
						tooltip: 'Cihaza Gönder',
						icon: const Icon(Icons.upload_outlined),
						onPressed: () {
							_program.name = _name.text.trim();

							Navigator.of(context).push(
								MaterialPageRoute<void>(
									builder: (_) => BleConnectionPage(program: _program),
								),
							);
						},
					),
        ]),
        body: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: primary.withValues(alpha: 0.75), width: 1.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText.rich(TextSpan(style: normal, children: spans)),
            ),
          ]),
        )),
      ),
    ));
  }

  void _showJson() {
    _program.name = _name.text.trim();
    final json = const JsonEncoder.withIndent('  ').convert(_program.toJson());
		final compactJson = jsonEncode(_program.toJson());
		debugPrint('PLC JSON SIZE: ${utf8.encode(compactJson).length} bytes');
    showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Program JSON'),
      content: SingleChildScrollView(child: SelectableText(json)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat'))],
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Program Editörü'), actions: [
      IconButton(tooltip: 'Simülasyon', icon: const Icon(Icons.show_chart), onPressed: () {
        _program.name = _name.text.trim();
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ProgramSimulatorPage(program: _program),
        ));
      }),
      IconButton(tooltip: 'Program Özeti', onPressed: _openSummary,
          icon: const Icon(Icons.description_outlined)),
      IconButton(tooltip: 'Program JSON', onPressed: _showJson,
          icon: const Icon(Icons.data_object)),
    ]),
    body: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: ListView(padding: const EdgeInsets.all(14), children: [
        TextField(
          controller: _name,
          decoration: InputDecoration(
            labelText: 'Program adı',
            prefixIcon: const Icon(Icons.edit_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
        ),
        const SizedBox(height: 10),
        Text('İfadelere dokunarak düzenleyin.',
          style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 14),
        for (var i = 0; i < _rules.length; i++) _ruleEditor(_rules[i], i),
        const SizedBox(height: 4),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: () => setState(() => _rules.add(_makeRule())),
          icon: const Icon(Icons.add), label: const Text('Yeni kural ekle'),
        ),
        const SizedBox(height: 24),
      ]),
    )),
  );
}


/// Decorative square-wave preview; does not alter PLC timing or behavior.
class _BlinkWavePainter extends CustomPainter {
  const _BlinkWavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00D5F5)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final high = size.height * 0.23;
    final low = size.height * 0.77;
    final step = size.width / 4;
    final path = Path()
      ..moveTo(0, low)
      ..lineTo(step * 0.5, low)
      ..lineTo(step * 0.5, high)
      ..lineTo(step * 1.5, high)
      ..lineTo(step * 1.5, low)
      ..lineTo(step * 2.5, low)
      ..lineTo(step * 2.5, high)
      ..lineTo(step * 3.5, high)
      ..lineTo(step * 3.5, low)
      ..lineTo(size.width, low);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BlinkWavePainter oldDelegate) => false;
}
