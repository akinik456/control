import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/control_block.dart';
import '../models/control_program.dart';
import '../core/widgets/control_circuit_painter.dart';
import '../core/theme/app_colors.dart';
import 'program_simulator_page.dart';
import 'ble_connection_page.dart';
import 'program_test_page.dart';
import '../services/lynra_ble_service.dart';
import '../services/local_program_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

/// Structured EGER-ISE editor. No free-form program text or block cards.
class ProgramEditorPage extends StatefulWidget {
  const ProgramEditorPage({super.key, this.openCloudOnStart = false, this.initialActionsOpen = false});
  final bool openCloudOnStart;
  final bool initialActionsOpen;
  @override
  State<ProgramEditorPage> createState() => _ProgramEditorPageState();
}

class _ProgramEditorPageState extends State<ProgramEditorPage> {
  final _name = TextEditingController(text: 'Yeni Program');
  late ControlProgram _program = ControlProgram(
    name: 'Yeni Program',
    controlBlocks: [ControlBlock(id: 'main', groups: [_makeRule()])],
  );
  int _id = 0;
  String? _cloudProgramId;
	String? _localProgramId;
  bool _cloudSaving = false;
  bool _programActionsOpen = false;
  String? _savedFingerprint;
  // UI-only expansion state; does not change saved program data.
  final Set<String> _collapsedConditions = {'rule_1'};
  final Set<String> _collapsedGroups = {};
	final Set<ControlAction> _expandedActions = {};
	final Set<String> _collapsedRules = {'rule_1'};

