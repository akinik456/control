import 'package:flutter/material.dart';
import 'function_help_data.dart';
import 'function_timing_painter.dart';

class FunctionHelpPage extends StatefulWidget {
  const FunctionHelpPage({super.key, this.wiping = false});
  final bool wiping;
  @override
  State<FunctionHelpPage> createState() => _FunctionHelpPageState();
}
class _FunctionHelpPageState extends State<FunctionHelpPage> {
  int condition = 0;
  bool repeat = false;
  bool get edge => condition >= 2;
  bool get falling => condition == 1 || condition == 3;
  int th = 2, tl = 3, t = 3;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget heading(String text) => Padding(padding: const EdgeInsets.only(top: 18, bottom: 6), child: Text(text, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold, fontSize: 16)));
    Widget param(String title, String text) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 3), Text(text)]));
    Widget time(String title, int value, ValueChanged<int> change) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('$title: $value sn'), Slider(value: value.toDouble(), min: edge && repeat ? 1 : 0, max: 5, divisions: edge && repeat ? 4 : 5, label: '$value sn', onChanged: (v) => setState(() => change(v.round())))]);
    return Scaffold(
      appBar: AppBar(title: Text(widget.wiping ? FunctionHelpData.wipingRelay : FunctionHelpData.onOffDelay, style: const TextStyle(fontSize: 17))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        heading('Giriş koşulu'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final item in (widget.wiping ? const ['I1 = ON', 'I1 = OFF'] : const ['I1 = ON', 'I1 = OFF', 'I1 ↑ (Yükselen kenar)', 'I1 ↓ (Düşen kenar)']).asMap().entries)
              ChoiceChip(
                label: Text(item.value),
                selected: condition == item.key,
                onSelected: (_) => setState(() {
                  condition = item.key;
                  if (!edge) repeat = false;
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(edge ? 'EDGE' : 'LEVEL', style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(widget.wiping ? FunctionHelpData.wipingLevel : (edge ? FunctionHelpData.edge : FunctionHelpData.level)),
        if (!widget.wiping)
        Text(const [
          'I1 ON olduğunda TH, OFF olduğunda TL başlar.',
          'I1 OFF olduğunda TH, ON olduğunda TL başlar.',
          'I1 yükselen kenarında TH başlar.',
          'I1 düşen kenarında TH başlar.',
        ][condition]),
        heading('Fonksiyonu keşfet'),
        const Text('Örnek değerleri değiştirerek zaman diyagramını inceleyin. Bu değerler programa aktarılmaz.'),
        if (widget.wiping) ...[
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
