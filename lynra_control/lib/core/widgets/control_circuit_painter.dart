import 'package:flutter/material.dart';
import '../../models/control_block.dart';

/// Draws one rule using its current conditions and actions.
class ControlCircuitDiagram extends StatelessWidget {
  final ControlConditionGroup group;
  const ControlCircuitDiagram({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    final height = 110.0 + (group.logicOperator == LogicOperator.or
        ? (group.conditions.length - 1).clamp(0, 10) * 28.0 : 0.0);
    return SizedBox(
      height: height,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 360 + (group.logicOperator == LogicOperator.and
              ? (group.conditions.length - 2).clamp(0, 10) * 50.0 : 0.0),
          child: CustomPaint(painter: _CircuitPainter(group, color)),
        ),
      ),
    );
  }
}

class _CircuitPainter extends CustomPainter {
  final ControlConditionGroup group;
  final Color color;
  _CircuitPainter(this.group, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()..color = color..strokeWidth = 1.8..style = PaintingStyle.stroke;
    final y = size.height / 2;
    const left = 16.0;
    final right = size.width - 16;
    canvas.drawLine(const Offset(left, 16), Offset(left, size.height - 16), line);
    canvas.drawLine(Offset(right, 16), Offset(right, size.height - 16), line);
    final conditions = group.conditions;
    if (conditions.isEmpty) return;
    const start = 48.0;
    final end = right - 88;
    if (group.logicOperator == LogicOperator.xor && conditions.length > 1) {
      canvas.drawLine(const Offset(left, 0) + Offset(0, y), Offset(start, y), line);
      canvas.drawLine(Offset(start, y), Offset(start + 24, y), line);
      canvas.drawRect(Rect.fromLTWH(start + 24, y - 23, 75, 46), line);
      _text(canvas, 'XOR', Offset(start + 61.5, y), centered: true);
      _text(canvas, conditions.map((e) => 'I${e.inputIndex}${e.expectedState ? "" : "!"}').join(', '), Offset(start + 61.5, y - 34), centered: true);
      canvas.drawLine(Offset(start + 99, y), Offset(end, y), line);
    } else if (group.logicOperator == LogicOperator.or && conditions.length > 1) {
      final top = y - (conditions.length - 1) * 28 / 2;
      final bottom = top + (conditions.length - 1) * 28;
      canvas.drawLine(Offset(left, y), Offset(start, y), line);
      canvas.drawLine(Offset(start, top), Offset(start, bottom), line);
      for (var i = 0; i < conditions.length; i++) {
        final by = top + i * 28;
        canvas.drawLine(Offset(start, by), Offset(start + 25, by), line);
        _contact(canvas, start + 25, by, conditions[i], line);
        canvas.drawLine(Offset(start + 53, by), Offset(end, by), line);
      }
      canvas.drawLine(Offset(end, top), Offset(end, bottom), line);
    } else {
      canvas.drawLine(Offset(left, y), Offset(start, y), line);
      final spacing = (end - start) / conditions.length;
      for (var i = 0; i < conditions.length; i++) {
        final x = start + i * spacing;
        _contact(canvas, x, y, conditions[i], line);
        canvas.drawLine(Offset(x + 28, y), Offset(start + (i + 1) * spacing, y), line);
      }
    }
    final actions = group.actions;
    final output = actions.where((a) => a.type == ControlActionType.setOutput).toList();
    final label = output.isEmpty ? 'İşlem yok' : output.map((a) => 'Q${a.outputIndex} ${a.outputState ? "ON" : "OFF"}').join(' → ');
    final coilX = right - 55;
    canvas.drawLine(Offset(end, y), Offset(coilX - 14, y), line);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(coilX, y), width: 55, height: 34), const Radius.circular(6)), line);
    _text(canvas, output.length == 1 ? (output.first.outputState ? 'SET' : 'RESET') : 'ACT', Offset(coilX, y), centered: true);
    _text(canvas, label, Offset(coilX, y - 29), centered: true);
    canvas.drawLine(Offset(coilX + 28, y), Offset(right, y), line);
    final delays = actions.where((a) => a.type == ControlActionType.delay).toList();
    if (delays.isNotEmpty) {
      _text(canvas, 'Bekle: ${delays.map((a) => '${a.durationMs / 1000} sn').join(', ')}', Offset(start, size.height - 19));
    }
  }

  void _contact(Canvas canvas, double x, double y, InputCondition c, Paint paint) {
    canvas.drawLine(Offset(x, y - 12), Offset(x, y + 12), paint);
    canvas.drawLine(Offset(x + 28, y - 12), Offset(x + 28, y + 12), paint);
    if (!c.expectedState) canvas.drawLine(Offset(x - 3, y + 15), Offset(x + 31, y - 15), paint);
    _text(canvas, 'I${c.inputIndex}', Offset(x + 14, y - 24), centered: true);
  }

  void _text(Canvas canvas, String text, Offset at, {bool centered = false}) {
    final tp = TextPainter(text: TextSpan(text: text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, centered ? Offset(at.dx - tp.width / 2, at.dy - tp.height / 2) : at);
  }

  @override
  bool shouldRepaint(covariant _CircuitPainter oldDelegate) => true;
}
