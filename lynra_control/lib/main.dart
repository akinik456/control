
import 'package:flutter/material.dart';

import 'core/theme/app_colors.dart';
import 'core/theme/app_preferences.dart';
import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';
import 'screens/program_editor_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppPreferences.instance.load();

  runApp(const LynraControlApp());
}

class LynraControlApp extends StatelessWidget {
  const LynraControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppPreferences.instance,
      builder: (context, child) {
        return MaterialApp(
          title: 'Lynra Control',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.data,
          locale: Locale(AppPreferences.instance.languageCode),
          localizationsDelegates:
              AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HomePage(),
        );
      },
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
	final l10n = AppLocalizations.of(context)!;
    final prefs = AppPreferences.instance;
    final isTurkish = prefs.isTurkish;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lynra Control'),
        actions: [
          IconButton(
            tooltip: isTurkish ? 'Tema değiştir' : 'Change theme',
            icon: Icon(
              prefs.isDark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
            onPressed: () {
              prefs.setDark(!prefs.isDark);
            },
          ),
          PopupMenuButton<String>(
            tooltip: isTurkish ? 'Dil seçimi' : 'Language',
            icon: const Icon(Icons.language),
            onSelected: prefs.setLanguage,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'tr',
                child: Text('Türkçe'),
              ),
              PopupMenuItem(
                value: 'en',
                child: Text('English'),
              ),
            ],
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.settings_input_component_outlined,
                  size: 76,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  'Lynra Control',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme.headlineMedium
                      ?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  isTurkish
                      ? 'Kontrol programlarını kolayca oluşturun.'
                      : 'Create control programs easily.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 40),
                FilledButton.icon(
                  onPressed: () {
										Navigator.push(
											context,
											MaterialPageRoute(
												builder: (_) => const ProgramEditorPage(),
											),
										);
									},
                  icon: const Icon(Icons.add),
                  label: Text(l10n.newProgram),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.folder_outlined),
                  label: Text(l10n.myPrograms),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
