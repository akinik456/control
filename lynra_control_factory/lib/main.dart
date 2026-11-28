import 'dart:async';
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
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
  _ble.addListener(_connectionChanged);
  _wifiTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollWifi());
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
  _wifiTimer?.cancel();
  _ble.removeListener(_connectionChanged);
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
  Timer? _wifiTimer;
  int? _wifiState;
  bool _polling = false;
  bool _reading = false;
  int _connectionGeneration = 0;
  bool _wasConnected = false;

  void _connectionChanged() {
    if (_wasConnected != _ble.isConnected) {
      _wasConnected = _ble.isConnected;
      _connectionGeneration++;
      if (mounted) setState(() => _wifiState = null);
    }
  }

  Future<void> _pollWifi() async {
    if (!mounted || !_ble.isConnected || _ble.connecting ||
        _ble.busy || _polling || _reading || _activating || _savingWifiConfig) return;
    final generation = _connectionGeneration;
    setState(() => _polling = true);
    try {
      final value = await _ble.readWifiState();
      if (mounted && generation == _connectionGeneration && _ble.isConnected) {
        setState(() => _wifiState = value);
      }
    } catch (_) {
      if (mounted && generation == _connectionGeneration) {
        setState(() => _wifiState = null);
      }
    } finally {
      if (mounted) setState(() => _polling = false);
    }
  }

  String get _wifiLabel {
    if (!_ble.isConnected) return 'BLE bağlı değil';
    return switch (_wifiState) {
      0 => 'Wi-Fi lisansı yok',
      1 => 'Wi-Fi yapılandırılmamış',
      2 => 'Bağlanıyor / yeniden bağlanıyor',
      3 => 'Wi-Fi bağlı',
      4 => 'Firebase oturum bilgisi hazır',
      5 => 'Bulut çevrimiçi',
      6 => 'Wi-Fi task hatası',
      _ => 'Durum bekleniyor / okunamadı',
    };
  }

  InputDecoration _field(String label) => InputDecoration(
    labelText: label, isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: const OutlineInputBorder(),
  );

  @override
  Widget build(BuildContext context) {
    final ready = _privateKey != null && _publicKey != null;
    return Scaffold(
      appBar: AppBar(title: const Text('LynraControl Factory'), toolbarHeight: 48),
      body: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: 600,
            child: ListenableBuilder(
              listenable: _ble,
              builder: (context, child) {
                final idle = !_polling && !_reading && !_activating && !_savingWifiConfig && !_ble.busy;
                final canRead = _ble.isConnected && !_ble.connecting && idle;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      FilledButton.icon(
                        onPressed: _ble.scanning || _ble.connecting || _ble.isConnected ? null : _ble.scan,
                        icon: const Icon(Icons.bluetooth_searching),
                        label: Text(_ble.scanning ? 'Taranıyor...' : 'Cihazları Tara'),
                      ),
                      FilledButton.icon(
                        onPressed: _ble.scanning || _ble.connecting || _ble.selectedDevice == null || !idle
                          ? null : _ble.isConnected ? _ble.disconnect : _ble.connect,
                        icon: Icon(_ble.isConnected ? Icons.bluetooth_disabled : Icons.bluetooth_connected),
                        label: Text(_ble.connecting ? 'Bekleyiniz...' : _ble.isConnected ? 'Bağlantıyı Kes' : 'Bağlan'),
                      ),
                    ]),
                    if (_ble.scanning) const LinearProgressIndicator(),
                    ..._ble.devices.map((result) {
                      final device = result.device;
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        child: ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: const Icon(Icons.bluetooth),
                          title: const Text('LynraControl'),
                          subtitle: Text(device.remoteId.toString()),
                          trailing: Text('${result.rssi} dBm'),
                          selected: _ble.selectedDevice?.remoteId == device.remoteId,
                          onTap: _ble.connecting || _ble.isConnected ? null : () => _ble.selectDevice(device),
                        ),
                      );
                    }),
                    Text(_ble.status),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      FilledButton(onPressed: canRead ? _readDeviceId : null, child: const Text('Cihaz Kimliğini Oku')),
                      FilledButton(onPressed: canRead ? _readWifiLicense : null, child: const Text('Wi-Fi Lisans Durumunu Oku')),
                    ]),
                    const Divider(height: 12),
                    Align(alignment: Alignment.centerLeft, child: FilledButton(
                      onPressed: ready || _activating ? null : _generateKeys,
                      child: const Text('Anahtar Çifti Oluştur'),
                    )),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _deviceIdController, maxLength: 12,
                      enabled: !_activating,
                      onChanged: (_) => setState(() => _activationCode = ''),
                      decoration: _field('Cihaz Kimliği').copyWith(hintText: '12 karakter HEX', counterText: ''),
                    ),
                    const SizedBox(height: 4),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      FilledButton(onPressed: ready && !_activating ? _generateActivationCode : null,
                        child: const Text('Aktivasyon Kodu Üret')),
                      FilledButton(onPressed: canRead && _activationCode.isNotEmpty ? _activateWifiLicense : null,
                        child: Text(_activating ? 'Aktivasyon yapılıyor...' : 'Wi-Fi Lisansını Aktive Et')),
                    ]),
                    if (_activationCode.isNotEmpty) SelectableText(_activationCode),
                    const Divider(height: 12),
                    const Text('Wi-Fi Yapılandırma', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    TextField(controller: _ssidController, decoration: _field('Wi-Fi SSID')),
                    const SizedBox(height: 6),
                    TextField(controller: _passwordController, obscureText: true, decoration: _field('Wi-Fi Şifresi')),
                    const SizedBox(height: 4),
                    Align(alignment: Alignment.centerLeft, child: FilledButton(
                      onPressed: canRead ? _saveWifiConfig : null,
                      child: Text(_savingWifiConfig ? 'Kaydediliyor...' : 'Wi-Fi Bilgilerini Kaydet'),
                    )),
                    Row(children: [
                      Icon(_wifiState == 5 ? Icons.cloud_done : Icons.cloud_off,
                        color: _wifiState == 5 ? Colors.green : null, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_wifiLabel)),
                    ]),
                    const Divider(height: 12),
                    Text(_status),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

Future<void> _readDeviceId() async {
  if (_reading || _polling || _ble.busy) return;
  setState(() => _reading = true);
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
  } finally {
    if (mounted) setState(() => _reading = false);
  }
}	
Future<void> _readWifiLicense() async {
  if (_reading || _polling || _ble.busy) return;
  setState(() => _reading = true);
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
  } finally {
    if (mounted) setState(() => _reading = false);
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