  @override
  void initState() {
    super.initState();
    _programActionsOpen = widget.initialActionsOpen;
    if (widget.openCloudOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openFromCloud();
      });
    }
  }

  String _conditionText(InputCondition c) {
  final text = switch (c.trigger) {
    ConditionTrigger.highLevel => 'I${c.inputIndex}=ON',
    ConditionTrigger.lowLevel => 'I${c.inputIndex}=OFF',
    ConditionTrigger.risingEdge => 'I${c.inputIndex}=↑',
    ConditionTrigger.fallingEdge => 'I${c.inputIndex}=↓',
  };

  return text;
}

  String _logicText(LogicOperator op) => switch (op) {
  LogicOperator.and => 'VE',
  LogicOperator.or => 'VEYA',
  LogicOperator.xor => 'FARKLIYSA',
  LogicOperator.nand => 'TERS VE',
  LogicOperator.nor => 'TERS VEYA',
  LogicOperator.not => 'DEĞİL',
};

  String _subgroupText(ConditionSubgroup group) =>
      '(${group.conditions.isEmpty ? 'koşul yok' : group.conditions.map(_conditionText).join(' ${_logicText(group.logicOperator)} ')})';

  String _allConditionsText(ControlConditionGroup rule) =>
      rule.conditionGroups.map(_subgroupText).join(' ${_logicText(rule.groupsOperator)} ');




  // Presentation only: colored, readable collapsed EGER summaries.
  Widget _conditionSummary(ConditionSubgroup group) => RichText(
    softWrap: true,
    text: TextSpan(
      style: DefaultTextStyle.of(context).style.copyWith(
  fontSize: 13,
  fontWeight: FontWeight.w600,
	decoration: TextDecoration.none,
),
      children: _subgroupSpans(group),
    ),
  );

  List<InlineSpan> _subgroupSpans(ConditionSubgroup group) {
    final scheme = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[
      TextSpan(text: '( ', style: TextStyle(color: scheme.onSurfaceVariant)),
    ];
    if (group.conditions.isEmpty) {
      spans.add(const TextSpan(text: 'koşul yok'));
    }
    for (var i = 0; i < group.conditions.length; i++) {
      if (i > 0) {
        spans.add(TextSpan(
  text: ' ${_logicText(
    i - 1 < group.conditionOperators.length
        ? group.conditionOperators[i - 1]
        : group.logicOperator,
  )} ',
  style: TextStyle(color: scheme.onSurface),
));
      }
      spans.add(TextSpan(text: _conditionText(group.conditions[i]),
          style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold)));
    }
    spans.add(TextSpan(text: ' )', style: TextStyle(color: scheme.onSurfaceVariant)));
    return spans;
  }

  Widget _allConditionsSummary(ControlConditionGroup rule) {
    final scheme = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];
    for (var i = 0; i < rule.conditionGroups.length; i++) {
      if (i > 0) {
        spans.add(TextSpan(
					text: ' ${_logicText(
  i - 1 < rule.groupOperators.length
      ? rule.groupOperators[i - 1]
      : rule.groupsOperator,
)} ',
					style: const TextStyle(
						color: Colors.green,
						fontWeight: FontWeight.bold,
					),
				));
      }
      spans.addAll(_subgroupSpans(rule.conditionGroups[i]));
    }
    return RichText(
      softWrap: true,
      text: TextSpan(
        style: DefaultTextStyle.of(context).style.copyWith(
  fontSize: 13,
  fontWeight: FontWeight.w600,
	decoration: TextDecoration.none,
),
        children: spans,
      ),
    );
  }

  ControlConditionGroup _makeRule() => ControlConditionGroup(
    id: 'rule_${++_id}',
    conditions: [InputCondition(inputIndex: 1)],
    actions: [ControlAction.timer(ControlActionType.onOffDelay)],
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

  Future<int?> _duration(String title, int currentMs, {int minMs = 0}) async {
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
              if (value != null && value.isFinite && value >= 0 && value <= 86400 &&
                  (value * 1000).round() >= minMs) {
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
            labelText: '0 = sınırsız, 1–255 = darbe sayısı',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => input = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(onPressed: () {
            final n = int.tryParse(input.trim());
            if (n != null && n >= 0 && n <= 255) Navigator.pop(ctx, n);
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
    'Açma / Kapanma Gecikmesi',
    'Darbe Rölesi',
    'Kenar Tetiklemeli Darbe Rölesi',
    'Asenkron Darbe Üreteci',
    'Merdiven Otomatiği',
    'Çok İşlevli Anahtar',
    'Kronometre',
  ];

  ControlActionType _timerType(String name) => switch (name) {
    'Açma / Kapanma Gecikmesi' => ControlActionType.onOffDelay,
    'Darbe Rölesi' => ControlActionType.wipingRelay,
    'Kenar Tetiklemeli Darbe Rölesi' => ControlActionType.edgeWipingRelay,
    'Asenkron Darbe Üreteci' => ControlActionType.asynchronousPulse,
    'Merdiven Otomatiği' => ControlActionType.stairwayTimer,
    'Çok İşlevli Anahtar' => ControlActionType.multipleFunctionTimer,
    'Kronometre' => ControlActionType.stopwatchTimer,
    _ => ControlActionType.onOffDelay,
  };

  void _selectTimer(ControlConditionGroup rule, String name,
      {ControlAction? replace}) {
    setState(() {
      final action = ControlAction.timer(_timerType(name),
          outputIndex: replace?.outputIndex ?? 1);
					final edgeOnly =
    action.type == ControlActionType.edgeWipingRelay ||
    action.type == ControlActionType.stairwayTimer;

for (final condition in rule.conditions) {
  condition.trigger = edgeOnly
      ? ConditionTrigger.risingEdge
      : ConditionTrigger.highLevel;
  condition.expectedState = true;
}
      if (action.type == ControlActionType.edgeWipingRelay) {
        action.timerTHMs = 1000;
        action.timerTLMs = 500;
        action.timerN = 2;
      }
			if (action.type == ControlActionType.asynchronousPulse) {
				action.timerTHMs = 1000;
				action.timerTLMs = 500;
			}
			if (action.type == ControlActionType.stairwayTimer) {
				action.timerTMs = 10000;
				action.timerWarningBeforeMs = 3000;
				action.timerWarningOffMs = 500;
			}
			if (action.type == ControlActionType.multipleFunctionTimer) {
				action.timerTMs = 10000;
				action.timerTLMs = 2000;
				action.timerWarningBeforeMs = 3000;
				action.timerWarningOffMs = 500;
			}
			if (action.type == ControlActionType.stopwatchTimer) {
				action.timerTMs = 10000;
				action.resetInputIndex = 2;
			}
      if (replace == null) {
        rule.actions.add(action);
      } else {
        final index = rule.actions.indexOf(replace);
        if (index >= 0) rule.actions[index] = action;
        _expandedActions.remove(replace);
      }
      _expandedActions.add(action);
    });
  }

  String _timerName(ControlAction action) => switch (action.type) {
    ControlActionType.setOutput => action.outputState ? 'ON' : 'OFF',
    ControlActionType.setLatch => 'SET',
    ControlActionType.resetLatch => 'RESET',
    ControlActionType.toggleOutput => 'TOGGLE',
    ControlActionType.onDelay => 'Açma Gecikmesi',
    ControlActionType.offDelay => 'Kapanma Gecikmesi',
    ControlActionType.onOffDelay => 'Açma / Kapanma Gecikmesi',
    ControlActionType.wipingRelay => 'Darbe Rölesi',
    ControlActionType.edgeWipingRelay => 'Kenar Tetiklemeli Darbe Rölesi',
    ControlActionType.asynchronousPulse => 'Asenkron Darbe Üreteci',
    ControlActionType.stairwayTimer => 'Merdiven Otomatiği',
    ControlActionType.multipleFunctionTimer => 'Çok İşlevli Anahtar',
    ControlActionType.stopwatchTimer => 'Kronometre',
		ControlActionType.upDownCounter => 'İleri / Geri Sayıcı',
		ControlActionType.hoursCounter => 'Çalışma Saati Sayacı',
		ControlActionType.thresholdTrigger => 'Frekans Eşik Tetikleyici',
    _ => 'Eski fonksiyon',
  };

  int _timerValue(ControlAction action, String key) => switch (key) {
    'T' => action.timerTMs,
    'TH' => action.timerTHMs,
    'TL' => action.timerTLMs,
		'TA' => action.timerTLMs,
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
			case 'TA': action.timerTLMs = value;
      case 'N': action.timerN = value;
      case 'T!': action.timerWarningBeforeMs = value;
      case 'T!L': action.timerWarningOffMs = value;
    }
  }

  List<(String, String)> _timerParams(String name) => switch (name) {
    'Açma / Kapanma Gecikmesi' => [('TH', 'ON gecikmesi'), ('TL', 'OFF gecikmesi')],
    'Darbe Rölesi' => [('T', 'Darbe süresi')],
    'Kenar Tetiklemeli Darbe Rölesi' => [('TH', 'Darbe süresi'), ('TL', 'Ara süresi'), ('N', 'Darbe sayısı')],
    'Asenkron Darbe Üreteci' => [('TH', 'ON süresi'), ('TL', 'OFF süresi')],
    'Merdiven Otomatiği' => [('T', 'Kapanma süresi'), ('T!', 'Ön uyarı zamanı'), ('T!L', 'Uyarı kesintisi')],
    'Çok İşlevli Anahtar' => [('T', 'Kapanma süresi'), ('TL', 'Uzun basma eşiği'), ('T!', 'Ön uyarı zamanı'), ('T!L', 'Uyarı kesintisi')],
    _ => [],
  };

  Widget _timerParameterPreview(ControlConditionGroup rule, ControlAction action) {
   final edgeTimer = action.type == ControlActionType.onOffDelay && rule.conditions.length == 1 && (rule.conditions.first.trigger == ConditionTrigger.risingEdge || rule.conditions.first.trigger == ConditionTrigger.fallingEdge);
  final name = _timerName(action);

  Widget retriggerToken() => _delayToken(
        action.timerRetrigger
            ? 'YENİDEN TETİKLE: ON'
            : 'YENİDEN TETİKLE: OFF',
        () => setState(
          () => action.timerRetrigger = !action.timerRetrigger,
        ),
      );

  Widget resetToken() => _delayToken(
        'RESET: ${action.resetInputIndex == 0 ? "YOK" : "I${action.resetInputIndex}"}',
        () async {
          final v = await _choose<int>('RESET girişi', [
            for (var i = 1; i <= 4; i++) (i, 'I$i'),
          ]);
          if (v != null && mounted) {
            setState(() => action.resetInputIndex = v);
          }
        },
      );

  Widget timeToken(String title) => _delayToken(
        'T ${_seconds(action.timerTMs)}',
        () async {
          final v = await _duration(
            title,
            action.timerTMs,
            minMs: 1,
          );
          if (v != null && mounted) {
            setState(() => action.timerTMs = v);
          }
        },
      );

  Widget virtualToken() => _delayToken(
        action.virtualStart ? 'SANAL GİRİŞ: AÇIK' : 'SANAL GİRİŞ: KAPALI',
        () => setState(() => action.virtualStart = !action.virtualStart),
      );

  if (name == 'Kronometre') {
    return Wrap(
      spacing: 4,
      runSpacing: 6,
      children: [
        virtualToken(),
        resetToken(),
        timeToken('Kronometre hedef süresi'),
      ],
    );
  }

  final repeatable =
      action.type == ControlActionType.edgeWipingRelay;

  final retriggerable =
      action.type == ControlActionType.edgeWipingRelay ||
      action.type == ControlActionType.stairwayTimer;

  return Wrap(
    spacing: 4,
    runSpacing: 6,
    children: [
      if (const {
        ControlActionType.onOffDelay,
        ControlActionType.wipingRelay,
        ControlActionType.edgeWipingRelay,
        ControlActionType.asynchronousPulse,
        ControlActionType.randomGenerator,
      }.contains(action.type))
        virtualToken(),
      if (action.type == ControlActionType.onOffDelay)
        resetToken(),
      if (edgeTimer) ...[
        retriggerToken(),
        _delayToken(
          action.timerRepeat ? 'TEKRARLA: AÇIK' : 'TEKRARLA: KAPALI',
          () => setState(() {
            action.timerRepeat = !action.timerRepeat;
            if (action.timerRepeat) {
              if (action.timerTHMs < 1000) action.timerTHMs = 1000;
              if (action.timerTLMs < 1000) action.timerTLMs = 1000;
            }
          }),
        ),
      ],
      if (retriggerable)
        retriggerToken(),

      if (repeatable) ...[
        _delayToken(
          action.timerRepeat
              ? 'TEKRARLA: ON'
              : 'TEKRARLA: OFF',
          () => setState(() {
            if (action.timerN == 0) return;
            action.timerRepeat = !action.timerRepeat;
          }),
        ),
        if (action.timerRepeat || action.timerN == 0)
          resetToken(),
      ],

      if (action.type == ControlActionType.edgeWipingRelay) ...[
        _delayToken(
          'TH: ${action.timerTHRandom ? "RASTGELE" : "SABİT"}',
          () async {
            final selected = await _choose<bool>('TH gecikme tipi', [
              (false, 'SABİT'), (true, 'RASTGELE (0–TH)'),
            ]);
            if (selected != null && mounted) {
              setState(() => action.timerTHRandom = selected);
            }
          },
        ),
        _delayToken(
          'TL: ${action.timerTLRandom ? "RASTGELE" : "SABİT"}',
          () async {
            final selected = await _choose<bool>('TL gecikme tipi', [
              (false, 'SABİT'), (true, 'RASTGELE (0–TL)'),
            ]);
            if (selected != null && mounted) {
              setState(() => action.timerTLRandom = selected);
            }
          },
        ),
      ],
      for (final param in (
  edgeTimer
      ? <(String, String)>[
          ('TH', 'Açma gecikmesi'),
          ('TA', 'Aktif kalma süresi (0 = RESET gelene kadar ON)'),
        ]
      : _timerParams(name)
))
        _delayToken(
          param.$1 == 'N'
              ? 'N=${action.timerN}'
              : '${param.$1} ${_seconds(_timerValue(action, param.$1))}',
          () async {
            final current = _timerValue(action, param.$1);

            final next = param.$1 == 'N'
                ? await _blinkCountDialog(current)
                : await _duration(
                    '${param.$1} – ${param.$2}',
                    current,
                    minMs: edgeTimer && action.timerRepeat &&
                            (param.$1 == 'TH' || param.$1 == 'TA')
                        ? 1000
                        : action.type == ControlActionType.edgeWipingRelay &&
                                (param.$1 == 'TH' || param.$1 == 'TL')
                            ? 1
                            : 0,
                  );

            if (next != null &&
                mounted &&
                (param.$1 != 'N' || next >= 0) &&
                (action.type != ControlActionType.asynchronousPulse ||
                    next > 0) &&
                (action.type != ControlActionType.stairwayTimer ||
                    param.$1 != 'T' ||
                    next > 0) &&
                (action.type !=
                        ControlActionType.multipleFunctionTimer ||
                    (param.$1 != 'T' && param.$1 != 'TL') ||
                    next > 0)) {
              setState(() {
                _setTimerValue(action, param.$1, next);
                if (action.type == ControlActionType.edgeWipingRelay &&
                    param.$1 == 'N' && next == 0) {
                  action.timerRepeat = true;
                }
              });
            }
          },
        ),
    ],
  );
}

Future<void> _chooseFunction(
  ControlConditionGroup rule, {
  ControlAction? replace,
  String? quickCategory,
  String? quickSelection,
}) async {
  final category = quickCategory ?? await _choose<String>('Fonksiyon grubu', [
    ('timers', 'ZAMAN FONKSİYONLARI'),
    ('counters', 'SAYAÇLAR'),
    ('outputs', 'ÇIKIŞ KONTROLÜ'),
  ]);

  if (category == null || !mounted) return;

  if (category == 'timers') {
    await _chooseTimer(rule, replace: replace);
    return;
  }

  if (category == 'outputs') {
    final selected = quickSelection ?? await _choose<String>('Çıkış kontrolü', [
      ('on', 'ON'),
      ('off', 'OFF'),
      ('set', 'SET'),
      ('reset', 'RESET'),
      ('toggle', 'TOGGLE'),
    ]);
    if (selected == null || !mounted) return;
    setState(() {
      final outputIndex = replace?.outputIndex ?? 1;
      final action = switch (selected) {
        'off' => ControlAction.output(outputIndex: outputIndex, outputState: false),
        'set' => ControlAction.set(outputIndex: outputIndex),
        'reset' => ControlAction.reset(outputIndex: outputIndex),
        'toggle' => ControlAction.toggle(outputIndex: outputIndex),
        _ => ControlAction.output(outputIndex: outputIndex),
      };
      if (replace == null) {
        rule.actions.add(action);
      } else {
        final index = rule.actions.indexOf(replace);
        if (index >= 0) rule.actions[index] = action;
        _expandedActions.remove(replace);
      }
      _expandedActions.add(action);
    });
    return;
  }

  final selected = quickSelection ?? await _choose<String>('Sayaç fonksiyonu', [
    ('upDown', 'İleri / Geri Sayıcı'),
		('hours', 'Çalışma Saati Sayacı'),
		('threshold', 'Frekans Eşik Tetikleyici'),
  ]);

  if (selected == null || !mounted) return;

  if (selected == 'upDown') {
    setState(() {
      final action = ControlAction.counter(
        ControlActionType.upDownCounter,
        outputIndex: replace?.outputIndex ?? 1,
      )..resetInputIndex = 3;

      if (replace == null) {
        rule.actions.add(action);
      } else {
        final index = rule.actions.indexOf(replace);
        if (index >= 0) rule.actions[index] = action;
      _expandedActions.remove(replace);
      }
    _expandedActions.add(action);
    });
  }
	if (selected == 'hours') {
  setState(() {
    final action = ControlAction.counter(
      ControlActionType.hoursCounter,
      outputIndex: replace?.outputIndex ?? 1,
    )
      ..hoursEnableInputIndex = 1
      ..resetInputIndex = 2
      ..hoursResetAllInputIndex = 3
      ..hoursTargetMs = 3600000;

    if (replace == null) {
      rule.actions.add(action);
    } else {
      final index = rule.actions.indexOf(replace);
      if (index >= 0) rule.actions[index] = action;
      _expandedActions.remove(replace);
    }
    _expandedActions.add(action);
  });
}
if (selected == 'threshold') {
  setState(() {
    final action = ControlAction.counter(
      ControlActionType.thresholdTrigger,
      outputIndex: replace?.outputIndex ?? 1,
    )
      ..thresholdInputIndex = 1
      ..thresholdGateMs = 1000
      ..thresholdOn = 10
      ..thresholdOff = 5;

    if (replace == null) {
      rule.actions.add(action);
    } else {
      final index = rule.actions.indexOf(replace);
      if (index >= 0) rule.actions[index] = action;
      _expandedActions.remove(replace);
    }
    _expandedActions.add(action);
  });
}
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

  Widget _quickFunctionHeading(String label) => Padding(
    padding: const EdgeInsets.only(top: 2, bottom: 3),
    child: Text(label, style: TextStyle(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.bold, fontSize: 11,
    )),
  );

  Widget _quickFunctionGrid(int columns, List<Widget> items) => LayoutBuilder(
    builder: (context, constraints) {
      final count = columns == 2 && constraints.maxWidth >= 560 ? 4 : columns;
      final width = (constraints.maxWidth - (count - 1) * 4) / count;
      return Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final item in items) SizedBox(width: width, child: item),
        ],
      );
    },
  );

  Widget _quickFunctionButton(String label, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
            child: Center(child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurface,
                fontSize: 11, fontWeight: FontWeight.w500),
            )),
          ),
        ),
      ),
    );
  }

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
        final edgeOnly = rule.actions.any((a) =>
    a.type == ControlActionType.edgeWipingRelay ||
    a.type == ControlActionType.stairwayTimer);
        final onOnly = rule.actions.any((a) =>
    a.type == ControlActionType.multipleFunctionTimer ||
    a.type == ControlActionType.stopwatchTimer);

