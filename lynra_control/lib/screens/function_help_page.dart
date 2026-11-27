import 'package:flutter/material.dart';
import 'function_help_data.dart';
import 'function_timing_painter.dart';

class FunctionHelpPage extends StatefulWidget {
  const FunctionHelpPage({super.key, this.wiping = false, this.edgeWiping = false, this.extra = 0});
  final int extra;
  final bool wiping, edgeWiping;
  @override
  State<FunctionHelpPage> createState() => _FunctionHelpPageState();
}
class _FunctionHelpPageState extends State<FunctionHelpPage> {
  late int condition = widget.edgeWiping ? 2 : 0;
  int n = 2;
  bool repeat = false;
  bool get edge => condition >= 2;
  bool get falling => condition == 1 || condition == 3;
  int th = 2, tl = 3, t = 3;
  @override
  Widget build(BuildContext context) {
    if (widget.extra != 0) return ExtraTimerHelp(kind: widget.extra);
    final scheme = Theme.of(context).colorScheme;
    Widget heading(String text) => Padding(padding: const EdgeInsets.only(top: 18, bottom: 6), child: Text(text, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold, fontSize: 16)));
    Widget param(String title, String text) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 3), Text(text)]));
    Widget time(String title, int value, ValueChanged<int> change) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('$title: $value sn'), Slider(value: value.toDouble(), min: widget.edgeWiping || (edge && repeat) ? 1 : 0, max: 5, divisions: widget.edgeWiping || (edge && repeat) ? 4 : 5, label: '$value sn', onChanged: (v) => setState(() => change(v.round())))]);
    return Scaffold(
      appBar: AppBar(title: Text(widget.edgeWiping ? FunctionHelpData.edgeWipingRelay : widget.wiping ? FunctionHelpData.wipingRelay : FunctionHelpData.onOffDelay, style: const TextStyle(fontSize: 17))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        heading('Giriş koşulu'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final item in (widget.edgeWiping ? const ['I1 ↑ (Yükselen kenar)', 'I1 ↓ (Düşen kenar)'] : widget.wiping ? const ['I1 = ON', 'I1 = OFF'] : const ['I1 = ON', 'I1 = OFF', 'I1 ↑ (Yükselen kenar)', 'I1 ↓ (Düşen kenar)']).asMap().entries)
              ChoiceChip(
                label: Text(item.value),
                selected: condition == item.key + (widget.edgeWiping ? 2 : 0),
                onSelected: (_) => setState(() {
                  condition = item.key + (widget.edgeWiping ? 2 : 0);
                  if (!edge) repeat = false;
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(edge ? 'EDGE' : 'LEVEL', style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(widget.edgeWiping ? FunctionHelpData.edgeWiping : widget.wiping ? FunctionHelpData.wipingLevel : (edge ? FunctionHelpData.edge : FunctionHelpData.level)),
        if (!widget.wiping && !widget.edgeWiping)
        Text(const [
          'I1 ON olduğunda TH, OFF olduğunda TL başlar.',
          'I1 OFF olduğunda TH, ON olduğunda TL başlar.',
          'I1 yükselen kenarında TH başlar.',
          'I1 düşen kenarında TH başlar.',
        ][condition]),
        heading('Fonksiyonu keşfet'),
        const Text('Örnek değerleri değiştirerek zaman diyagramını inceleyin. Bu değerler programa aktarılmaz.'),
        if (widget.edgeWiping) ...[
          time('TH', th, (v) => th = v),
          time('TL', tl, (v) => tl = v),
          Text('N: ${n == 0 ? "Sınırsız" : n.toString()}'),
          Slider(value: n.toDouble(), min: 0, max: 4, divisions: 4, onChanged: (v) => setState(() { n = v.round(); if (n == 0) repeat = true; })),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('TEKRARLA'), value: repeat, onChanged: n == 0 ? null : (v) => setState(() => repeat = v)),
          SizedBox(height: 165, child: CustomPaint(painter: FunctionTimingPainter(edge: true, th: th, tl: tl, repeat: repeat, falling: falling, scheme: scheme, edgeWiping: true, n: n))),
          Text(repeat ? 'Darbe dizisi devam eder. Grafikte ilk darbeler gösterilmiştir.' : 'Darbe dizisi N darbe sonunda tamamlanır.'),
          const Text('Örnek diyagram: sabit süreler; RESET, yeniden tetikleme ve sanal başlangıç uygulanmamıştır.', style: TextStyle(fontSize: 12)),
          heading('Parametreler'),
          param('TH – Darbe süresi (0,001–86400 sn)', 'Çıkışın ON kalacağı süre.'),
          param('TL – Ara süresi (0,001–86400 sn)', 'İlk darbeden önce ve darbeler arasında çıkışın OFF kalacağı süre.'),
          param('N – Darbe sayısı (0–255)', 'Bir dizideki darbe sayısı. 0 = sınırsız.'),
          const Text('Zaman ayar çözünürlüğü: 1 ms (0,001 sn).'),
          param('TEKRARLA', FunctionHelpData.edgeWipingRepeat),
          param('YENİDEN TETİKLE', FunctionHelpData.edgeWipingRetrigger),
          param('RESET', FunctionHelpData.edgeWipingReset),
          param('TH / TL – SABİT / RASTGELE', FunctionHelpData.edgeWipingRandom),
          param('SANAL GİRİŞ', FunctionHelpData.edgeWipingVirtual),
        ] else if (widget.wiping) ...[
          time('T', t, (v) => t = v),
          SizedBox(height: 165, child: CustomPaint(painter: FunctionTimingPainter(edge: false, th: t, tl: 0, repeat: false, falling: falling, scheme: scheme, wiping: true))),
          const Text('Örnek diyagram: sanal başlangıç uygulanmamıştır.', style: TextStyle(fontSize: 12)),
          heading('Parametreler'),
          param('T – Darbe süresi (0–86400 sn)', 'Çıkışın ON kalabileceği en uzun süre. Koşul daha önce yanlış olursa çıkış hemen OFF olur. T sıfır ise çıkış ON olmaz.'),
          const Text('Zaman ayar çözünürlüğü: 1 ms (0,001 sn).'),
          param('SANAL GİRİŞ', FunctionHelpData.wipingVirtual),
        ] else ...[
        if (edge) ...[
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('TEKRARLA'), value: repeat, onChanged: (v) => setState(() {repeat = v; if (v) {if (th == 0) th = 1; if (tl == 0) tl = 1;}})),
        ],
        time('TH', th, (v) => th = v), time(edge ? 'TA' : 'TL', tl, (v) => tl = v),
        SizedBox(height: 165, child: CustomPaint(painter: FunctionTimingPainter(edge: edge, th: th, tl: tl, repeat: repeat, falling: falling, scheme: scheme))),
        const Text('Örnek diyagram: RESET ve sanal başlangıç uygulanmamıştır.', style: TextStyle(fontSize: 12)),
        heading('Parametreler'),
param('TH – Açma gecikmesi (0–86400 sn)',
    'Çıkışın ON olması için beklenecek süre. Sıfır ise bekleme yapılmaz.'),
if (edge)
  param('TA – Aktif kalma süresi (0–86400 sn)',
      'Çıkışın ON kalacağı süre. Sıfır ise süreye bağlı kapanma olmaz.')
else
  param('TL – Kapanma gecikmesi (0–86400 sn)',
      'Koşul yanlış olduğunda çıkışın OFF olması için beklenecek süre. Sıfır ise bekleme yapılmaz.'),
const Text('Zaman ayar çözünürlüğü: 1 ms (0,001 sn).'),
if (edge)
  const Text('TEKRARLA açıkken TH ve TA en az 1 sn olmalıdır.'),        param('RESET', FunctionHelpData.reset), param('SANAL GİRİŞ', FunctionHelpData.virtual),
        if (edge) ...[param('TEKRARLA', FunctionHelpData.repeat), param('YENİDEN TETİKLE', FunctionHelpData.retrigger)],
        ],
      ]),
      bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç'))), const SizedBox(width: 12), Expanded(child: FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('İşlemi Ekle')))]))),
    );
  }
}

