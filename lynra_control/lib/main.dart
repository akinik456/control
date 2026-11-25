import 'dart:io';
import '/services/lynra_plc_ffi.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

import 'l10n/app_localizations.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_preferences.dart';
import 'core/theme/app_theme.dart';
import 'screens/program_editor_page.dart';
import 'screens/live_monitor_page.dart';
import 'screens/auth_page.dart';
import 'screens/serial_terminal_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
LynraPlcFfi().printStructSizes();

  await AppPreferences.instance.load();
  // Şimdilik uygulama Türkçe başlasın; dil seçimi korunur.
  await AppPreferences.instance.setLanguage('tr');

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
	    final prefs = AppPreferences.instance;
    final isTurkish = prefs.isTurkish;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: isTurkish ? 'Hesabım' : 'My Account',
          icon: const Icon(Icons.account_circle_outlined),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AuthPage()),
          ),
        ),
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
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          child: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            initialData: FirebaseAuth.instance.currentUser,
            builder: (context, snapshot) {
              final user = snapshot.data;
              final accountName = user?.displayName?.trim().isNotEmpty == true
                  ? user!.displayName!
                  : user?.email ?? (isTurkish ? 'Misafir' : 'Guest');
              return Text(
                accountName,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).appBarTheme.titleTextStyle ??
                    Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
              );
            },
          ),
        ),
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
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ProgramEditorPage(initialActionsOpen: true),
                    ),
                  ),
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Program'),
                ),
                const SizedBox(height: 12),
								OutlinedButton.icon(
									onPressed: () {
										Navigator.push(
											context,
											MaterialPageRoute(
												builder: (_) => const LiveMonitorPage(),
											),
										);
									},
									icon: const Icon(Icons.monitor_heart_outlined),
									label: Text(isTurkish ? 'Canlı İzle' : 'Live Monitor'),
								),
                if (Platform.isWindows) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SerialTerminalPage(),
                      ),
                    ),
                    icon: const Icon(Icons.terminal),
                    label: const Text('RS232 Terminal'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