final v = await _choose<ConditionTrigger>('Giriş koşulu', [
  if (!edgeOnly) ...[
    (ConditionTrigger.highLevel, 'ON '),
    if (!onOnly) (ConditionTrigger.lowLevel, 'OFF '),
  ],
  if (edgeOnly || rule.actions.any((a) => a.type == ControlActionType.onOffDelay)) ...[
    (ConditionTrigger.risingEdge, 'ON olursa (yükselen kenar)'),
    if (!rule.actions.any((a) => a.type == ControlActionType.stairwayTimer))
      (ConditionTrigger.fallingEdge, 'OFF olursa (düşen kenar)'),
  ],
]);
        if (v != null) setState(() {
          condition.trigger = v;
          condition.expectedState = v == ConditionTrigger.highLevel || v == ConditionTrigger.risingEdge;
        });
      }),
			
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
      await _chooseFunction(rule, replace: action);
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
	Widget _hoursTargetToken(ControlAction action) {
  final hours = action.hoursTargetMs ~/ 3600000;
  final minutes = (action.hoursTargetMs % 3600000) ~/ 60000;

  return _delayToken('T: ${hours}sa ${minutes}dk', () async {
    var h = hours.toString();
    var m = minutes.toString();

    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hedef çalışma süresi'),
        content: Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: h,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Saat'),
                onChanged: (v) => h = v,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                initialValue: m,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Dakika'),
                onChanged: (v) => m = v,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () {
              final hh = int.tryParse(h.trim());
              final mm = int.tryParse(m.trim());

              if (hh != null && hh >= 0 &&
                  hh <= 1000000 &&
                  mm != null && mm >= 0 && mm < 60 &&
                  (hh > 0 || mm > 0)) {
                Navigator.pop(ctx, hh * 3600000 + mm * 60000);
              }
            },
            child: const Text('Tamam'),
          ),
        ],
      ),
    );

    if (selected != null && mounted) {
		debugPrint('HOURS TARGET MS: $selected');
      setState(() => action.hoursTargetMs = selected);
    }
  });
}
Widget _hoursInputToken(
  ControlAction action,
  String label,
  int value,
  void Function(int) update,
) {
  return _delayToken(
    '$label: ${value == 0 ? "YOK" : "I$value"}',
    () async {
      final selected = await _choose<int>('$label girişi', [
        if (label != 'EN') (0, 'YOK'),
        for (var i = 1; i <= 4; i++) (i, 'I$i'),
      ]);

      if (selected == null || !mounted) return;

      final en = label == 'EN'
          ? selected : action.hoursEnableInputIndex;
      final r = label == 'R'
          ? selected : action.resetInputIndex;
      final ral = label == 'Ral'
          ? selected : action.hoursResetAllInputIndex;

      if ((r != 0 && r == en) ||
          (ral != 0 && (ral == en || ral == r))) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('EN, R ve Ral girişleri farklı olmalı'),
          ),
        );
        return;
      }

      setState(() => update(selected));
    },
  );
}	
Widget _counterInputToken(
  ControlAction action,
  String label,
  int value,
  void Function(int) update,
) {
  return _delayToken('$label: ${value == 0 ? "YOK" : "I$value"}', () async {
    final selected = await _choose<int>('$label girişi', [
      if (label != 'CNT') (0, 'YOK'),
      for (var i = 1; i <= 4; i++) (i, 'I$i'),
    ]);

    if (selected == null || !mounted) return;

    final cnt = label == 'CNT' ? selected : action.counterInputIndex;
    final dir = label == 'DIR' ? selected : action.directionInputIndex;
    final reset = label == 'RESET' ? selected : action.resetInputIndex;

    if ((dir != 0 && dir == cnt) ||
        (reset != 0 && (reset == cnt || reset == dir))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CNT, DIR ve RESET girişleri farklı olmalı')),
      );
      return;
    }

    setState(() => update(selected));
  });
}
Widget _counterValueToken(
  String label,
  int current,
 void Function(int) update, {
  int min = -2147483648,
  int max = 2147483647,
}) {
  return _delayToken('$label: $current', () async {
    var input = current.toString();

    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$label değeri'),
        content: TextFormField(
          initialValue: input,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(
            signed: true,
          ),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => input = v,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(input.trim());
              if (value != null &&
                  value >= min &&
                  value <= max) {
                Navigator.pop(ctx, value);
              }
            },
            child: const Text('Tamam'),
          ),
        ],
      ),
    );

    if (selected != null && mounted) {
      setState(() => update(selected));
    }
  });
}
  Widget _actionDelayPreview(
		ControlConditionGroup rule,
		ControlAction action,
	) {
  if (action.type == ControlActionType.delay) {
    return const SizedBox.shrink();
  }
if (action.type == ControlActionType.thresholdTrigger) {
  return Wrap(
    spacing: 4,
    runSpacing: 4,
    children: [
      _counterInputToken(
        action, 'Fre', action.thresholdInputIndex,
        (v) => action.thresholdInputIndex = v,
      ),
      _delayToken(
        'G_T ${action.thresholdGateMs ~/ 1000} sn',
        () async {
          final v = await _duration(
            'Ölçüm penceresi (1–100 sn)',
            action.thresholdGateMs,
            minMs: 1000,
          );
          if (v != null && mounted &&
              v <= 100000 && v % 1000 == 0) {
            setState(() => action.thresholdGateMs = v);
          }
        },
      ),
      _counterValueToken(
  'ON', action.thresholdOn,
  (v) => action.thresholdOn = v,
  min: 0,
  max: 9999,
),
_counterValueToken(
  'OFF', action.thresholdOff,
  (v) => action.thresholdOff = v,
  min: 0,
  max: 9999,
),
    ],
  );
}
if (action.type == ControlActionType.hoursCounter) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _hoursInputToken(
        action, 'EN', action.hoursEnableInputIndex,
        (v) => action.hoursEnableInputIndex = v,
      ),
      const SizedBox(width: 4),
      _hoursInputToken(
        action, 'R', action.resetInputIndex,
        (v) => action.resetInputIndex = v,
      ),
      const SizedBox(width: 4),
      _hoursInputToken(
        action, 'Ral', action.hoursResetAllInputIndex,
        (v) => action.hoursResetAllInputIndex = v,
      ),
			const SizedBox(width: 4),
_hoursTargetToken(action),
    ],
  );
}
  if (action.type == ControlActionType.upDownCounter) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _counterInputToken(
  action, 'CNT', action.counterInputIndex,
  (v) => action.counterInputIndex = v,
),
const SizedBox(width: 4),
_counterInputToken(
  action, 'DIR', action.directionInputIndex,
  (v) => action.directionInputIndex = v,
),
const SizedBox(width: 4),
_counterInputToken(
  action, 'RESET', action.resetInputIndex,
  (v) => action.resetInputIndex = v,
),
        _counterValueToken(
  'START', action.counterStartValue,
  (v) => action.counterStartValue = v,
),
        const SizedBox(width: 4),
        _counterValueToken(
  'ON', action.counterOn,
  (v) => action.counterOn = v,
),
        const SizedBox(width: 4),
        _counterValueToken(
  'OFF', action.counterOff,
  (v) => action.counterOff = v,
),
      ],
    );
  }

  return _timerParameterPreview(rule, action);
}

  // Grouped conditions are editor-only until the runtime converter supports them.
  
