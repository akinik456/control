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


class CounterHelpPage extends StatefulWidget {
  const CounterHelpPage({super.key, required this.kind});
  final String kind;
  @override
  State<CounterHelpPage> createState() => _CounterHelpPageState();
}

class _CounterHelpPageState extends State<CounterHelpPage> {
  int start=0, on=4, off=2, target=4, gate=2, rate=3;
  bool down=false, q=false;
  int count=0, elapsed=0, total=0;
  final List<int> values=[0];
  final List<bool> outputs=[false];
  final List<int> totals=[0];
  final List<String> events=['Başlangıç'];
  int get k => widget.kind=='upDown'?0:widget.kind=='hours'?1:2;
  void evaluate() {
    if(k==0) {
      if(on>=off) {if(count>=on) q=true; else if(count<=off) q=false;}
      else {if(count<=on) q=true; else if(count>=off) q=false;}
    } else if(k==1) {if(elapsed>=target) q=true;}
    else {if(on>=off) {if(count>on) q=true; else if(count<=off) q=false;} else {q=count>=on && count<off;}}
  }
  void record(String event) {
    values.add(k==1?elapsed:count); outputs.add(q); totals.add(total); events.add(event);
    if(values.length>9) {values.removeAt(0);outputs.removeAt(0);totals.removeAt(0);events.removeAt(0);}
  }
  void restart() {
    count=k==0?start:0; elapsed=0;total=0;q=false;
    values.clear();outputs.clear();totals.clear();events.clear();
    if(k==0) evaluate();
    record('Başlangıç');
  }
  @override
  Widget build(BuildContext context) {
    final scheme=Theme.of(context).colorScheme;
    Widget heading(String s)=>Padding(padding:const EdgeInsets.only(top:18,bottom:6),child:Text(s,style:TextStyle(color:scheme.primary,fontWeight:FontWeight.bold,fontSize:16)));
    Widget param(String a,String b)=>Padding(padding:const EdgeInsets.only(bottom:12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(a,style:const TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:3),Text(b)]));
    Widget slider(String name,int v,int min,int max,ValueChanged<int> change)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('$name: $v'),Slider(value:v.toDouble(),min:min.toDouble(),max:max.toDouble(),divisions:max-min,onChanged:(x)=>setState(()=>change(x.round())))]);
    Widget act(String label,VoidCallback fn)=>OutlinedButton(onPressed:()=>setState(fn),child:Text(label));
    return Scaffold(appBar:AppBar(title:Text(FunctionHelpData.counterTitles[k],style:const TextStyle(fontSize:17))),body:ListView(padding:const EdgeInsets.all(16),children:[
      heading('İşlev tanımı'),Text(FunctionHelpData.counterDescriptions[k]),
      heading('Fonksiyonu keşfet'),const Text('Örnek değerler programa aktarılmaz. Butonlarla olayları oluşturup grafiği inceleyin.'),
      if(k==0)...[
        slider('START',start,-5,5,(v){start=v;restart();}),
        slider('ON',on,-5,10,(v){on=v;restart();}),slider('OFF',off,-5,10,(v){off=v;restart();}),
        SwitchListTile(contentPadding:EdgeInsets.zero,title:Text('DIR: ${down?"ON – Geri":"OFF – İleri"}'),value:down,onChanged:(v)=>setState(()=>down=v)),
        Wrap(spacing:8,runSpacing:4,children:[act('CNT ↑',(){count+=down?-1:1;evaluate();record(down?'−1':'+1');}),act('RESET',(){count=start;q=false;record('RESET');evaluate();record('Bırak');})]),
      ] else if(k==1)...[
        slider('T (örnek saniye)',target,1,10,(v){target=v;restart();}),
        Wrap(spacing:8,runSpacing:4,children:[act('EN ON · 1 sn',(){elapsed++;total++;evaluate();record('ON');}),act('EN OFF · 1 sn',(){record('OFF');}),act('R',(){elapsed=0;q=false;record('R');}),act('Ral',(){elapsed=0;total=0;q=false;record('Ral');})]),
      ] else ...[
        slider('G_T (sn)',gate,1,5,(v){gate=v;restart();}),slider('ON (darbe)',on,0,10,(v){on=v;restart();}),slider('OFF (darbe)',off,0,10,(v){off=v;restart();}),slider('Örnek frekans (Hz)',rate,0,5,(v)=>rate=v),
        Text(on>=off?'Histerezisli kontrol':'Frekans aralığı kontrolü'),
        Text('Sonraki pencere: ${rate*gate} darbe'),act('Ölçüm penceresini tamamla',(){count=rate*gate;evaluate();record('$count');}),
      ],
      const SizedBox(height:12),Text(k==1?'Güncel: $elapsed sn   Toplam: $total sn   Q1: ${q?"ON":"OFF"}':'${k==0?"Sayaç":"Son ölçüm"}: $count   Q1: ${q?"ON":"OFF"}',style:const TextStyle(fontWeight:FontWeight.bold)),
      SizedBox(height:230,child:CustomPaint(painter:CounterHelpPainter(values:List.of(values),outputs:List.of(outputs),totals:List.of(totals),events:List.of(events),kind:k,on:k==1?target:on,off:off,scheme:scheme))),
      const Text('Grafik son olayları gösterir. Yatay eksen olay sırasıdır.',style:TextStyle(fontSize:12)),act('Örneği baştan başlat',restart),
      heading('Parametreler'),
      if(k==0)...[
        param('CNT','Sayım girişi. Yalnızca yükselen kenarlar sayılır.'),param('DIR','OFF veya YOK: ileri sayım. ON: geri sayım.'),param('START','Başlangıç ve RESET değeri.'),param('ON / OFF','ON ≥ OFF ise sayaç ON değerine ulaştığında veya geçtiğinde çıkış ON, OFF değerine ulaştığında veya altına indiğinde OFF olur. ON < OFF ise yön tersidir: ON değerine veya altına inince ON, OFF değerine veya üstüne çıkınca OFF olur. Arada önceki durum korunur. Eşikler eşitse ON önceliklidir.'),param('RESET','ON olduğu sürece sayaç START değerinde tutulur ve çıkış OFF olur. Bırakıldığında eşikler yeniden değerlendirilir.'),param('Değer aralığı','START, ON ve OFF: −2147483648…2147483647. Sayaç bu sınırlarda durur.'),
      ] else if(k==1)...[
        param('EN','Çalışma süresini biriktiren giriş.'),param('T – Hedef süre','0–1000000 saat ve 0–59 dakika; toplam süre sıfır olamaz. Ayar çözünürlüğü 1 dakikadır. Grafikte örnek olarak saniye kullanılmıştır.'),param('R','Güncel süreyi sıfırlar ve çıkışı OFF yapar. Toplam süre EN ON iken birikmeye devam eder.'),param('Ral','Güncel ve toplam süreyi sıfırlar, çıkışı OFF yapar. Ral önceliklidir.'),
      ] else ...[
        param('Fre','Ölçüm girişi. Yalnızca yükselen kenarlar sayılır.'),param('G_T (1–100 sn)','Ölçüm penceresi; 1 saniye adımlarla ayarlanır. Frekans = darbe adedi / G_T.'),param('ON / OFF (0–9999 darbe)','ON ≥ OFF: ölçüm ON değerinden büyükse çıkış ON, OFF değerine eşit veya küçükse OFF olur; arada önceki durum korunur.'),param('Aralık kontrolü','ON < OFF: ölçüm ON değerine eşit veya büyük ve OFF değerinden küçükse çıkış ON, aksi halde OFF olur.'),param('Ölçüm güncellemesi','Çıkış pencere sonunda değerlendirilir. İki veya daha fazla pencere süresi geçerse ölçüm geçersiz sayılır ve çıkış korunur.'),
      ],
    ]),bottomNavigationBar:SafeArea(child:Padding(padding:const EdgeInsets.all(12),child:Row(children:[Expanded(child:OutlinedButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Vazgeç'))),const SizedBox(width:12),Expanded(child:FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('İşlemi Ekle')))]))));
  }
}


class OutputHelpPage extends StatelessWidget {
  const OutputHelpPage({super.key, required this.selected});
  final String selected;
  static const descriptions = {
    'on': 'Koşul doğru iken çıkış ON, yanlış iken OFF olur. Çıkış koşulu takip eder.',
    'off': 'Koşul doğru iken çıkış OFF, yanlış iken ON olur. Çıkış koşulun tersini takip eder.',
    'set': 'Koşul yanlış durumdan doğru duruma geçtiğinde çıkış ON yapılır. Koşul tekrar yanlış olsa da çıkış ON kalır.',
    'reset': 'Koşul yanlış durumdan doğru duruma geçtiğinde çıkış OFF yapılır. Koşul tekrar yanlış olsa da çıkış OFF kalır.',
    'toggle': 'Koşul her yanlış durumdan doğru duruma geçtiğinde çıkış tersine döner. Koşul doğru kaldığı sürece tekrar değişmez.',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Çıkış İşlevleri')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Örnek giriş koşulu: I1 = ON. Her diyagram bağımsız bir örnektir.'),
        const SizedBox(height: 12),
        for (final item in descriptions.entries) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: item.key == selected ? scheme.primary.withValues(alpha: 0.08) : null,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: item.key == selected ? scheme.primary : scheme.outlineVariant),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Text(item.key.toUpperCase(), style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold, fontSize: 16)),
                if (item.key == selected) ...[const Spacer(), Icon(Icons.check_circle, color: scheme.primary, size: 20)]
              ]),
              const SizedBox(height: 6), Text(item.value),
              const SizedBox(height: 8),
              SizedBox(height: 88, width: double.infinity, child: CustomPaint(painter: _OutputHelpPainter(item.key, scheme))),
              if (item.key == 'reset') const Text('Örnekte Q1 başlangıçta ON kabul edilmiştir.', style: TextStyle(fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 10),
        ],
        const Text('SET, RESET ve TOGGLE çıkışın durumunu başka bir işlem değiştirene veya program sıfırlanana kadar korur. Bu işlevlerin zaman parametresi yoktur.'),
      ]),
      bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç'))),
        const SizedBox(width: 12),
        Expanded(child: FilledButton(onPressed: () => Navigator.pop(context, true), child: Text('${selected.toUpperCase()} Ekle'))),
      ]))),
    );
  }
}

