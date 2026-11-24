import 'package:flutter/material.dart';
import '../core/theme/app_preferences.dart';

class LiveMonitorPage extends StatelessWidget {
  const LiveMonitorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isTurkish = AppPreferences.instance.isTurkish;
    return Scaffold(
      appBar: AppBar(
        title: Text(isTurkish ? 'Canlı İzleme' : 'Live Monitor'),
      ),
      body: const SizedBox.expand(),
    );
  }
}