void _enableConditionGroups(ControlConditionGroup rule) {
  setState(() {
    if (rule.conditionGroups.isNotEmpty) return;

    rule.conditionGroups.add(
      ConditionSubgroup(
        logicOperator: rule.logicOperator,
        conditions: List<InputCondition>.from(rule.conditions),
        conditionOperators: List<LogicOperator>.generate(
          rule.conditions.length > 0
              ? rule.conditions.length - 1
              : 0,
          (i) => i < rule.conditionOperators.length
              ? rule.conditionOperators[i]
              : rule.logicOperator,
        ),
      ),
    );
  });
}


  Widget _groupedConditions(ControlConditionGroup rule) {
    final allCollapsed = _collapsedConditions.contains(rule.id);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        onTap: () => setState(() => allCollapsed
            ? _collapsedConditions.remove(rule.id)
            : _collapsedConditions.add(rule.id)),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(children: [
            Icon(allCollapsed ? Icons.chevron_right : Icons.expand_more),
            const SizedBox(width: 5),
            Expanded(child: allCollapsed
                ? _allConditionsSummary(rule)
                : const Text('Koşulları kapat',
                    style: TextStyle(fontWeight: FontWeight.w600))),
          ]),
        ),
      ),
      if (!allCollapsed) ...[
      for (var g = 0; g < rule.conditionGroups.length; g++) ...[
        if (g > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: _token(
  _logicText(
    g - 1 < rule.groupOperators.length
        ? rule.groupOperators[g - 1]
        : rule.groupsOperator,
  ),
  () async {
              final v = await _choose<LogicOperator>('...', [
  (LogicOperator.and, 'VE'),
  (LogicOperator.or, 'VEYA'),
  (LogicOperator.xor, 'FARKLIYSA'),
  (LogicOperator.nand, 'TERS VE'),
  (LogicOperator.nor, 'TERS VEYA'),
]);
              if (v != null && mounted) {
  setState(() {
    while (rule.groupOperators.length <
        rule.conditionGroups.length - 1) {
      rule.groupOperators.add(rule.groupsOperator);
    }

    rule.groupOperators[g - 1] = v;
  });
}
            }),
          ),
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => setState(() {
              final key = '${rule.id}:$g';
              _collapsedGroups.contains(key)
                  ? _collapsedGroups.remove(key)
                  : _collapsedGroups.add(key);
            }),
            child: Row(
              children: [
                Icon(
                  _collapsedGroups.contains('${rule.id}:$g')
                      ? Icons.chevron_right
                      : Icons.expand_more,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _collapsedGroups.contains('${rule.id}:$g')
                      ? _conditionSummary(rule.conditionGroups[g])
                      : Text(
                          'GRUP ${g + 1}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        if (rule.conditionGroups.length > 1)
          IconButton(
            tooltip: 'Grubu sil',
            icon: const Icon(Icons.delete_outline, size: 20),
						color: Colors.redAccent,
            visualDensity: VisualDensity.compact,
            onPressed: () {
  setState(() {
    final index = g;

    // Eksik operatörleri eski varsayılanla tamamla.
    while (rule.groupOperators.length <
        rule.conditionGroups.length - 1) {
      rule.groupOperators.add(rule.groupsOperator);
    }

    rule.conditionGroups.removeAt(index);

    if (rule.groupOperators.isNotEmpty) {
      final opIndex = index == 0 ? 0 : index - 1;
      rule.groupOperators.removeAt(opIndex);
    }
  });
},
          ),
      ],
    ),
            if (!_collapsedGroups.contains('${rule.id}:$g')) ...[
  for (var c = 0; c < rule.conditionGroups[g].conditions.length; c++) ...[
    if (c > 0)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: _token(
            _logicText(
  c - 1 < rule.conditionGroups[g].conditionOperators.length
      ? rule.conditionGroups[g].conditionOperators[c - 1]
      : rule.conditionGroups[g].logicOperator,
),
            () async {
              final v = await _choose<LogicOperator>(
                'Grup içi ilişki',
                [
                  (LogicOperator.and, 'VE'),
                  (LogicOperator.or, 'VEYA'),
                  (LogicOperator.xor, 'FARKLIYSA'),
                  (LogicOperator.nand, 'TERS VE'),
                  (LogicOperator.nor, 'TERS VEYA'),
                ],
              );
              if (v != null && mounted) {
                setState(() {
  final group = rule.conditionGroups[g];

  while (group.conditionOperators.length <
      group.conditions.length - 1) {
    group.conditionOperators.add(group.logicOperator);
  }

  group.conditionOperators[c - 1] = v;
});
              }
            },
          ),
        ),
      ),

    Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
						width: 140,
						child: _condition(
							rule,
							rule.conditionGroups[g].conditions[c],
						),
					),
					const SizedBox(width: 8),
          if (rule.conditionGroups[g].conditions.length > 1)
            IconButton(
              tooltip: 'Gruptan koşulu sil',
              icon: const Icon(
                Icons.remove_circle_outline,
                size: 19,
								color: Colors.redAccent,
              ),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
              onPressed: () {
								setState(() {
									final group = rule.conditionGroups[g];
									final index = c;

									if (index < 0 || index >= group.conditions.length) return;

									// Eksik operatörleri eski varsayılanla tamamla.
									while (group.conditionOperators.length <
											group.conditions.length - 1) {
										group.conditionOperators.add(group.logicOperator);
									}

									group.conditions.removeAt(index);

									if (group.conditionOperators.isNotEmpty) {
										final opIndex = index == 0 ? 0 : index - 1;
										group.conditionOperators.removeAt(opIndex);
									}
								});
							},
            ),
        ],
      ),
    ),
  ],

  TextButton.icon(
    onPressed: () {
  setState(() {
    final group = rule.conditionGroups[g];

    if (group.conditions.isNotEmpty) {
      while (group.conditionOperators.length <
          group.conditions.length - 1) {
        group.conditionOperators.add(group.logicOperator);
      }
      group.conditionOperators.add(group.logicOperator);
    }

    group.conditions.add(InputCondition(inputIndex: 1));
  });
},
    icon: const Icon(Icons.add),
    label: const Text('Koşul ekle'),
  ),
],
          ]),
        ),
      ],
      TextButton.icon(
  onPressed: () {
    setState(() {
      // Eksik operatörleri tamamla.
      while (rule.groupOperators.length <
          rule.conditionGroups.length - 1) {
        rule.groupOperators.add(rule.groupsOperator);
      }

      // Yeni grubu mevcut gruplara bağlayan operatör.
      if (rule.conditionGroups.isNotEmpty) {
        rule.groupOperators.add(rule.groupsOperator);
      }

      rule.conditionGroups.add(
        ConditionSubgroup(
          conditions: [InputCondition(inputIndex: 1)],
        ),
      );
    });
  },
  icon: const Icon(Icons.add),
  label: const Text('Yeni grup ekle'),
),
      
      ],
    ]);
  }

