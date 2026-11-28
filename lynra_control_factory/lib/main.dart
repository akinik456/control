import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pointycastle/export.dart'
    show ECPrivateKey, ECPublicKey;
import 'services/license_service.dart';
import 'services/factory_ble_service.dart';

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
final _ble = FactoryBleService();
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
final _ssidController = TextEditingController();
final _passwordController = TextEditingController();

bool _savingWifiConfig = false;
String _activationCode = '';

@override
void dispose() {
  _ble.dispose();
  _deviceIdController.dispose();
_ssidController.dispose();
_passwordController.dispose();  
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
					ListenableBuilder(
  listenable: _ble,
  builder: (context, child) {
    return Column(
      children: [
        FilledButton.icon(
          onPressed: _ble.scanning ||
                  _ble.connecting ||
                  _ble.isConnected
              ? null
              : _ble.scan,
          icon: const Icon(Icons.bluetooth_searching),
          label: Text(
            _ble.scanning
                ? 'Taranıyor...'
                : 'Cihazları Tara',
          ),
        ),

        const SizedBox(height: 12),

        if (_ble.scanning)
          const LinearProgressIndicator(),

        ..._ble.devices.map((result) {
          final device = result.device;

          return Card(
            child: ListTile(
              leading: const Icon(Icons.bluetooth),
              title: const Text('LynraControl'),
              subtitle: Text(
                device.remoteId.toString(),
              ),
              trailing: Text('${result.rssi} dBm'),
              selected: _ble.selectedDevice?.remoteId ==
                  device.remoteId,
              onTap: _ble.connecting || _ble.isConnected
    ? null
    : () => _ble.selectDevice(device),
            ),
          );
        }),

        const SizedBox(height: 8),
const SizedBox(height: 12),

FilledButton.icon(
  onPressed: _ble.scanning ||
          _ble.connecting ||
          _ble.selectedDevice == null
      ? null
      : _ble.isConnected
          ? _ble.disconnect
          : _ble.connect,

  icon: Icon(
    _ble.isConnected
        ? Icons.bluetooth_disabled
        : Icons.bluetooth_connected,
  ),

  label: Text(
    _ble.connecting
        ? 'Bekleyiniz...'
        : _ble.isConnected
            ? 'Bağlantıyı Kes'
            : 'Bağlan',
  ),
),

const SizedBox(height: 8),
        Text(_ble.status),
				const SizedBox(height: 12),

FilledButton(
  onPressed: _ble.isConnected && !_ble.connecting
      ? _readDeviceId
      : null,
  child: const Text('Cihaz Kimliğini Oku'),
),
const SizedBox(height: 8),

FilledButton(
  onPressed: _ble.isConnected && !_ble.connecting
      ? _readWifiLicense
      : null,
  child: const Text('Wi-Fi Lisans Durumunu Oku'),
),				
      ],
    );
  },
),

const SizedBox(height: 16),
const Divider(),
const SizedBox(height: 16),
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
const SizedBox(height: 16),

ListenableBuilder(
  listenable: _ble,
  builder: (context, child) {
    return FilledButton(
      onPressed: _ble.isConnected &&
              !_ble.connecting &&
              !_activating &&
              _activationCode.isNotEmpty
          ? _activateWifiLicense
          : null,
      child: Text(
        _activating
            ? 'Aktivasyon yapılıyor...'
            : 'Wi-Fi Lisansını Aktive Et',
      ),
    );
  },
),
          const SizedBox(height: 24),
const Divider(),
const SizedBox(height: 16),

const Text(
  'Wi-Fi Yapılandırma',
  style: TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
  ),
),

const SizedBox(height: 16),

TextField(
  controller: _ssidController,
  decoration: const InputDecoration(
    labelText: 'Wi-Fi SSID',
    border: OutlineInputBorder(),
  ),
),

const SizedBox(height: 12),

TextField(
  controller: _passwordController,
  obscureText: true,
  decoration: const InputDecoration(
    labelText: 'Wi-Fi Şifresi',
    border: OutlineInputBorder(),
  ),
),

const SizedBox(height: 16),

ListenableBuilder(
  listenable: _ble,
  builder: (context, child) {
    return FilledButton(
      onPressed: _ble.isConnected &&
              !_ble.connecting &&
              !_activating &&
              !_savingWifiConfig
          ? _saveWifiConfig
          : null,
      child: Text(
        _savingWifiConfig
            ? 'Kaydediliyor...'
            : 'Wi-Fi Bilgilerini Kaydet',
      ),
    );
  },
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
	
Future<void> _readDeviceId() async {
  try {
    final id = await _ble.readDeviceId();

    if (!mounted) return;

    setState(() {
      _deviceIdController.text = id;
      _activationCode = '';
      _status = 'Cihaz kimliği okundu.';
    });
  } catch (e) {
    if (!mounted) return;

    setState(() {
      _status = 'Cihaz kimliği okuma hatası: $e';
    });
  }
}	
Future<void> _readWifiLicense() async {
  try {
    final enabled = await _ble.readWifiLicense();

    if (!mounted) return;

    setState(() {
      _status = enabled
          ? 'Wi-Fi lisansı AKTİF'
          : 'Wi-Fi lisansı YOK';
    });
  } catch (e) {
    if (!mounted) return;

    setState(() {
      _status = 'Lisans okuma hatası: $e';
    });
  }
}
bool _activating = false;

Future<void> _activateWifiLicense() async {
  if (_activating || _activationCode.isEmpty) return;

  setState(() {
    _activating = true;
  });

  try {
    final id = await _ble.readDeviceId();

    if (id != _deviceIdController.text.trim().toUpperCase()) {
      throw StateError('Bağlı cihazın kimliği farklı.');
    }

    final result = await _ble.activateWifiLicense(
      _activationCode,
    );

    if (!mounted) return;

    setState(() {
      _status = result
          ? 'Aktivasyon başarılı - NVS kayıt OK'
          : 'Aktivasyon reddedildi.';
    });

  } catch (e) {
    if (!mounted) return;

    setState(() {
      _status = 'Aktivasyon hatası: $e';
    });
  } finally {
    if (mounted) {
      setState(() {
        _activating = false;
      });
    }
  }
}
Future<void> _saveWifiConfig() async {
  if (_savingWifiConfig) return;

  setState(() {
    _savingWifiConfig = true;
  });

  try {
    final result = await _ble.saveWifiConfig(
      _ssidController.text,
      _passwordController.text,
    );

    if (!mounted) return;

    setState(() {
      _status = result
          ? 'Wi-Fi bilgileri kaydedildi.'
          : 'Wi-Fi yapılandırması reddedildi.';
    });
  } catch (e) {
    if (!mounted) return;

    setState(() {
      _status = 'Wi-Fi kayıt hatası: $e';
    });
  } finally {
    if (mounted) {
      setState(() {
        _savingWifiConfig = false;
      });
    }
  }
}
}