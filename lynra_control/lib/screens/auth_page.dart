import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String _errorText(FirebaseAuthException e) => switch (e.code) {
        'email-already-in-use' => 'Bu e-posta ile zaten bir hesap var.',
        'invalid-email' => 'E-posta adresi geçersiz.',
        'weak-password' => 'Şifre çok zayıf. En az 6 karakter kullan.',
        'wrong-password' || 'user-not-found' || 'invalid-credential' =>
          'E-posta veya şifre hatalı.',
        'network-request-failed' => 'İnternet bağlantısını kontrol et.',
        'too-many-requests' => 'Çok fazla deneme yapıldı. Biraz bekle.',
        _ => 'İşlem başarısız (${e.code}).',
      };

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final email = _email.text.trim();
      final password = _password.text;
      if (_register) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email, password: password,
        );
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email, password: password,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    } catch (_) {
      if (mounted) setState(() => _error = 'Beklenmeyen bir hata oluştu.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() { _busy = true; _error = null; });
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      if (mounted) setState(() => _error = 'Çıkış yapılamadı.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hesabım')),
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final user = snapshot.data;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: user != null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.account_circle_outlined, size: 64),
                          const SizedBox(height: 16),
                          const Text('Giriş yapıldı', textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          Text(user.email ?? '', textAlign: TextAlign.center),
                          const SizedBox(height: 24),
                          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                          FilledButton(
                            onPressed: _busy ? null : _signOut,
                            child: const Text('Çıkış yap'),
                          ),
                        ],
                      )
                    : Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(_register ? 'Hesap oluştur' : 'Giriş yap',
                                style: Theme.of(context).textTheme.headlineSmall,
                                textAlign: TextAlign.center),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(labelText: 'E-posta'),
                              validator: (v) => v == null || !v.contains('@')
                                  ? 'Geçerli bir e-posta gir' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _password,
                              obscureText: true,
                              autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                              decoration: const InputDecoration(labelText: 'Şifre'),
                              validator: (v) => v == null || v.length < 6
                                  ? 'En az 6 karakter gir' : null,
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                            ],
                            const SizedBox(height: 24),
                            FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: Text(_register ? 'Hesap oluştur' : 'Giriş yap'),
                            ),
                            TextButton(
                              onPressed: _busy ? null : () => setState(() {
                                _register = !_register;
                                _error = null;
                              }),
                              child: Text(_register
                                  ? 'Zaten hesabım var — Giriş yap'
                                  : 'Hesabım yok — Kayıt ol'),
                            ),
                            const Text('Hesap olmadan da program oluşturabilir ve test edebilirsin.',
                                textAlign: TextAlign.center),
                          ],
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}