String _ruleSummary(ControlConditionGroup rule) {
  final conditions = rule.conditionGroups.isNotEmpty
      ? () {
          final groups = <String>[];

          for (var g = 0; g < rule.conditionGroups.length; g++) {
            final group = rule.conditionGroups[g];

            if (g > 0) {
              final opIndex = g - 1;
              final op = opIndex < rule.groupOperators.length
                  ? rule.groupOperators[opIndex]
                  : rule.groupsOperator;
              groups.add(_logicText(op));
            }

            final parts = <String>[];

            for (var i = 0; i < group.conditions.length; i++) {
              if (i > 0) {
                final opIndex = i - 1;
                final op = opIndex < group.conditionOperators.length
                    ? group.conditionOperators[opIndex]
                    : group.logicOperator;
                parts.add(_logicText(op));
              }

              parts.add(_conditionText(group.conditions[i]));
            }

            groups.add('( ${parts.join(' ')} )');
          }

          return groups.join(' ');
        }()
      : () {
          final parts = <String>[];

          for (var i = 0; i < rule.conditions.length; i++) {
            if (i > 0) {
              final opIndex = i - 1;
              final op = opIndex < rule.conditionOperators.length
                  ? rule.conditionOperators[opIndex]
                  : rule.logicOperator;
              parts.add(_logicText(op));
            }

            parts.add(_conditionText(rule.conditions[i]));
          }

          return parts.join(' ');
        }();

  final actions = rule.actions.map((action) {
    return action.type == ControlActionType.delay
        ? '${_seconds(action.durationMs)} BEKLE'
        : 'Q${action.outputIndex} - ${_timerName(action)}';
  }).join(' → ');

  return 'EĞER\n$conditions\nİSE\n${actions.replaceAll(' → ', '\n')}';
}

  Widget _ruleSection(String label, bool compact, List<Widget> children) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
    if (!compact) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionLabel(label),
        const SizedBox(height: 4),
        content,
      ]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      _sectionLabel(label),
      const SizedBox(width: 6),
      Expanded(child: content),
    ]);
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, 
			children: [
  Row(
  children: [
    Expanded(
      child: InkWell(
        onTap: () => setState(() {
          _collapsedRules.contains(rule.id)
              ? _collapsedRules.remove(rule.id)
              : _collapsedRules.add(rule.id);
        }),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
          child: Row(
            children: [
              Icon(
                _collapsedRules.contains(rule.id)
                    ? Icons.chevron_right
                    : Icons.expand_more,
                color: primary,
                size: 28,
              ),
              const SizedBox(width: 6),
              Text(
                'KURAL ${index + 1}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: primary,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 8),
              if (_collapsedRules.contains(rule.id))
              Expanded(
  child: RichText(
    softWrap: true,
    text: TextSpan(
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 13,
        decoration: TextDecoration.none,
      ),
      children: [
        for (final match in RegExp(r'EĞER|İSE|[\s\S]+?(?=EĞER|İSE|$)')
            .allMatches(_ruleSummary(rule)))
          TextSpan(
            text: match.group(0),
            style: (match.group(0) == 'EĞER' ||
                    match.group(0) == 'İSE')
                ? TextStyle(
                    color: const Color(0xFF22D3EE),
                    fontWeight: FontWeight.bold,
                  )
                : null,
          ),
      ],
    ),
  ),
),
            ],
          ),
        ),
      ),
    ),

    if (!_collapsedRules.contains(rule.id)) ...[
      IconButton(
        tooltip: 'Yukarı',
        onPressed: index == 0 ? null : () => setState(() {
          _rules.removeAt(index);
          _rules.insert(index - 1, rule);
        }),
        icon: const Icon(Icons.arrow_upward, size: 20),
        visualDensity: VisualDensity.compact,
      ),
      IconButton(
        tooltip: 'Aşağı',
        onPressed: index == _rules.length - 1 ? null : () => setState(() {
          _rules.removeAt(index);
          _rules.insert(index + 1, rule);
        }),
        icon: const Icon(Icons.arrow_downward, size: 20),
        visualDensity: VisualDensity.compact,
      ),
    ],

    IconButton(
      tooltip: 'Kuralı sil',
      onPressed: () => setState(() {
        _collapsedRules.remove(rule.id);
        _collapsedConditions.remove(rule.id);
        _rules.remove(rule);
      }),
      icon: const Icon(
        Icons.delete_outline,
        size: 20,
        color: Colors.redAccent,
      ),
    ),
  ],
),
  if (!_collapsedRules.contains(rule.id)) ...[
        
        Divider(height: 1, color: outline.withValues(alpha: 0.3)),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _ruleSection('EĞER', _collapsedConditions.contains(rule.id), [
            if (rule.conditionGroups.isNotEmpty)
              _groupedConditions(rule)
            else ...[
						InkWell(
  onTap: () => setState(() {
    _collapsedConditions.contains(rule.id)
        ? _collapsedConditions.remove(rule.id)
        : _collapsedConditions.add(rule.id);
  }),
  child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    child: Row(
      children: [
        Icon(
          _collapsedConditions.contains(rule.id)
              ? Icons.chevron_right
              : Icons.expand_more,
        ),
        const SizedBox(width: 5),
        Expanded(
          child: _collapsedConditions.contains(rule.id)
              ? Text(
                  rule.conditions.isEmpty
                      ? 'Koşul yok'
                      : rule.conditions
                          .map(_conditionText)
                          .join(' ${_logicText(rule.logicOperator)} '),
                  style: const TextStyle(fontSize: 13),
                )
              : const Text(
                  'Koşulları kapat',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
        ),
      ],
    ),
  ),
),
if (!_collapsedConditions.contains(rule.id)) ...[
            for (var i = 0; i < rule.conditions.length; i++)
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
                    if (i < rule.conditions.length - 1)
										_token(
  switch (
    i < rule.conditionOperators.length
        ? rule.conditionOperators[i]
        : rule.logicOperator
  ) {
    LogicOperator.and => 'VE',
    LogicOperator.or => 'VEYA',
    LogicOperator.xor => 'FARKLIYSA',
    LogicOperator.nand => 'TERS VE',
    LogicOperator.nor => 'TERS VEYA',
    LogicOperator.not => 'DEĞİL',
  },
  () async {
    final v = await _choose<LogicOperator>('', [
      (LogicOperator.and, 'VE'),
      (LogicOperator.or, 'VEYA'),
      (LogicOperator.xor, 'FARKLIYSA'),
      (LogicOperator.nand, 'TERS VE'),
      (LogicOperator.nor, 'TERS VEYA'),
    ]);

    if (v != null) {
      setState(() {
        while (rule.conditionOperators.length <
            rule.conditions.length - 1) {
          rule.conditionOperators.add(rule.logicOperator);
        }

        if (i < rule.conditionOperators.length) {
          rule.conditionOperators[i] = v;
        }
      });
    }
  },
)
										else
  _token('Koşul ekle', () {
    setState(() {
      rule.conditionOperators.add(rule.logicOperator);
      rule.conditions.add(InputCondition(inputIndex: 1));
    });
  }),
                  ]),
                ),
              ),
            if (rule.conditions.isEmpty)
              _token('Koşul ekle', () => setState(() =>
                rule.conditions.add(InputCondition(inputIndex: 1)))),
              TextButton.icon(
                onPressed: () => _enableConditionGroups(rule),
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('Koşulları gruplandır'),
              ),
            ],
						],
            if (rule.onDelayMs > 0)
              Text('${_seconds(rule.onDelayMs)} boyunca koşul sağlanırsa'),
            ]),
            const SizedBox(height: 6),
            Divider(height: 1, color: primary.withValues(alpha: 0.7)),
            const SizedBox(height: 6),
            _ruleSection('İSE', !rule.actions.any(_expandedActions.contains), [
            //const Text('Zaman fonksiyonları: arayüz taslağı; henüz cihaza aktarılabilir değil.', style: TextStyle(fontSize: 11)),
            // Fixed columns keep every action, delay and arrow aligned.
            for (var i = 0; i < rule.actions.length; i++)
							Padding(
								padding: const EdgeInsets.only(bottom: 6),
								child: Builder(
									builder: (context) {
										final action = rule.actions[i];
										final expanded = _expandedActions.contains(action);

										return Container(
											padding: const EdgeInsets.all(8),
											decoration: BoxDecoration(
												border: Border.all(
													color: Theme.of(context).colorScheme.outline,
												),
												borderRadius: BorderRadius.circular(12),
											),
											child: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Row(
      children: [
        InkWell(
          onTap: () => setState(() {
            expanded
                ? _expandedActions.remove(action)
                : _expandedActions.add(action);
          }),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              expanded ? Icons.expand_more : Icons.chevron_right,
            ),
          ),
        ),
        const SizedBox(width: 6),

        if (!expanded)
          Expanded(
            child: InkWell(
              onTap: () => setState(() {
                _expandedActions.add(action);
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  action.type == ControlActionType.delay
                      ? '${_seconds(action.durationMs)} BEKLE'
                      : 'Q${action.outputIndex} · ${_timerName(action)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),

        if (expanded) ...[
          if (action.type != ControlActionType.delay) ...[
            _outputToken('Q${action.outputIndex}', () async {
              final v = await _choose<int>('Çıkış seç', [
                for (var n = 1; n <= 4; n++) (n, 'Q$n'),
              ]);
              if (v != null && mounted) {
                setState(() => action.outputIndex = v);
              }
            }, color: Colors.deepOrange),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: _operationToken(_timerName(action), () async {
                  await _chooseFunction(rule, replace: action);
                }),
              ),
            ),
          ] else
            Expanded(
              child: _token(
                '${_seconds(action.durationMs)} BEKLE',
                () async {
                  final v = await _duration(
                    'Bekleme süresi',
                    action.durationMs,
                  );
                  if (v != null && mounted) {
                    setState(() => action.durationMs = v);
                  }
                },
              ),
            ),

          IconButton(
            tooltip: 'İşlemi sil',
            icon: const Icon(
              Icons.close,
              color: Colors.redAccent,
            ),
            onPressed: () => setState(() {
              _expandedActions.remove(action);
              rule.actions.remove(action);
            }),
          ),
        ],
      ],
    ),

    if (expanded && action.type != ControlActionType.delay) ...[
      const SizedBox(height: 8),
      _actionDelayPreview(rule, action),
    ],
  ],
),
										);
									},
								),
							),
            ]),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Row(children: [
                _token('İşlem ekle', () => _chooseFunction(rule)),
                const SizedBox(width: 8),
                const Expanded(child: Text('Hızlı İşlem Ekle',
  textAlign: TextAlign.end,
  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
              ]),
              childrenPadding: const EdgeInsets.fromLTRB(0, 0, 0, 6),
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _quickFunctionHeading('ZAMAN FONKSİYONLARI'),
                    _quickFunctionGrid(2, [
                      for (final name in _timerFunctions)
                        _quickFunctionButton(name, () => _selectTimer(rule, name)),
                    ]),
                    const Divider(height: 10),
                    _quickFunctionHeading('SAYAÇLAR'),
                    _quickFunctionGrid(3, [
                      for (final item in <(String, String)>[
                        ('upDown', 'İleri / Geri Sayıcı'),
                        ('hours', 'Çalışma Saati Sayacı'),
                        ('threshold', 'Frekans Eşik Tetikleyici'),
                      ])
                        _quickFunctionButton(item.$2,
                          () => _chooseFunction(rule,
                              quickCategory: 'counters', quickSelection: item.$1)),
                    ]),
                    const Divider(height: 10),
                    _quickFunctionHeading('ÇIKIŞ KONTROLÜ'),
                    _quickFunctionGrid(5, [
                      for (final item in <(String, String)>[
                        ('on', 'ON'), ('off', 'OFF'), ('set', 'SET'),
                        ('reset', 'RESET'), ('toggle', 'TOGGLE'),
                      ])
                        _quickFunctionButton(item.$2,
                          () => _chooseFunction(rule,
                              quickCategory: 'outputs', quickSelection: item.$1)),
                    ]),
                  ],
                ),
              ],
              ),
            ),

          ]),
        ),
				],
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
  LogicOperator.nand => 'TERS VE',
  LogicOperator.nor => 'TERS VEYA',
  LogicOperator.not => 'DEĞİL',
};

  // Program is embedded in the URL; no Firebase or additional package needed.
  // Browser counterpart must decode Base64URL and decompress gzip.
  Future<void> _createShareLink() async {
  final user = FirebaseAuth.instance.currentUser;

  if (user == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link oluşturmak için giriş yapmalısınız.'),
      ),
    );
    return;
  }

  _program.name = _name.text.trim();

  final name = _program.name;
  final programJson = jsonEncode(_program.toJson());

  try {
    final doc = FirebaseFirestore.instance
        .collection('sharedPrograms')
        .doc();

    await doc.set({
      'ownerId': user.uid,
      'name': name,
      'programJson': programJson,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 7)),
      ),
    });

    final link = 'https://lynra.app/plc/?id=${doc.id}';

    final shareText = 'LynraControl – Program Paylaşımı\n\n'
        'Program adı: $name\n\n'
        'Bu programı LynraControl akıllı rölenize Bluetooth üzerinden ' 
        'yükleyebilirsiniz. Uygulama yüklemeniz gerekmez.\n\n'
        '$link\n\n'
        'Paylaşım bağlantısı 7 gün geçerlidir.';

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Program Linki'),
        content: SingleChildScrollView(
          child: SelectableText(shareText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Kapat'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: shareText),
              );

              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Paylaşım metni kopyalandı'),
                  ),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Paylaşım Metnini Kopyala'),
          ),
        ],
      ),
    );
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Link oluşturulamadı: $e'),
      ),
    );
  }
}
  void _openSummary() {
    final primary = Theme.of(context).colorScheme.primary;
    final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    final normal = base.copyWith(height: 1.5);
    final keyword = normal.copyWith(color: primary, fontWeight: FontWeight.bold);
    final input = normal.copyWith(color: Colors.blue.shade700, fontWeight: FontWeight.bold);
    final output = normal.copyWith(color: Colors.deepOrange.shade700, fontWeight: FontWeight.bold);
    final heading = normal.copyWith(fontWeight: FontWeight.bold);
    final ruleSpans = <List<InlineSpan>>[];
		var spans = <InlineSpan>[];

		void add(String value, [TextStyle? style]) =>
				spans.add(TextSpan(text: value, style: style ?? normal));

    
if (_rules.isEmpty) add('Henüz kural eklenmedi.');

for (var i = 0; i < _rules.length; i++) {
  spans = <InlineSpan>[];

  final rule = _rules[i];

  add('KURAL ${i + 1}\n', heading);
  add('\n');
  add('EĞER\n', keyword);
  
  void addCondition(InputCondition condition) {
    add('I${condition.inputIndex}', input);
    add(' ${_triggerName(condition.trigger)}');
  }

  if (rule.conditionGroups.isNotEmpty) {
    for (var g = 0; g < rule.conditionGroups.length; g++) {
      final group = rule.conditionGroups[g];

      if (g > 0) {
        final index = g - 1;
        final op = index < rule.groupOperators.length
            ? rule.groupOperators[index]
            : rule.groupsOperator;

        add(' ${_summaryOperator(op)} ', keyword);
      }

      add('( ');

      for (var c = 0; c < group.conditions.length; c++) {
        if (c > 0) {
          final index = c - 1;
          final op = index < group.conditionOperators.length
              ? group.conditionOperators[index]
              : group.logicOperator;

          add(' ${_summaryOperator(op)} ', keyword);
        }

        addCondition(group.conditions[c]);
      }

      add(' )');
    }
  } else if (rule.conditions.isEmpty) {
    add('(koşul yok)');
  } else {
    for (var c = 0; c < rule.conditions.length; c++) {
      if (c > 0) {
        final index = c - 1;
        final op = index < rule.conditionOperators.length
            ? rule.conditionOperators[index]
            : rule.logicOperator;

        add(' ${_summaryOperator(op)} ', keyword);
      }

      addCondition(rule.conditions[c]);
    }
  }


  // A TON waits for the complete logical condition, not each input separately.
  if (rule.onDelayMs > 0) {
    add(', ${_seconds(rule.onDelayMs)} boyunca koşul sağlanırsa');
  }
	add('\n');
  add('\n');
  add('İSE\n', keyword);

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
          ControlActionType.onDelay ||
          ControlActionType.offDelay ||
          ControlActionType.onOffDelay ||
          ControlActionType.wipingRelay ||
          ControlActionType.edgeWipingRelay ||
          ControlActionType.asynchronousPulse ||
          ControlActionType.stairwayTimer ||
          ControlActionType.multipleFunctionTimer ||
          ControlActionType.stopwatchTimer =>
            ' ${_timerName(action)}',

          ControlActionType.setLatch => ' SET',
          ControlActionType.resetLatch => ' RESET',
          ControlActionType.toggleOutput => ' TOGGLE',

          ControlActionType.stairwayOutput =>
            ' MERDİVEN (T ${_seconds(action.durationMs)} / Uyarı ${_seconds(action.stairWarningBeforeMs)} / Kesinti ${_seconds(action.stairWarningOffMs)} / Tekrar ${action.stairRetrigger ? 'Açık' : 'Kapalı'})',

          ControlActionType.multiSwitchOutput =>
            ' ÇOK İŞLEVLİ (T ${_seconds(action.durationMs)} / Uzun ${_seconds(action.multiLongPressMs)} / Uyarı ${_seconds(action.stairWarningBeforeMs)} / Kesinti ${_seconds(action.stairWarningOffMs)})',

          ControlActionType.stopwatchOutput =>
            ' KRONOMETRE (EN: I${rule.conditions.isNotEmpty ? rule.conditions[0].inputIndex : 1} / RESET: I${rule.conditions.length > 1 ? rule.conditions[1].inputIndex : 2} / T ${_seconds(action.durationMs)})',

          ControlActionType.blinkOutput =>
            ' YANIP SÖN (Başlangıç ${_seconds(action.blinkStartDelayMs)} / ON ${action.blinkOnMinMs > 0 ? 'RANDOM ${_seconds(action.blinkOnMinMs)}–${_seconds(action.blinkOnMaxMs)}' : _seconds(action.durationMs)} / OFF ${action.blinkOffMinMs > 0 ? 'RANDOM ${_seconds(action.blinkOffMinMs)}–${_seconds(action.blinkOffMaxMs)}' : _seconds(action.offDurationMs)} / N=${action.blinkCount})',

          _ => action.outputState ? ' ON' : ' OFF',
        });
      }
    }
  }

  // Describe the return behavior only when it is unambiguous.
  final levelConditions = rule.conditions.every((c) =>
      c.trigger == ConditionTrigger.highLevel ||
      c.trigger == ConditionTrigger.lowLevel);

  final outputActions = rule.actions
      .where((a) => a.type == ControlActionType.setOutput)
      .toList();

  final simpleContinuous =
      rule.executionMode == RuleExecutionMode.continuous &&
      levelConditions &&
      rule.actions.length == 1 &&
      outputActions.length == 1;

  if (simpleContinuous) {
    final a = outputActions.first;

    add('\nKoşul artık sağlanmazsa ');

    if (rule.offDelayMs > 0) {
      add('${_seconds(rule.offDelayMs)} sonra ');
    }

    add('Q${a.outputIndex}', output);
    add(a.outputState ? ' OFF olur.' : ' ON olur.');

  } else if (rule.actions.any((a) =>
      a.type == ControlActionType.setLatch ||
      a.type == ControlActionType.resetLatch)) {

    for (final action in rule.actions) {
      if (action.type == ControlActionType.setLatch) {
        add('\nQ${action.outputIndex}', output);
        add(' ON olur ve başka bir komut değiştirmedikçe ON kalır.');
      } else if (action.type == ControlActionType.resetLatch) {
        add('\nQ${action.outputIndex}', output);
        add(' OFF olur ve başka bir komut değiştirmedikçe OFF kalır.');
      }
    }

  } else if (rule.actions.any(
      (a) => a.type == ControlActionType.blinkOutput)) {

    add('\nN=0 ise koşul sağlandığı sürece yanıp söner; N>0 ise tetiklemede belirlenen sayıda darbe üretir.');

  } else if (rule.actions.any(
      (a) => a.type == ControlActionType.toggleOutput)) {

    for (final action in rule.actions) {
      if (action.type == ControlActionType.toggleOutput) {
        add('\nQ${action.outputIndex}', output);
        add(' mevcut durumunun tersine geçer (ON ise OFF, OFF ise ON).');
      }
    }

  } else if (rule.offDelayMs > 0) {
    add('\nOFF gecikmesi: ${_seconds(rule.offDelayMs)}.');
  }

  ruleSpans.add(spans);
}
    Navigator.of(context).push(MaterialPageRoute<void>(
			builder: (ctx) => Scaffold(
				appBar: AppBar(
					title: const Text('Program Özeti'),
				),

				body: Center(
					child: ConstrainedBox(
						constraints: const BoxConstraints(maxWidth: 760),
						child: ListView(
							padding: const EdgeInsets.all(16),
							children: [
								Container(
									padding: const EdgeInsets.all(12),
									decoration: BoxDecoration(
										border: Border.all(
											color: primary.withValues(alpha: 0.75),
											width: 1.2,
										),
										borderRadius: BorderRadius.circular(12),
									),
									child: Column(
										crossAxisAlignment: CrossAxisAlignment.stretch,
										children: [
											if (ruleSpans.isEmpty)
												Padding(
													padding: const EdgeInsets.all(8),
													child: Text(
														'Henüz kural eklenmedi.',
														style: normal,
													),
												),

											for (var i = 0; i < ruleSpans.length; i++) ...[
												if (i > 0)
													const SizedBox(height: 10),

												Container(
													padding: const EdgeInsets.all(14),
													decoration: BoxDecoration(
														border: Border.all(
															color: Colors.grey.withValues(alpha: 0.55),
															width: 1,
														),
														borderRadius: BorderRadius.circular(10),
													),
													child: SelectableText.rich(
														TextSpan(
															style: normal,
															children: ruleSpans[i],
														),
													),
												),
											],
										],
									),
								),
							],
						),
					),
				),

			),
    ));
  }

  String _fingerprint() {
    final data = Map<String, dynamic>.from(_program.toJson());
    data['name'] = _name.text.trim();
    return jsonEncode(data);
  }

  bool get _hasUnsavedChanges =>
      _savedFingerprint == null || _fingerprint() != _savedFingerprint;

  Future<bool> _confirmDiscardChanges() async {
    if (!_hasUnsavedChanges) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kaydedilmemiş değişiklikler'),
        content: const Text('Mevcut programdaki kaydedilmemiş değişiklikler kaybolacak. Devam edilsin mi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Devam Et')),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _openFromDevice() async {
    if (!await _confirmDiscardChanges() || !mounted) return;
    final loaded = await Navigator.of(context).push<ControlProgram>(
      MaterialPageRoute(builder: (_) => const _DeviceProgramReadPage()),
    );
    if (!mounted || loaded == null) return;
    final nextId = loaded.controlBlocks.expand((b) => b.groups)
        .map((r) => int.tryParse(RegExp(r'^rule_(\d+)$').firstMatch(r.id)?.group(1) ?? '') ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);
    setState(() {
      _program = loaded;
			_localProgramId = null;
      _name.text = loaded.name;
      _cloudProgramId = null;
      _savedFingerprint = null;
      _id = nextId;
      _collapsedConditions.clear();
      _collapsedGroups.clear();
      _collapsedRules..clear()..addAll(loaded.controlBlocks.expand((b) => b.groups).map((r) => r.id));
      _expandedActions.clear();
    });
  }

  Future<void> _createReadRequest() async {
    if (_cloudSaving) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uzaktan program almak için giriş yapın.')),
      );
      return;
    }
    setState(() => _cloudSaving = true);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final token = await user.getIdToken();
      if (token == null) throw Exception('Oturum doğrulanamadı.');
      final request = await client.postUrl(Uri.parse(
        'https://us-central1-lynracontrol.cloudfunctions.net/createReadRequest',
      )).timeout(const Duration(seconds: 20));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.write('{}');
      final response = await request.close().timeout(const Duration(seconds: 40));
      final body = await response.transform(utf8.decoder).join()
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception(response.statusCode == 429
            ? 'Çok fazla talep oluşturuldu. Daha sonra tekrar deneyin.'
            : 'Talep oluşturulamadı (HTTP ${response.statusCode}).');
      }
      final data = jsonDecode(body);
      final code = data['code'];
      if (code is! String || !RegExp(r'^\d{6}$').hasMatch(code)) {
        throw const FormatException('Geçersiz okuma kodu.');
      }
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != user.uid) return;
      final shareText = 'LynraControl – Program Okuma Talebi\n\n'
          'https://lynra.app/plc/read/\n\n'
          'Okuma kodu: $code\n\n'
          'Kodu doğrulayın, cihaza bağlanın, programı okuyun ve '
          'Teknisyene Gönder butonuna basın.\n\n'
          'Kod 30 dakika geçerlidir ve tek kullanımlıktır.';
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Uzaktan Program Al'),
          content: SingleChildScrollView(child: SelectableText(shareText)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat')),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: shareText));
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Okuma talebi kopyalandı.')),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text('Kopyala'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Okuma talebi hatası: $e')),
      );
    } finally {
      client.close(force: true);
      if (mounted) setState(() => _cloudSaving = false);
    }
  }
