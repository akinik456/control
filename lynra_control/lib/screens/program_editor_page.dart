import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/control_block.dart';
import '../models/control_program.dart';
import '../core/widgets/control_circuit_painter.dart';
import 'program_simulator_page.dart';
import 'ble_connection_page.dart';

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
    actions: [ControlAction.output()],
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
            ListTile(title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
            ...choices.map((c) => ListTile(
              title: Text(c.$2),
              onTap: () => Navigator.pop(ctx, c.$1),
            )),
          ]),
        ),
      );

  Future<int?> _duration(String title, int currentMs) async {
    var input = (currentMs / 1000).toStringAsFixed(1);
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

  Widget _token(String text, VoidCallback onTap, {Color? color}) =>
      ActionChip(
        label: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
      );

  String _triggerName(ConditionTrigger t) => switch (t) {
    ConditionTrigger.highLevel => 'ON',
    ConditionTrigger.lowLevel => 'OFF',
    ConditionTrigger.risingEdge => 'OFF → ON geçişinde (yükselen kenar)',
    ConditionTrigger.fallingEdge => 'ON → OFF geçişinde (düşen kenar)',
  };

  String _seconds(int ms) => '${(ms / 1000).toStringAsFixed(ms % 1000 == 0 ? 0 : 1)} sn';

  Widget _condition(ControlConditionGroup rule, InputCondition condition) => Wrap(
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
        IconButton(tooltip: 'Koşulu sil', onPressed: () => setState(() => rule.conditions.remove(condition)), icon: const Icon(Icons.close, size: 18)),
    ],
  );

  Widget _action(ControlConditionGroup rule, ControlAction action) => Wrap(
    spacing: 5,
    runSpacing: 3,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      if (action.type == ControlActionType.delay)
        _token('${_seconds(action.durationMs)} BEKLE', () async {
          final v = await _duration('Bekleme süresi', action.durationMs);
          if (v != null) setState(() => action.durationMs = v);
        })
      else ...[
        _token('Q${action.outputIndex}', () async {
          final v = await _choose<int>('Çıkış seç', [for (var i = 1; i <= 4; i++) (i, 'Q$i')]);
          if (v != null) setState(() => action.outputIndex = v);
        }, color: Colors.deepOrange),
        _token(switch (action.type) {
          ControlActionType.setLatch => 'SET',
          ControlActionType.resetLatch => 'RESET',
          ControlActionType.toggleOutput => 'DEĞİŞTİR',
          ControlActionType.blinkOutput => 'YANIP SÖN',
          _ => action.outputState ? 'ON' : 'OFF',
        }, () async {
          final v = await _choose<ControlActionType>('Çıkış işlemi', [
            (ControlActionType.setOutput, 'ON / OFF (koşulu takip et)'),
            (ControlActionType.setLatch, 'SET (ON kal)'),
            (ControlActionType.resetLatch, 'RESET (OFF kal)'),
            (ControlActionType.toggleOutput, 'DEĞİŞTİR (ON/OFF tersine çevir)'),
            (ControlActionType.blinkOutput, 'YANIP SÖN (tekrarla)'),
          ]);
          if (v != null) setState(() {
            action.type = v;
            if (v == ControlActionType.blinkOutput) {
              action.durationMs = 3000;
              action.offDurationMs = 3000;
            }
            if (v == ControlActionType.setLatch) action.outputState = true;
            if (v == ControlActionType.resetLatch) action.outputState = false;
          });
        }),
        if (action.type == ControlActionType.blinkOutput) ...[
          _token('ON ${_seconds(action.durationMs)}', () async {
            final v = await _duration('Yanma süresi', action.durationMs);
            if (v != null && v > 0) setState(() => action.durationMs = v);
          }),
          _token('OFF ${_seconds(action.offDurationMs)}', () async {
            final v = await _duration('Sönme süresi', action.offDurationMs);
            if (v != null && v > 0) setState(() => action.offDurationMs = v);
          }),
        ],
        if (action.type == ControlActionType.setOutput)
          _token('Değiştir', () => setState(() => action.outputState = !action.outputState)),
      ],
      IconButton(tooltip: 'İşlemi sil', onPressed: () => setState(() => rule.actions.remove(action)), icon: const Icon(Icons.close, size: 18)),
    ],
  );

  Widget _ruleEditor(ControlConditionGroup rule, int index) {
    return Padding(
      key: ValueKey(rule.id),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('KURAL ${index + 1}', style: Theme.of(context).textTheme.labelMedium),
          const Spacer(),
          IconButton(tooltip: 'Yukarı', onPressed: index == 0 ? null : () => setState(() {
            _rules.removeAt(index); _rules.insert(index - 1, rule);
          }), icon: const Icon(Icons.arrow_upward, size: 19)),
          IconButton(tooltip: 'Aşağı', onPressed: index == _rules.length - 1 ? null : () => setState(() {
            _rules.removeAt(index); _rules.insert(index + 1, rule);
          }), icon: const Icon(Icons.arrow_downward, size: 19)),
          IconButton(tooltip: 'Kuralı sil', onPressed: () => setState(() => _rules.remove(rule)), icon: const Icon(Icons.delete_outline, size: 19)),
        ]),
        Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('EĞER', style: TextStyle(fontWeight: FontWeight.bold)),
          for (var i = 0; i < rule.conditions.length; i++) ...[
            if (i > 0) _token(switch (rule.logicOperator) {
              LogicOperator.and => 'VE', LogicOperator.or => 'VEYA', LogicOperator.xor => 'FARKLIYSA',
            }, () async {
              final v = await _choose<LogicOperator>('Bağlaç', [
                (LogicOperator.and, 'VE'), (LogicOperator.or, 'VEYA'), (LogicOperator.xor, 'FARKLIYSA'),
              ]);
              if (v != null) setState(() => rule.logicOperator = v);
            }),
            _condition(rule, rule.conditions[i]),
          ],
          _token('+ Koşul', () => setState(() => rule.conditions.add(InputCondition(inputIndex: 1)))),
          if (rule.onDelayMs > 0) Text(' ${_seconds(rule.onDelayMs)} boyunca koşul sağlanırsa'),
        ]),
				const Divider(height: 16, thickness: 1,color: Color(0xFF00BCD4)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('İSE', style: TextStyle(fontWeight: FontWeight.bold)),
          for (var i = 0; i < rule.actions.length; i++) ...[
            if (i > 0) const Text('→'),
            _action(rule, rule.actions[i]),
          ],
          _token('+ İşlem', () async {
            final v = await _choose<ControlActionType>('İşlem ekle', [
              (ControlActionType.setOutput, 'Çıkış ON / OFF'),
              (ControlActionType.setLatch, 'Çıkış SET'),
              (ControlActionType.resetLatch, 'Çıkış RESET'),
              (ControlActionType.toggleOutput, 'Çıkış DEĞİŞTİR'),
              (ControlActionType.blinkOutput, 'Çıkış YANIP SÖN'),
              (ControlActionType.delay, 'Bekle'),
            ]);
            if (v != null) setState(() => rule.actions.add(
              switch (v) {
                ControlActionType.delay => ControlAction.delay(),
                ControlActionType.setLatch => ControlAction.set(),
                ControlActionType.resetLatch => ControlAction.reset(),
                ControlActionType.toggleOutput => ControlAction.toggle(),
                ControlActionType.blinkOutput => ControlAction.blink(),
                _ => ControlAction.output(),
              },
            ));
          }),
        ]),
				const Divider(height: 16, thickness: 1,color: Color(0xFF00BCD4)),
        const SizedBox(height: 4),
        Wrap(spacing: 5, crossAxisAlignment: WrapCrossAlignment.center, children: [
           _token(rule.runPolicy == RuleRunPolicy.once ? '1 kez çalış' : 'Tekrarla (koşullar sağlanıyorsa)', () async {
             final v = await _choose<RuleRunPolicy>('Çalışma şekli', [
               (RuleRunPolicy.once, '1 kez çalış'),
               (RuleRunPolicy.repeat, 'Tekrarla (koşullar sağlanıyorsa)'),
             ]);
             if (v != null) setState(() => rule.runPolicy = v);
           }),
          _token(rule.onDelayMs > 0 ? 'ON için ${_seconds(rule.onDelayMs)} bekle' : 'ON gecikmesi ekle', () async {
            final v = await _duration('ON gecikmesi (TON)', rule.onDelayMs);
            if (v != null) setState(() => rule.onDelayMs = v);
          }),
          _token(rule.offDelayMs > 0 ? 'OFF için ${_seconds(rule.offDelayMs)} bekle' : 'OFF gecikmesi ekle', () async {
            final v = await _duration('OFF gecikmesi (TOF)', rule.offDelayMs);
            if (v != null) setState(() => rule.offDelayMs = v);
          }),
        ]),
        const Divider(height: 24),
				const Divider(height: 16, thickness: 1,color: Color(0xFF00BCD4)),
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
  };

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
        for (var c = 0; c < rule.conditions.length; c++) {
          if (c > 0) add(' ${_summaryOperator(rule.logicOperator)} ', keyword);
          final condition = rule.conditions[c];
          add('I${condition.inputIndex}', input);
          add(' ${_triggerName(condition.trigger)}');
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
              ControlActionType.setLatch => ' SET',
              ControlActionType.resetLatch => ' RESET',
              ControlActionType.toggleOutput => ' DEĞİŞTİR',
              ControlActionType.blinkOutput => ' YANIP SÖN (${_seconds(action.durationMs)} ON / ${_seconds(action.offDurationMs)} OFF)',
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
        add('\nKoşul sağlandığı sürece yanıp söner; koşul bittiğinde OFF olur.');
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
            tooltip: 'Program Şeması',
            icon: const Icon(Icons.account_tree_outlined),
            onPressed: () {
              Navigator.of(ctx).pop();
              _openDiagram();
            },
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
      IconButton(tooltip: 'Program Özeti', onPressed: _openSummary, icon: const Icon(Icons.description_outlined)),
      IconButton(tooltip: 'Program JSON', onPressed: _showJson, icon: const Icon(Icons.data_object)),
    ]),
    body: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _name, decoration: const InputDecoration(
          labelText: 'Program adı', border: OutlineInputBorder(),
        )),
        const SizedBox(height: 16),
        const Text('İfadelere dokunarak düzenleyin.', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
        for (var i = 0; i < _rules.length; i++) _ruleEditor(_rules[i], i),
        FilledButton.icon(onPressed: () => setState(() => _rules.add(_makeRule())),
          icon: const Icon(Icons.add), label: const Text('Yeni kural ekle')),
      ]),
    )),
  );
}