class _OutputHelpPainter extends CustomPainter {
  const _OutputHelpPainter(this.kind, this.scheme);
  final String kind;
  final ColorScheme scheme;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 48) return;
    const left = 32.0;
    final step = (size.width - left - 8) / 7;
    const input = [false, true, true, false, true, false, false];
    final output = <bool>[];
    bool q = kind == 'reset';
    bool prev = false;
    for (final active in input) {
      if (kind == 'on') { q = active; }
      else if (kind == 'off') { q = !active; }
      else if (active && !prev) {
        if (kind == 'set') { q = true; }
        else if (kind == 'reset') { q = false; }
        else { q = !q; }
      }
      output.add(q);
      prev = active;
    }
    final guide = Paint()..color = scheme.outline.withValues(alpha: 0.45)..strokeWidth = 1;
    for (var i = 1; i < input.length; i++) {
      if (input[i] == input[i-1]) continue;
      final x = left + i * step;
      for (double y = 4; y < 84; y += 7) {
        canvas.drawLine(Offset(x,y), Offset(x,y+3), guide);
      }
    }
    void wave(String label, List<bool> values, double base, Color color) {
      final tp = TextPainter(text: TextSpan(text: label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(0, base-18));
      double y(bool v) => base - (v ? 23 : 0);
      final path = Path()..moveTo(left, y(values.first));
      for (var i=0; i<values.length; i++) {
        path.lineTo(left+i*step, y(values[i]));
        path.lineTo(left+(i+1)*step, y(values[i]));
      }
      canvas.drawPath(path, Paint()..color=color..style=PaintingStyle.stroke..strokeWidth=2.3);
    }
    wave('I1', input, 31, scheme.primary);
    wave('Q1', output, 79, Colors.green);
  }
  @override
  bool shouldRepaint(covariant _OutputHelpPainter oldDelegate) => oldDelegate.kind != kind || oldDelegate.scheme != scheme;
}