Future<void> _openFromLocal() async {
  if (_cloudSaving) return;

  try {
    var programs = await LocalProgramService.listPrograms();

    if (!mounted) return;

    final selectedId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
  builder: (sheetContext, setSheetState) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: ListTile(
                      title: Text(
                        'Yerel Programlar',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kapat',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(sheetContext),
                  ),
                ],
              ),
              Flexible(
                child: programs.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Kayıtlı program bulunamadı.'),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: programs.length,
                        itemBuilder: (ctx, index) {
                          final item = programs[index];

                          return ListTile(
  leading: const Icon(Icons.description_outlined),
  title: Text(item.name),
  onTap: () => Navigator.pop(
    sheetContext,
    item.id,
  ),
  trailing: Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    IconButton(
      tooltip: 'Yeniden adlandır',
      icon: const Icon(Icons.edit_outlined),
      onPressed: () async {
        var enteredName = item.name;

        final newName = await showDialog<String>(
          context: sheetContext,
          builder: (ctx) => AlertDialog(
            title: const Text('Yeniden adlandır'),
            content: TextFormField(
              initialValue: enteredName,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Program adı',
              ),
              onChanged: (v) => enteredName = v,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () {
                  final name = enteredName.trim();

                  if (name.isNotEmpty) {
                    Navigator.pop(ctx, name);
                  }
                },
                child: const Text('Kaydet'),
              ),
            ],
          ),
        );

        if (newName == null ||
            newName == item.name ||
            !mounted) return;

        try {
          await LocalProgramService.rename(item.id, newName);

          if (!mounted) return;

          if (_localProgramId == item.id) {
            final wasSaved =
                _savedFingerprint == _fingerprint();

            setState(() {
              _program.name = newName;
              _name.text = newName;

              if (wasSaved && _cloudProgramId == null) {
                _savedFingerprint = _fingerprint();
              }
            });
          }

          final updated =
              await LocalProgramService.listPrograms();

          if (!sheetContext.mounted) return;

          setSheetState(() {
            programs = updated;
          });
        } catch (e) {
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Yeniden adlandırma başarısız: $e'),
            ),
          );
        }
      },
    ),
    IconButton(
    tooltip: 'Programı sil',
    icon: const Icon(
      Icons.delete_outline,
      color: Colors.redAccent,
    ),
    onPressed: () async {
      final confirmed = await showDialog<bool>(
        context: sheetContext,
        builder: (ctx) => AlertDialog(
          title: const Text('Programı sil'),
          content: Text(
            '"${item.name}" silinsin mi?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sil'),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;

      try {
        await LocalProgramService.delete(item.id);

        if (!mounted) return;

        if (_localProgramId == item.id) {
          setState(() {
            _localProgramId = null;
            if (_cloudProgramId == null) {
              _savedFingerprint = null;
            }
          });
        }

        if (!sheetContext.mounted) return;

        setSheetState(() {
          programs.removeWhere((p) => p.id == item.id);
        });
      } catch (e) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Silme başarısız: $e')),
        );
      }
    },
      ),
  ],
),
);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
			),
    );

    if (selectedId == null || !mounted) return;

    if (!await _confirmDiscardChanges() || !mounted) return;

    final loaded = await LocalProgramService.load(selectedId);

    if (!mounted) return;

    if (loaded.controlBlocks.isEmpty) {
      throw const FormatException(
        'Programda kontrol bloğu bulunamadı.',
      );
    }

    final nextId = loaded.controlBlocks
        .expand((b) => b.groups)
        .map((r) => int.tryParse(
              RegExp(r'^rule_(\d+)$').firstMatch(r.id)?.group(1) ?? '',
            ) ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);

    setState(() {
      _program = loaded;
      _name.text = loaded.name;

      _localProgramId = selectedId;
      _cloudProgramId = null;

      _id = nextId;

      _collapsedConditions.clear();
      _collapsedGroups.clear();

      _collapsedRules
        ..clear()
        ..addAll(
          loaded.controlBlocks
              .expand((b) => b.groups)
              .map((r) => r.id),
        );

      _expandedActions.clear();
      _savedFingerprint = _fingerprint();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Program yerel kayıttan açıldı.'),
      ),
    );
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Yerel program açılamadı: $e')),
    );
  }
}
  Future<void> _openFromCloud() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Programlarım için önce giriş yapın.')),
      );
      return;
    }
    final collection = FirebaseFirestore.instance
        .collection('users').doc(user.uid).collection('programs');
    try {
      final snapshot = await collection.orderBy('updatedAt', descending: true).get();
      if (!mounted) return;
      var docs = snapshot.docs.toList();
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, refresh) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  const Expanded(child: ListTile(title: Text('Programlarım',
                      style: TextStyle(fontWeight: FontWeight.bold)))),
                  IconButton(tooltip: 'Kapat', icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(sheetContext)),
                ]),
                Flexible(child: docs.isEmpty
                    ? const Padding(padding: EdgeInsets.all(24), child: Text('Kayıtlı program bulunamadı.'))
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: docs.length,
                        itemBuilder: (ctx, index) {
                          final doc = docs[index];
                          final data = doc.data();
                          final name = data['name'] as String? ?? 'Adsız Program';
                          final timestamp = data['updatedAt'];
                          final date = timestamp is Timestamp ? timestamp.toDate() : null;
                          final dateText = date == null ? 'Tarih bilinmiyor'
                              : '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} '
                                '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                          return ListTile(
                            leading: const Icon(Icons.description_outlined),
                            title: Text(name),
                            subtitle: Text('Son değişiklik: $dateText'),
                            onTap: () async {
                              if (!await _confirmDiscardChanges() || !mounted) return;
                              try {
                                final raw = doc.data()['program'];
                                if (raw is! Map) throw const FormatException('Program verisi bulunamadı.');
                                final loaded = ControlProgram.fromJson(Map<String, dynamic>.from(raw));
                                if (loaded.controlBlocks.isEmpty) {
                                  throw const FormatException('Programda kontrol bloğu bulunamadı.');
                                }
                                final nextId = loaded.controlBlocks.expand((b) => b.groups)
                                    .map((r) => int.tryParse(RegExp(r'^rule_(\d+)$').firstMatch(r.id)?.group(1) ?? '') ?? 0)
                                    .fold<int>(0, (a, b) => a > b ? a : b);
                                setState(() {
                                  _program = loaded;
																	_localProgramId = null;
                                  _name.text = loaded.name;
                                  _cloudProgramId = doc.id;
                                  _id = nextId;
                                  _collapsedConditions.clear();
                                  _collapsedGroups.clear();
                                  _collapsedRules..clear()
                                      ..addAll(loaded.controlBlocks.expand((b) => b.groups).map((r) => r.id));
                                  _expandedActions.clear();
                                  _savedFingerprint = _fingerprint();
                                });
                                if (sheetContext.mounted) Navigator.pop(sheetContext);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Program buluttan açıldı.')),
                                );
                              } catch (e) {
                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Program açılamadı: $e')),
                                );
                              }
                            },
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                tooltip: 'Yeniden adlandır',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () async {
                                  var entered = name;
                                  final renamed = await showDialog<String>(
                                    context: sheetContext,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Program adını değiştir'),
                                      content: TextFormField(initialValue: name, autofocus: true,
                                          decoration: const InputDecoration(labelText: 'Program adı'),
                                          onChanged: (v) => entered = v),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
                                        FilledButton(onPressed: () {
                                          if (entered.trim().isNotEmpty) Navigator.pop(ctx, entered.trim());
                                        }, child: const Text('Kaydet')),
                                      ],
                                    ),
                                  );
                                  if (renamed == null || !sheetContext.mounted) return;
                                  try {
                                    final raw = data['program'];
                                    if (raw is! Map) throw const FormatException('Program verisi bulunamadı.');
                                    final updatedProgram = Map<String, dynamic>.from(raw);
                                    updatedProgram['name'] = renamed;
                                    await collection.doc(doc.id).update({
                                      'name': renamed, 'program': updatedProgram,
                                      'updatedAt': FieldValue.serverTimestamp(),
                                    });
                                    if (!sheetContext.mounted) return;
                                    final refreshed = await collection.orderBy('updatedAt', descending: true).get();
                                    if (!sheetContext.mounted) return;
                                    refresh(() => docs = refreshed.docs.toList());
                                    if (_cloudProgramId == doc.id && mounted) {
                                      final wasDirty = _hasUnsavedChanges;
                                      setState(() {
                                        _name.text = renamed;
                                        _program.name = renamed;
                                        if (!wasDirty) _savedFingerprint = _fingerprint();
                                      });
                                    }
                                  } catch (e) {
                                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Ad değiştirilemedi: $e')),
                                    );
                                  }
                                },
                              ),
                              IconButton(
                                tooltip: 'Sil',
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                onPressed: () async {
                                  final confirmed = await showDialog<bool>(
                                    context: sheetContext,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Programı sil'),
                                      content: Text('"$name" buluttan kalıcı olarak silinsin mi?'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
                                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sil')),
                                      ],
                                    ),
                                  );
                                  if (confirmed != true || !sheetContext.mounted) return;
                                  try {
                                    await collection.doc(doc.id).delete();
                                    if (!sheetContext.mounted) return;
                                    refresh(() => docs.removeWhere((d) => d.id == doc.id));
                                    if (_cloudProgramId == doc.id && mounted) {
                                      setState(() { _cloudProgramId = null; _savedFingerprint = null; });
                                    }
                                  } catch (e) {
                                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Program silinemedi: $e')),
                                    );
                                  }
                                },
                              ),
                            ]),
                          );
                        },
                      )),
              ]),
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Programlar yüklenemedi: $e')),
      );
    }
  }

  Future<void> _newProgram() async {
    if (_cloudSaving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yeni Program'),
        content: const Text(
          'Yeni program oluşturulsun mu? Kaydedilmemiş değişiklikler kaybolabilir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yeni Oluştur'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _id = 0;
      _program = ControlProgram(
        name: 'Yeni Program',
        controlBlocks: [ControlBlock(id: 'main', groups: [_makeRule()])],
      );
			_localProgramId = null;
      _name.text = 'Yeni Program';
      _cloudProgramId = null;
      _savedFingerprint = null;
      _collapsedConditions
        ..clear()
        ..add('rule_1');
      _collapsedGroups.clear();
      _collapsedRules
        ..clear()
        ..add('rule_1');
      _expandedActions.clear();
    });
  }

  Future<void> _renameProgram() async {
    var enteredName = _name.text;
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Program adını değiştir'),
        content: TextFormField(
          initialValue: enteredName,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Program adı'),
          onChanged: (value) => enteredName = value,
          onFieldSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(ctx, value.trim());
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () {
              final value = enteredName.trim();
              if (value.isNotEmpty) Navigator.pop(ctx, value);
            },
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
    if (newName == null || !mounted) return;
    setState(() {
      _name.text = newName;
      _program.name = newName;
    });
  }
Future<void> _saveAsToLocal() async {
  if (_cloudSaving) return;

  var enteredName = '${_name.text.trim()} Kopya';

  final newName = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Yerel Farklı Kaydet'),
      content: TextFormField(
        initialValue: enteredName,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Yeni program adı',
        ),
        onChanged: (value) => enteredName = value,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () {
            final value = enteredName.trim();
            if (value.isNotEmpty) {
              Navigator.pop(ctx, value);
            }
          },
          child: const Text('Kaydet'),
        ),
      ],
    ),
  );

  if (newName == null || !mounted) return;

  await _saveToLocal(asNew: true, newName: newName);
}

