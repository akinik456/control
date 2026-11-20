import 'package:flutter/material.dart';
import '../../models/control_block.dart';

/// Read-only FBD preview. Operators follow the editor's left-to-right order.
class ControlCircuitDiagram extends StatefulWidget {
  final ControlConditionGroup group;
  const ControlCircuitDiagram({super.key, required this.group});

  @override
  State<ControlCircuitDiagram> createState() => _ControlCircuitDiagramState();
}

class _ControlCircuitDiagramState extends State<ControlCircuitDiagram> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tree = _buildExpression(widget.group);
    final leaves = tree?.leaves ?? 1;
    final depth = tree?.depth ?? 1;
    // Final logic gate + short wire (24 px) + 88 px action block.
    final width = depth * 130.0 + 100.0;
    final height = (leaves * 66.0 + 75.0).clamp(210.0, double.infinity);
    final colors = Theme.of(context).colorScheme;

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
									height: height,
                  child: CustomPaint(
                    painter: _FbdPainter(tree, colors.onSurface, colors.primary),
                  ),
                ),
              ),
              if (width > constraints.maxWidth + 1)
  Align(
    alignment: Alignment.bottomRight,
    child: IconButton(
      icon: Icon(
        Icons.keyboard_double_arrow_right,
        color: colors.onSurface.withValues(alpha: 0.35),
        size: 30,
      ),
      onPressed: () {
        if (!_scrollController.hasClients) return;

        final position = _scrollController.position;
        final target = (_scrollController.offset + 180.0)
            .clamp(0.0, position.maxScrollExtent)
            .toDouble();

        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      },
    ),
  ),
            ],
          );
        },
      ),
    );
  }
}

class _Node {
  final String text;
  final _Node? left;
  final _Node? right;
  _Node(this.text, [this.left, this.right]);
  int get leaves => left == null ? 1 : left!.leaves + (right?.leaves ?? 0);
  int get depth {
  final l = left?.depth ?? 0;
  final r = right?.depth ?? 0;
  return 1 + (l > r ? l : r);
}
}

String _operatorName(LogicOperator op) => switch (op) {
  LogicOperator.and => 'VE',
  LogicOperator.or => 'VEYA',
  LogicOperator.xor => 'FARKLIYSA',
  LogicOperator.nand => 'TERS VE',
  LogicOperator.nor => 'TERS VEYA',
  _ => 'DEĞİL',
};

_Node? _conditionChain(List<InputCondition> conditions,
    List<LogicOperator> operators, LogicOperator fallback) {
  if (conditions.isEmpty) return null;
  _Node leaf(InputCondition c) {
    final input = _Node('I${c.inputIndex} ${c.expectedState ? "ON" : "OFF"}');
    return c.negated ? _Node('DEĞİL', input) : input;
  }
  var result = leaf(conditions.first);
  for (var i = 1; i < conditions.length; i++) {
    final op = i - 1 < operators.length ? operators[i - 1] : fallback;
    result = _Node(_operatorName(op), result, leaf(conditions[i]));
  }
  return result;
}

_Node? _buildExpression(ControlConditionGroup rule) {
  if (rule.conditionGroups.isEmpty) {
    return _conditionChain(rule.conditions, rule.conditionOperators, rule.logicOperator);
  }
  _Node? result;
  for (var i = 0; i < rule.conditionGroups.length; i++) {
    final subgroup = rule.conditionGroups[i];
    var current = _conditionChain(
      subgroup.conditions, subgroup.conditionOperators, subgroup.logicOperator);
    if (current == null) continue;
    if (subgroup.negated) current = _Node('DEĞİL', current);
    if (result == null) {
      result = current;
    } else {
      final opIndex = i - 1;
      final op = opIndex < rule.groupOperators.length
          ? rule.groupOperators[opIndex] : rule.groupsOperator;
      result = _Node(_operatorName(op), result, current);
    }
  }
  return result;
}

class _FbdPainter extends CustomPainter {
  final _Node? root;
  final Color ink;
  final Color accent;
  _FbdPainter(this.root, this.ink, this.accent);

  void _label(Canvas canvas, String text, Offset center, {Color? color}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(
        color: color ?? ink, fontSize: 12, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  void _block(Canvas canvas, Rect rect, String text, Paint stroke) {
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(7)), stroke);
    _label(canvas, text, rect.center, color: accent);
  }

  @override
  void paint(Canvas canvas, Size size) {
	debugPrint('FBD PAINT START');
debugPrint('FBD ROOT DEPTH: ${root?.depth}');
debugPrint('FBD ROOT LEAVES: ${root?.leaves}');
    final wire = Paint()..color = ink..strokeWidth = 1.5..style = PaintingStyle.stroke;
    final border = Paint()..color = accent..strokeWidth = 1.5..style = PaintingStyle.stroke;
    if (root == null) {
      _label(canvas, 'Koşul yok', Offset(size.width / 2, size.height / 2));
      return;
    }
    var leafIndex = 0;
    final maxDepth = root!.depth;
    // Each subtree receives a distinct vertical interval; no overlapping blocks.
    Offset draw(_Node node, int depth) {
      final x = 12.0 + (depth - 1) * 130.0;
      if (node.left == null) {
        final y = 40.0 + leafIndex++ * 66.0;
        _block(canvas, Rect.fromCenter(center: Offset(x + 45, y), width: 90, height: 36), node.text, border);
        return Offset(x + 90, y);
      }
      final leftEnd = draw(node.left!, depth - 1);
      final rightEnd = node.right == null ? null : draw(node.right!, depth - 1);
      final y = rightEnd == null ? leftEnd.dy : (leftEnd.dy + rightEnd.dy) / 2;
      final gate = Rect.fromCenter(center: Offset(x + 45, y), width: 90, height: 46);
      void connect(Offset source, double targetY) {
        final elbowX = x - 12.0;
        canvas.drawLine(source, Offset(elbowX, source.dy), wire);
        canvas.drawLine(Offset(elbowX, source.dy), Offset(elbowX, targetY), wire);
        canvas.drawLine(Offset(elbowX, targetY), Offset(x, targetY), wire);
      }
      connect(leftEnd, rightEnd == null ? y : y - 12);
      if (rightEnd != null) connect(rightEnd, y + 12);
      _block(canvas, gate, node.text, border);
      return Offset(gate.right, y);
    }
		debugPrint('FBD BEFORE DRAW');
    final end = draw(root!, maxDepth);
		debugPrint('FBD AFTER DRAW');
    final actionX = end.dx + 24.0;
    canvas.drawLine(end, Offset(actionX, end.dy), wire);
    _block(canvas, Rect.fromLTWH(actionX, end.dy - 18, 88, 36), 'İŞLEM', border);
    //_label(canvas, 'İşlem blokları sonraki aşama', Offset(size.width / 2, size.height - 22));
		debugPrint('FBD PAINT COMPLETE');
  }

  @override
  bool shouldRepaint(covariant _FbdPainter oldDelegate) => true;
}
