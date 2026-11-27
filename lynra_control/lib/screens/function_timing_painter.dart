import 'package:flutter/material.dart';

class FunctionTimingPainter extends CustomPainter {
  const FunctionTimingPainter({required this.edge, required this.th, required this.tl, required this.repeat, required this.falling, required this.scheme, this.wiping = false});
  final bool wiping;
  final bool edge, repeat, falling;
  final int th, tl;
  final ColorScheme scheme;
  @override
  void paint(Canvas canvas, Size size) {
    const left = 48.0;
    final span = size.width - left - 12;
    if (span <= 0) return;
    final end = wiping ? 19 : edge ? 2 + (th + tl) * (repeat ? 2 : 1) + 3 : 10 + tl + 2;
    double x(num t) => left + span * t / end;
    void label(String s, double x, double y, Color color) {
      final p = TextPainter(text: TextSpan(text: s, style: TextStyle(color: color, fontSize: 11)), textDirection: TextDirection.ltr)..layout();
      p.paint(canvas, Offset(x, y));
    }
    void wave(List<(num, bool)> events, double y, Color color) {
      final path = Path();
      var state = events.first.$2;
      path.moveTo(x(0), y - (state ? 25 : 0));
      for (final event in events.skip(1)) {
        path.lineTo(x(event.$1), y - (state ? 25 : 0));
        state = event.$2;
        path.lineTo(x(event.$1), y - (state ? 25 : 0));
      }
      path.lineTo(x(end), y - (state ? 25 : 0));
      canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2.3);
    }
    for (var t = 0; t <= end; t++) {
      canvas.drawLine(Offset(x(t), 12), Offset(x(t), 116), Paint()..color = scheme.outline.withValues(alpha: .2));
      
    }
    label('I1', 0, 25, scheme.onSurface);
    label('Q1', 0, 88, scheme.onSurface);
    final input = wiping ? <(num,bool)>[(0,falling),(2,!falling),(4,falling),(9,!falling),(16,falling)] : edge ? <(num,bool)>[(0, falling),(2,!falling),(3,falling)] : <(num,bool)>[(0,falling),(2,!falling),(10,falling)];
    final output = <(num,bool)>[(0,false)];
    if (wiping) {
      if (th > 0) {
        output.addAll([(2,true),(2+(th < 2 ? th : 2),false),(9,true),(9+th,false)]);
      }
    } else {
    output.add((2+th,true));
    if (!edge) { output.add((10+tl,false)); }
    else if (tl > 0) {
      output.add((2+th+tl,false));
      if (repeat) {
        output.add((2+2*th+tl,true));
        output.add((2+2*th+2*tl,false));
        if (2+3*th+2*tl <= end) output.add((2+3*th+2*tl,true));
      }
    }
    }
    wave(input, 53, scheme.primary);
    wave(output, 116, Colors.greenAccent.shade400);
    final arrowColor = scheme.brightness == Brightness.dark
        ? Colors.amberAccent : Colors.amber.shade900;
    final guide = Paint()..color = scheme.outline..strokeWidth = 1;
    final arrow = Paint()..color = arrowColor..strokeWidth = 1.5;
    void dimension(num start, num finish, String name, double startY, double finishY) {
      final a = x(start), b = x(finish);
      const y = 132.0;
      void dashed(double xx, double from) {
        for (double yy = from; yy < y - 3; yy += 7) {
          canvas.drawLine(Offset(xx, yy), Offset(xx, (yy + 4).clamp(yy, y - 3).toDouble()), guide);
        }
      }
      dashed(a, startY);
      if (b != a) {
        dashed(b, finishY);
        final tip = ((b-a)/3).clamp(0.0, 5.0).toDouble();
        canvas.drawLine(Offset(a,y), Offset(b,y), arrow);
        canvas.drawLine(Offset(a,y), Offset(a+tip,y-tip), arrow);
        canvas.drawLine(Offset(a,y), Offset(a+tip,y+tip), arrow);
        canvas.drawLine(Offset(b,y), Offset(b-tip,y-tip), arrow);
        canvas.drawLine(Offset(b,y), Offset(b-tip,y+tip), arrow);
      } else {
        canvas.drawLine(Offset(a,y-4), Offset(a,y+4), arrow);
      }
      final text = TextPainter(text: TextSpan(text: b == a ? '$name=0' : name,
          style: TextStyle(color: arrowColor, fontSize: 12)), textDirection: TextDirection.ltr)..layout();
      final center = (a+b)/2;
      text.paint(canvas, Offset((center-text.width/2).clamp(0.0, (size.width-text.width).clamp(0.0,size.width)).toDouble(), 141));
    }
    if (wiping) {
      dimension(9, 9+th, 'T', 28, 91);
      dimension(2, 2+(th < 2 ? th : 2), th > 2 ? '< T' : 'T', 28, 91);
      return;
    }
    dimension(2, 2+th, 'TH', 28, 91);
    if (!edge) {
      dimension(10, 10+tl, 'TL', 28, 91);
    } else if (tl > 0) {
      dimension(2+th, 2+th+tl, 'TA', 91, 91);
    } else {
      label('TA=0 (süresiz)', x(2+th), 60, arrowColor);
    }
  }
  @override
  bool shouldRepaint(covariant FunctionTimingPainter oldDelegate) => true;
}
