import 'package:flutter/material.dart';

class FunctionTimingPainter extends CustomPainter {
  const FunctionTimingPainter({required this.edge, required this.th, required this.tl, required this.repeat, required this.falling, required this.scheme, this.wiping = false, this.edgeWiping = false, this.n = 2});
  final bool wiping, edgeWiping;
  final int n;
  final bool edge, repeat, falling;
  final int th, tl;
  final ColorScheme scheme;
  @override
  void paint(Canvas canvas, Size size) {
    const left = 48.0;
    final span = size.width - left - 12;
    if (span <= 0) return;
    final pulses = n == 0 ? 3 : n;
    final end = edgeWiping ? 2 + (th + tl) * pulses + (repeat ? tl + th / 2 : 2) : wiping ? 19 : edge ? 2 + (th + tl) * (repeat ? 2 : 1) + 3 : 10 + tl + 2;
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
    if (edgeWiping) {
      for (var i = 0; i < pulses; i++) {
        final start = 2 + i * (th + tl) + tl;
        output.addAll([(start, true), (start + th, false)]);
      }
      if (repeat) output.add((2 + pulses * (th + tl) + tl, true));
    } else if (wiping) {
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
    if (edgeWiping) {
      dimension(2, 2+tl, 'TL', 28, 91);
      dimension(2+tl, 2+tl+th, 'TH', 91, 91);
      return;
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

class ExtraTimerPainter extends CustomPainter {
  const ExtraTimerPainter({required this.kind,required this.th,required this.tl,required this.t,required this.warning,required this.cut,required this.falling,required this.longPress,required this.scheme});
  final int kind,th,tl,t,warning,cut;
  final bool falling,longPress;
  final ColorScheme scheme;
  @override
  void paint(Canvas canvas,Size size){
    if(size.width<=60)return;
    final input=<(num,bool)>[(0,falling)];
    final output=<(num,bool)>[(0,false)];
    final reset=<(num,bool)>[(0,false)];
    final dims=<(num,num,String,int)>[];
    num end=20;
    if(kind==1){
      final stop=2+2*(th+tl)+th/2;
      end=stop+2;
      input.addAll([(2,!falling),(stop,falling)]);
      for(var i=0;i<3;i++){
        final a=2+i*(th+tl);
        output.add((a,true));
        output.add((a+th<stop?a+th:stop,false));
      }
      dims.addAll([(2,2+th,'TH',0),(2+th,2+th+tl,'TL',0)]);
    }else if(kind==4){
      final first=t/2;
      final resume=2+first+2;
      final reached=resume+t-first;
      final r=reached+3;
      end=r+3;
      input.addAll([(2,true),(2+first,false),(resume,true),(reached+1,false)]);
      output.addAll([(reached,true),(r,false)]);
      reset.addAll([(r,true),(r+1,false)]);
      dims.addAll([(2,2+first,'T/2',0),(resume,reached,'T/2',0)]);
    }else{
      final press=kind==3?(longPress?tl+1:tl/2):1;
      final release=2+press;
      input.addAll([(2,!falling),(release,falling)]);
      output.add((2,true));
      if(kind==3) dims.add((2,release,longPress?'≥ TL':'< TL',1));
      if(kind==3&&longPress){
        final next=release+4;
        input.addAll([(next,true),(next+1,false)]);
        output.add((next+1,false));
        end=next+3;
      }else{
        final start=kind==2?2:release;
        final finish=start+t;
        final w=finish-warning;
        if(warning>0&&cut>0){
          output.add((w,false));
          if(w+cut<finish)output.add((w+cut,true));
          dims.addAll([(w,finish,'T!',1),(w,w+cut,'T!L',2)]);
        }
        output.add((finish,false));
        dims.add((start,finish,'T',0));
        end=finish+2;
      }
    }
    double x(num v)=>48+(size.width-60)*v/end;
    void label(String s,double xx,double yy,Color color){
      final tp=TextPainter(text:TextSpan(text:s,style:TextStyle(color:color,fontSize:11)),textDirection:TextDirection.ltr)..layout();
      tp.paint(canvas,Offset(xx.clamp(0.0,(size.width-tp.width).clamp(0.0,size.width)).toDouble(),yy));
    }
    void wave(List<(num,bool)> events,double y,Color color){
      var state=events.first.$2;
      final path=Path()..moveTo(x(0),y-(state?25:0));
      for(final e in events.skip(1)){
        path.lineTo(x(e.$1),y-(state?25:0));state=e.$2;path.lineTo(x(e.$1),y-(state?25:0));
      }
      path.lineTo(x(end),y-(state?25:0));
      canvas.drawPath(path,Paint()..color=color..style=PaintingStyle.stroke..strokeWidth=2.3);
    }
    final qy=kind==4?156.0:116.0;
    for(var i=0;i<=end;i++)canvas.drawLine(Offset(x(i),12),Offset(x(i),qy),Paint()..color=scheme.outline.withValues(alpha:.2));
    label('I1',0,25,scheme.onSurface);wave(input,53,scheme.primary);
    if(kind==4){label('I2 R',0,79,scheme.onSurface);wave(reset,103,scheme.primary);}
    label('Q1',0,qy-28,scheme.onSurface);wave(output,qy,Colors.greenAccent.shade400);
    final color=scheme.brightness==Brightness.dark?Colors.amberAccent:Colors.amber.shade900;
    final pen=Paint()..color=color..strokeWidth=1.5;
    for(final d in dims){
      final a=x(d.$1),b=x(d.$2),y=qy+13+d.$4*22;
      for(final xx in [a,b]){for(double yy=qy-25;yy<y-3;yy+=7){canvas.drawLine(Offset(xx,yy),Offset(xx,yy+3),Paint()..color=scheme.outline);}}
      final tip=((b-a)/3).clamp(0.0,4.0).toDouble();
      canvas.drawLine(Offset(a,y),Offset(b,y),pen);
      for(final sign in [-1,1]){canvas.drawLine(Offset(a,y),Offset(a+tip,y+sign*tip),pen);canvas.drawLine(Offset(b,y),Offset(b-tip,y+sign*tip),pen);}
      label(d.$3,(a+b)/2-d.$3.length*3,y+4,color);
    }
  }
  @override
  bool shouldRepaint(covariant ExtraTimerPainter oldDelegate)=>true;
}