class ExtraTimerHelp extends StatefulWidget {
  const ExtraTimerHelp({super.key, required this.kind});
  final int kind;
  @override
  State<ExtraTimerHelp> createState() => _ExtraTimerHelpState();
}
class _ExtraTimerHelpState extends State<ExtraTimerHelp> {
  int th=2, tl=3, t=8, warning=3, cut=1;
  bool falling=false, longPress=false;
  @override
  Widget build(BuildContext context) {
    final k=widget.kind;
    final scheme=Theme.of(context).colorScheme;
    Widget heading(String s)=>Padding(padding:const EdgeInsets.only(top:18,bottom:6),child:Text(s,style:TextStyle(color:scheme.primary,fontWeight:FontWeight.bold,fontSize:16)));
    Widget param(String a,String b)=>Padding(padding:const EdgeInsets.only(bottom:12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(a,style:const TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:3),Text(b)]));
    Widget slider(String name,int v,int min,int max,ValueChanged<int> change)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('$name: $v sn'),Slider(value:v.toDouble(),min:min.toDouble(),max:max.toDouble(),divisions:max==min?null:max-min,onChanged:max==min?null:(x)=>setState(()=>change(x.round())))]);
    return Scaffold(appBar:AppBar(title:Text(FunctionHelpData.extraTitles[k-1],style:const TextStyle(fontSize:17))),body:ListView(padding:const EdgeInsets.all(16),children:[
      heading('Giriş koşulu'),
      if(k==1) Wrap(spacing:8,children:[ChoiceChip(label:const Text('I1 = ON'),selected:!falling,onSelected:(_)=>setState(()=>falling=false)),ChoiceChip(label:const Text('I1 = OFF'),selected:falling,onSelected:(_)=>setState(()=>falling=true))]) else if(k==2) Wrap(spacing:8,children:[ChoiceChip(label:const Text('I1 ↑ (Yükselen kenar)'),selected:!falling,onSelected:(_)=>setState(()=>falling=false)),ChoiceChip(label:const Text('I1 ↓ (Düşen kenar)'),selected:falling,onSelected:(_)=>setState(()=>falling=true))]) else const Text('I1 = ON'),
      const SizedBox(height:12),Text(FunctionHelpData.extraDescriptions[k-1]),
      heading('Fonksiyonu keşfet'),const Text('Örnek değerleri değiştirerek zaman diyagramını inceleyin. Bu değerler programa aktarılmaz.'),
      if(k==1)...[slider('TH',th,1,5,(v)=>th=v),slider('TL',tl,1,5,(v)=>tl=v)] else ...[
        slider('T',t,1,10,(v){t=v;if(warning>t)warning=t;if(cut>warning)cut=warning;}),
        if(k==3)...[slider('TL',tl,1,5,(v)=>tl=v),SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Uzun basma'),value:longPress,onChanged:(v)=>setState(()=>longPress=v))],
        if(k==2||k==3)...[slider('T!',warning,0,t,(v){warning=v;if(cut>warning)cut=warning;}),slider('T!L',cut,0,warning,(v)=>cut=v)],
      ],
      SizedBox(height:k==4?235:195,child:CustomPaint(painter:ExtraTimerPainter(kind:k,th:th,tl:tl,t:t,warning:warning,cut:cut,falling:falling,longPress:longPress,scheme:scheme))),
      Text(k==4?'Örnek: I1 duraklatılır ve yeniden ON olur; I2 RESET biriken süreyi siler.':k==3&&longPress?'Uzun basma: çıkış sonraki basıp bırakmaya kadar ON kalır.':'Örnek diyagram: sanal başlangıç ve yeniden tetikleme uygulanmamıştır.',style:const TextStyle(fontSize:12)),
      heading('Parametreler'),
      if(k==1)...[param('TH – ON süresi (0,001–86400 sn)','Çıkışın ON kalacağı süre.'),param('TL – OFF süresi (0,001–86400 sn)','Çıkışın OFF kalacağı süre.'),param('SANAL GİRİŞ','Enerji verildiğinde darbe üretimi başlar. Fiziksel koşul ilk kez gerçekleştiğinde yeni ON fazı ile fiziksel kontrole geçilir.')] else ...[
        param('T – ${k==4?'Hedef süre':'Kapanma süresi'} (0,001–86400 sn)',k==4?'Biriken ON süresi bu değere ulaştığında çıkış ON olur.':k==2?'Tetikleme kenarından çıkışın kapanmasına kadar geçen süre.':'Giriş bırakıldıktan sonra çıkışın kapanmasına kadar geçen süre.'),
        if(k==3)param('TL – Uzun basma eşiği (0,001–86400 sn)','Giriş en az TL kadar ON kalırsa süreli kapanma yerine sürekli ON seçilir.'),
        if(k==2||k==3)...[param('T! – Ön uyarı zamanı (0–T)','Kapanmadan ne kadar önce uyarı kesintisinin başlayacağını belirler.'),param('T!L – Uyarı kesintisi (0–T!)','Uyarı sırasında çıkışın OFF kalacağı süre. T! veya T!L sıfır ise uyarı yoktur.')],
        if(k==2)param('YENİDEN TETİKLE','Açık ise süre devam ederken yeni tetikleme T süresini yeniden başlatır ve çıkışı ON yapar. Kapalı ise süre devam ederken yeni tetiklemeler yok sayılır.'),
        if(k==4)...[param('RESET','RESET girişi ON olduğu sürece biriken süre sıfırlanır ve çıkış OFF olur.'),param('SANAL GİRİŞ','Enerji verildiğinde süre birikmeye başlar. Fiziksel koşul ilk kez gerçekleştiğinde biriken süre sıfırlanır ve fiziksel girişle yeniden sayılır.')],
      ],const Text('Zaman ayar çözünürlüğü: 1 ms (0,001 sn).'),
    ]),bottomNavigationBar:SafeArea(child:Padding(padding:const EdgeInsets.all(12),child:Row(children:[Expanded(child:OutlinedButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Vazgeç'))),const SizedBox(width:12),Expanded(child:FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('İşlemi Ekle')))]))));
  }
}
