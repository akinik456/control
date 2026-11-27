import 'package:flutter/material.dart';
import 'function_help_data.dart';
import 'function_timing_painter.dart';

class FunctionHelpPage extends StatefulWidget {
  const FunctionHelpPage({super.key, this.wiping = false, this.edgeWiping = false});
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
