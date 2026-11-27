import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pointycastle/export.dart'
    show ECPrivateKey, ECPublicKey;
import 'services/license_service.dart';

void main() {
  runApp(const FactoryApp());
}

class FactoryApp extends StatelessWidget {
  const FactoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LynraControl Factory',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const FactoryPage(),
    );
  }
}

class FactoryPage extends StatefulWidget {
  const FactoryPage({super.key});

  @override
  State<FactoryPage> createState() => _FactoryPageState();
}

class _FactoryPageState extends State<FactoryPage> {
  ECPrivateKey? _privateKey;
  ECPublicKey? _publicKey;

  String _status = 'Anahtar oluşturulmadı.';

  void _generateKeys() {
  try {
    if (File(LicenseService.privateKeyPath).existsSync() ||
        File(LicenseService.publicKeyPath).existsSync()) {
      throw StateError('Mevcut anahtar dosyaları var.');
    }

    final pair = LicenseService.generateKeyPair();

    final privateKey = pair.privateKey as ECPrivateKey;
    final publicKey = pair.publicKey as ECPublicKey;

    LicenseService.saveKeyPair(privateKey, publicKey);

    setState(() {
      _privateKey = privateKey;
      _publicKey = publicKey;
      _status = 'Anahtar çifti oluşturuldu ve kaydedildi.';
    });
  } catch (e) {
    setState(() {
      _status = 'Hata: $e';
    });
  }
}
@override
void initState() {
  super.initState();
  _loadKeys();
}

void _loadKeys() {
  try {
    if (LicenseService.keysExist()) {
      final pair = LicenseService.loadKeyPair();

      _privateKey = pair.privateKey;
      _publicKey = pair.publicKey;

      _status = 'Mevcut anahtar çifti yüklendi.';
    } else if (
        File(LicenseService.privateKeyPath).existsSync() ||
        File(LicenseService.publicKeyPath).existsSync()) {
      _status = 'HATA: Anahtar dosyalarından biri eksik.';
    }
  } catch (e) {
    _status = 'Anahtar yükleme hatası: $e';
  }
}	
	
final _deviceIdController = TextEditingController();

String _activationCode = '';

@override
void dispose() {
  _deviceIdController.dispose();
  super.dispose();
}
void _generateActivationCode() {
  if (_privateKey == null || _publicKey == null) {
    return;
  }

  try {
    final deviceId = _deviceIdController.text;

    final code = LicenseService.generateActivationCode(
      deviceId,
      _privateKey!,
    );

    final valid = LicenseService.verifyActivationCode(
      deviceId,
      code,
      _publicKey!,
    );

    if (!valid) {
      throw StateError('İmza doğrulama başarısız.');
    }

    setState(() {
      _activationCode = code;
      _status = 'Aktivasyon kodu üretildi ve doğrulandı.';
    });
  } catch (e) {
    setState(() {
      _activationCode = '';
      _status = 'Hata: $e';
    });
  }
}
  @override
  Widget build(BuildContext context) {
    final ready = _privateKey != null && _publicKey != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('LynraControl Factory'),
      ),
      body: Center(
  child: SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: SizedBox(
      width: 600,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FilledButton(
            onPressed: ready ? null : _generateKeys,
            child: const Text('Anahtar Çifti Oluştur'),
          ),

          const SizedBox(height: 24),

          TextField(
            controller: _deviceIdController,
            maxLength: 12,
            onChanged: (_) {
              setState(() {
                _activationCode = '';
              });
            },
            decoration: const InputDecoration(
              labelText: 'Cihaz Kimliği',
              hintText: '12 karakter HEX',
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 16),

          FilledButton(
            onPressed: ready ? _generateActivationCode : null,
            child: const Text('Wi-Fi Aktivasyon Kodu Üret'),
          ),

          const SizedBox(height: 24),

          if (_activationCode.isNotEmpty)
            SelectableText(
              _activationCode,
              textAlign: TextAlign.center,
            ),

          const SizedBox(height: 24),

          Text(_status),
        ],
      ),
    ),
  ),
),
    );
  }
}