Future<void> _saveToLocal({
  bool asNew = false,
  String? newName,
}) async {
  if (_cloudSaving) return;

  final name = (newName ?? _name.text).trim();

  if (name.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Önce program adı girin.')),
    );
    return;
  }

  setState(() => _cloudSaving = true);

  try {
    final data = _program.toJson();
    data['name'] = name;

    final snapshot = ControlProgram.fromJson(data);
    final fingerprint = jsonEncode(data);

    final id = await LocalProgramService.save(
      snapshot,
      id: asNew ? null : _localProgramId,
    );

    if (!mounted) return;

    setState(() {
      _localProgramId = id;

      if (asNew) {
        _cloudProgramId = null;
      }

      _program.name = name;
      _name.text = name;
      _savedFingerprint = fingerprint;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Program yerel olarak kaydedildi.'),
      ),
    );
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Yerel kayıt başarısız: $e')),
    );
  } finally {
    if (mounted) {
      setState(() => _cloudSaving = false);
    }
  }
}
  Future<void> _saveAsToCloud() async {
    if (_cloudSaving) return;
    var enteredName = '${_name.text.trim()} Kopya';
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Farklı Kaydet'),
        content: TextFormField(
          initialValue: enteredName,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Yeni program adı'),
          onChanged: (value) => enteredName = value,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () {
              final value = enteredName.trim();
              if (value.isNotEmpty) Navigator.pop(ctx, value);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (newName == null || !mounted) return;
    await _saveToCloud(asNew: true, newName: newName);
  }

  Future<void> _saveToCloud({bool asNew = false, String? newName}) async {
    if (_cloudSaving) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Buluta kaydetmek için Hesabım bölümünden giriş yapın.')),
      );
      return;
    }
    final name = (newName ?? _name.text).trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce program adı girin.')),
      );
      return;
    }
    setState(() => _cloudSaving = true);
    try {
      _program.name = name;
      final collection = FirebaseFirestore.instance
          .collection('users').doc(user.uid).collection('programs');
      final doc = asNew || _cloudProgramId == null
          ? collection.doc()
          : collection.doc(_cloudProgramId);
      final data = <String, dynamic>{
        'name': name,
        'program': _program.toJson(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (asNew || _cloudProgramId == null) {
        data['createdAt'] = FieldValue.serverTimestamp();
				_localProgramId = null;
      }
      await doc.set(data, SetOptions(merge: true));
      _cloudProgramId = doc.id;
      _savedFingerprint = _fingerprint();
      if (asNew) {
        _name.text = name;
        _savedFingerprint = _fingerprint();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Program buluta kaydedildi.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Buluta kayıt başarısız: $e')),
      );
    } finally {
      if (mounted) setState(() => _cloudSaving = false);
    }
  }

  Widget _storageActionRow(String title, List<Widget> buttons) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 2),
          child: Text(title, style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          )),
        ),
        Row(children: [
          for (final button in buttons) Expanded(child: button),
        ]),
      ],
    );
  }

  Widget _storageActionButton(String label, IconData icon, VoidCallback? action) {
    return TextButton(
      onPressed: action,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22),
          const SizedBox(height: 3),
          Text(label, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  void _showJson() {
  _program.name = _name.text.trim();

  final json = const JsonEncoder.withIndent('  ')
      .convert(_program.toJson());

  final compactJson = jsonEncode(_program.toJson());

  debugPrint(
    'PLC JSON SIZE: ${utf8.encode(compactJson).length} bytes',
  );

  final safeName = _program.name
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
      .trim();

  final fileName =
      '${safeName.isEmpty ? "program" : safeName}.json';

  void notify(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Program JSON'),

      content: SingleChildScrollView(
        child: SelectableText(json),
      ),

      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy),
          label: const Text('Kopyala'),
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: json),
            );

            notify('JSON panoya kopyalandı.');
          },
        ),

        TextButton.icon(
          icon: const Icon(Icons.save_outlined),
          label: const Text('Dosyaya Kaydet'),
          onPressed: () async {
            try {
              final path = await FilePicker.saveFile(
                dialogTitle: 'JSON dosyasını kaydet',
                fileName: fileName,
                type: FileType.custom,
                allowedExtensions: ['json'],
                bytes: Uint8List.fromList(utf8.encode(json)),
              );

              if (path == null) return;

              notify('JSON dosyası kaydedildi.');
            } catch (e) {
              notify('JSON kaydedilemedi: $e');
            }
          },
        ),
				if (!Platform.isWindows)
        TextButton.icon(
          icon: const Icon(Icons.share_outlined),
          label: const Text('Paylaş'),
          onPressed: () async {
            try {
              await SharePlus.instance.share(
                ShareParams(
                  files: [
                    XFile.fromData(
                      Uint8List.fromList(utf8.encode(json)),
                      mimeType: 'application/json',
                    ),
                  ],
                  fileNameOverrides: [fileName],
                ),
              );
            } catch (e) {
              notify('JSON paylaşılamadı: $e');
            }
          },
        ),

        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Kapat'),
        ),
      ],
    ),
  );
}
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
			title: const Text('Program Editörü'),
		),
    body: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: ListView(padding: const EdgeInsets.all(14), children: [
        OutlinedButton.icon(
          onPressed: () => setState(() => _programActionsOpen = !_programActionsOpen),
          icon: Icon(_programActionsOpen ? Icons.expand_less : Icons.expand_more),
          label: const Text('Program İşlemleri'),
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        if (_programActionsOpen) ...[
  const SizedBox(height: 6),
  Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.20),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _storageActionRow('YEREL PROGRAMLAR', [
          _storageActionButton('Yeni', Icons.add_circle_outline,
              _cloudSaving ? null : () {
                setState(() => _programActionsOpen = false);
                _newProgram();
              }),
          _storageActionButton(
  'Aç',
  Icons.folder_open_outlined,
  _cloudSaving ? null : () {
    setState(() => _programActionsOpen = false);
    _openFromLocal();
  },
),
          _storageActionButton(
  'Kaydet',
  Icons.save_outlined,
  _cloudSaving ? null : () {
    setState(() => _programActionsOpen = false);
    _saveToLocal();
  },
),
_storageActionButton(
  'Farklı Kaydet',
  Icons.copy_outlined,
  _cloudSaving ? null : () {
    setState(() => _programActionsOpen = false);
    _saveAsToLocal();
  },
),
        ]),
        const Divider(height: 12),
        _storageActionRow('BULUT PROGRAMLARI', [
          _storageActionButton('Programlarım', Icons.folder_open_outlined,
              _cloudSaving ? null : () {
                setState(() => _programActionsOpen = false);
                _openFromCloud();
              }),
          _storageActionButton('Kaydet', Icons.cloud_upload_outlined,
              _cloudSaving ? null : () {
                setState(() => _programActionsOpen = false);
                _saveToCloud();
              }),
          _storageActionButton('Farklı Kaydet', Icons.copy_outlined,
              _cloudSaving ? null : () {
                setState(() => _programActionsOpen = false);
                _saveAsToCloud();
              }),
        ]),
        const Divider(height: 12),
        _storageActionRow('TEST VE İNCELEME', [
          _storageActionButton('Simülasyon', Icons.show_chart, () {
            setState(() => _programActionsOpen = false);
            _program.name = _name.text.trim();
            Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => ProgramSimulatorPage(program: _program),
            ));
          }),
          _storageActionButton('Özet', Icons.description_outlined, () {
            setState(() => _programActionsOpen = false);
            _openSummary();
          }),
          _storageActionButton('JSON', Icons.data_object, () {
            setState(() => _programActionsOpen = false);
            _showJson();
          }),
        ]),
        Row(children: [
          Expanded(child: _storageActionButton('Program Testi', Icons.science_outlined, () {
            setState(() => _programActionsOpen = false);
            _program.name = _name.text.trim();
            Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => ProgramTestPage(program: _program),
            ));
          })),
          Expanded(child: _storageActionButton('Program Şeması', Icons.account_tree_outlined, () {
            setState(() => _programActionsOpen = false);
            _openDiagram();
          })),
        ]),
        const Divider(height: 12),
        _storageActionRow('PROGRAM AKTARIMI', [
          _storageActionButton('Cihazdan Program Al', Icons.bluetooth,
            _cloudSaving ? null : () {
              setState(() => _programActionsOpen = false);
              _openFromDevice();
            }),
          _storageActionButton('Uzaktan Program Al', Icons.cloud_download_outlined,
            _cloudSaving ? null : _createReadRequest),
        ]),
        Row(children: [
          Expanded(child: _storageActionButton('Link Oluştur', Icons.link_outlined, () {
            setState(() => _programActionsOpen = false);
            _createShareLink();
          })),
          Expanded(child: _storageActionButton('Cihaza Gönder', Icons.upload_outlined, () {
            setState(() => _programActionsOpen = false);
            _program.name = _name.text.trim();
            Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => BleConnectionPage(program: _program),
            ));
          })),
        ]),
      ],
    ),
  ),
],
const SizedBox(height: 6),
        const SizedBox(height: 6),
        SizedBox(
          height: 42,
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: constraints.maxWidth * 0.52,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      onTap: _renameProgram,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.edit_outlined, size: 18, color: Colors.cyan),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _name.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.cyan,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Text(
                      'İfadelere dokunarak düzenleyin.',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 2),
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

class _DeviceProgramReadPage extends StatefulWidget {
  const _DeviceProgramReadPage();
  @override
  State<_DeviceProgramReadPage> createState() => _DeviceProgramReadPageState();
}

class _DeviceProgramReadPageState extends State<_DeviceProgramReadPage> {
  final _ble = LynraBleService();
  String? _error;
  @override
  void initState() {
    super.initState();
    _ble.addListener(_refresh);
  }
  void _refresh() { if (mounted) setState(() {}); }
  @override
  void dispose() {
    _ble.removeListener(_refresh);
    super.dispose();
  }
  Future<void> _read() async {
    setState(() => _error = null);
    try {
      final program = await _ble.readProgram();
      if (mounted) Navigator.pop(context, program);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }
  @override
  Widget build(BuildContext context) {
    final busy = _ble.connecting || _ble.commandBusy;
    return Scaffold(
      appBar: AppBar(title: const Text('Cihazdan Program Al')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('BLE: ${_ble.status}'),
        if (!_ble.isConnected) ...[
          FilledButton(onPressed: busy || _ble.scanning ? null : _ble.scan,
            child: Text(_ble.scanning ? 'Aranıyor...' : 'Cihaz Ara')),
          for (final result in _ble.devices)
            RadioListTile<String>(title: const Text('LynraControl'),
              subtitle: Text(result.device.remoteId.toString()),
              value: result.device.remoteId.toString(),
              groupValue: _ble.selectedDevice?.remoteId.toString(),
              onChanged: busy ? null : (_) => _ble.selectDevice(result.device)),
        ],
        OutlinedButton(onPressed: busy || _ble.scanning || (!_ble.isConnected && _ble.selectedDevice == null) ? null : _ble.connectOrDisconnect,
          child: Text(_ble.isConnected ? 'Bağlantıyı Kes' : 'Bağlan')),
        FilledButton(onPressed: _ble.isConnected && !busy ? _read : null,
          child: Text(_ble.commandBusy ? 'Program okunuyor...' : 'Programı Al')),
        if (_error != null) Text(_error!),
      ]),
    );
  }
}
