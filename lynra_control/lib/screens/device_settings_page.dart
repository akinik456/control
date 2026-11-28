import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_preferences.dart';
import '../services/lynra_ble_service.dart';
import 'ble_connection_page.dart';

class DeviceSettingsPage extends StatefulWidget {
  const DeviceSettingsPage({super.key});

  @override
  State<DeviceSettingsPage> createState() =>
      _DeviceSettingsPageState();
}

class _DeviceSettingsPageState
    extends State<DeviceSettingsPage> {

  final _ble = LynraBleService.instance;

  String? _deviceId;
  String? _pairingCode;
  String? _error;

  bool _loading = false;
	bool? _wifiLicensed;
bool _activating = false;

final _activationController = TextEditingController();
final _ssidController = TextEditingController();
final _passwordController = TextEditingController();

bool _savingWifi = false;
bool _hidePassword = true;

Timer? _wifiStatusTimer;
int? _wifiState;
bool _readingWifiState = false;

  bool get _isTurkish =>
      AppPreferences.instance.isTurkish;

  String tr(String turkish, String english) =>
      _isTurkish ? turkish : english;

  @override
  void initState() {
    super.initState();

    _ble.addListener(_onBleChanged);
		_wifiStatusTimer = Timer.periodic(
  const Duration(seconds: 2),
  (_) => _pollWifiState(),
);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadDeviceInfo();
    });
  }

  void _onBleChanged() {
    if (!mounted) return;

    setState(() {
      if (!_ble.isConnected) {
        _deviceId = null;
        _pairingCode = null;
				_wifiLicensed = null;
				_wifiState = null;
_activationController.clear();
_ssidController.clear();
_passwordController.clear();
_hidePassword = true;
        _error = null;
      }
    });
  }

  Future<void> _loadDeviceInfo() async {
    if (!_ble.isConnected ||
        _ble.commandBusy ||
        _loading) return;

    final device = _ble.connectedDevice;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final deviceId = await _ble.readDeviceId();

      if (!mounted ||
          !_ble.isConnected ||
          _ble.connectedDevice != device) return;

      final pairingCode = await _ble.readPairingCode();

      if (!mounted ||
          !_ble.isConnected ||
          _ble.connectedDevice != device) return;
			final wifiLicensed = await _ble.readWifiLicense();

if (!mounted ||
    !_ble.isConnected ||
    _ble.connectedDevice != device) return;
      setState(() {
  _deviceId = deviceId;
  _pairingCode = pairingCode;
  _wifiLicensed = wifiLicensed;
});

    } catch (e) {
      if (mounted && _ble.isConnected) {
        setState(() {
          _error = tr(
            'Cihaz bilgileri okunamadı.',
            'Failed to read device information.',
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }
	Future<void> _pollWifiState() async {
  if (!mounted ||
      !_ble.isConnected ||
      _ble.connecting ||
      _ble.commandBusy ||
      _ble.pendingAck != null ||
      _wifiLicensed != true ||
      _loading ||
      _activating ||
      _savingWifi ||
      _readingWifiState) return;

  final device = _ble.connectedDevice;

  _readingWifiState = true;

  try {
    final state = await _ble.readWifiState();

    if (!mounted ||
        !_ble.isConnected ||
        _ble.connectedDevice != device) return;

    if (_wifiState != state) {
      setState(() => _wifiState = state);
    }
  } catch (e) {
    if (mounted && _ble.connectedDevice == device) {
      setState(() => _wifiState = null);
    }
  } finally {
    _readingWifiState = false;
  }
}
	Future<void> _saveWifiConfig() async {
  if (!_ble.isConnected ||
      _ble.commandBusy ||
      _loading ||
      _savingWifi ||
      _activating ||
      _wifiLicensed != true) return;

  final ssid = _ssidController.text;
  final password = _passwordController.text;

  final ssidLength = utf8.encode(ssid).length;
  final passwordLength = utf8.encode(password).length;

  if (ssidLength == 0 ||
      ssidLength > 32 ||
      passwordLength > 63 ||
      ssid.contains('\u0000') ||
      password.contains('\u0000')) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr(
          'Geçersiz ağ adı veya şifre.',
          'Invalid network name or password.',
        )),
      ),
    );
    return;
  }

  final device = _ble.connectedDevice;

  setState(() => _savingWifi = true);

  try {
    final success = await _ble.saveWifiConfig(
      ssid,
      password,
    );

    if (!mounted ||
        !_ble.isConnected ||
        _ble.connectedDevice != device) return;

    if (!success) {
      throw StateError('WiFi configuration rejected');
    }

    setState(() {
      _passwordController.clear();
      _hidePassword = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr(
          'Ağ ayarları kaydedildi.',
          'Network settings saved.',
        )),
      ),
    );
  } catch (e) {
    if (mounted && _ble.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(
            'Ağ ayarları kaydedilemedi.',
            'Failed to save network settings.',
          )),
        ),
      );
    }
  } finally {
    if (mounted) {
      setState(() => _savingWifi = false);
    }
  }
}
	Future<void> _activateWifi() async {
  if (!_ble.isConnected ||
      _ble.commandBusy ||
      _activating ||
      _loading ||
      _wifiLicensed != false) return;

  final code = _activationController.text.trim();

  if (!RegExp(r'^[A-Za-z0-9_-]{86}$').hasMatch(code)) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr(
          'Geçersiz aktivasyon kodu.',
          'Invalid activation code.',
        )),
      ),
    );
    return;
  }

  final device = _ble.connectedDevice;

  setState(() => _activating = true);

  try {
    final success = await _ble.activateWifiLicense(code);

    if (!mounted ||
        !_ble.isConnected ||
        _ble.connectedDevice != device) return;

    if (!success) {
      throw StateError('Activation rejected');
    }

    final licensed = await _ble.readWifiLicense();

    if (!mounted ||
        !_ble.isConnected ||
        _ble.connectedDevice != device) return;

    setState(() {
      _wifiLicensed = licensed;

      if (licensed) {
        _activationController.clear();
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          licensed
              ? tr('Wi-Fi lisansı etkinleştirildi.',
                   'Wi-Fi license activated.')
              : tr('Lisans doğrulanamadı.',
                   'License could not be verified.'),
        ),
      ),
    );
  } catch (e) {
    if (mounted && _ble.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(
            'Lisans aktivasyonu başarısız.',
            'License activation failed.',
          )),
        ),
      );
    }
  } finally {
    if (mounted) {
      setState(() => _activating = false);
    }
  }
}
Future<void> _reconnect() async {
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const BleConnectionPage(
        connectionOnly: true,
        returnOnConnect: true,
      ),
    ),
  );

  if (!mounted || !_ble.isConnected) return;

  await _loadDeviceInfo();
}
  Future<void> _copy(String value) async {
    await Clipboard.setData(
      ClipboardData(text: value),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr('Kopyalandı', 'Copied'),
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }
	String _wifiStateText() {
  switch (_wifiState) {
    case 0:
      return tr(
        'Wi-Fi devre dışı',
        'Wi-Fi disabled',
      );

    case 1:
      return tr(
        'Ağ ayarları yapılmamış',
        'Network not configured',
      );

    case 2:
      return tr(
        'Wi-Fi ağına bağlanıyor...',
        'Connecting to Wi-Fi...',
      );

    case 3:
      return tr(
        'Wi-Fi bağlı',
        'Wi-Fi connected',
      );

    case 4:
      return tr(
        'Bulut bağlantısı hazırlanıyor...',
        'Preparing cloud connection...',
      );

    case 5:
      return tr(
        'Bulut bağlantısı aktif',
        'Cloud online',
      );

    case 6:
      return tr(
        'Wi-Fi sistem hatası',
        'Wi-Fi system error',
      );

    default:
      return tr(
        'Durum okunuyor...',
        'Reading status...',
      );
  }
}
Color _wifiStateColor() {
  switch (_wifiState) {
    case 5:
      return Colors.green;

    case 2:
    case 3:
    case 4:
      return Colors.orange;

    case 6:
      return Colors.red;

    default:
      return Colors.grey;
  }
}
	Widget _wifiConfigCard() {
  final canSave = _ble.isConnected &&
      !_ble.commandBusy &&
      !_loading &&
      !_activating &&
      !_savingWifi &&
      _wifiLicensed == true;

  return Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
  leading: const Icon(Icons.router_outlined),
  title: Text(
    tr('Wi-Fi Ağ Ayarları', 'Wi-Fi Network Settings'),
  ),
  subtitle: Text(
    _wifiStateText(),
    style: TextStyle(
      color: _wifiStateColor(),
    ),
  ),
  trailing: Icon(
    _wifiState == 5
        ? Icons.cloud_done_outlined
        : Icons.cloud_off_outlined,
    color: _wifiStateColor(),
  ),
),

        const Divider(height: 1),

        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _ssidController,
                enabled: canSave,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: tr('Ağ Adı (SSID)', 'Network Name (SSID)'),
                  border: const OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 12),

              TextField(
                controller: _passwordController,
                enabled: canSave,
                obscureText: _hidePassword,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: tr('Şifre', 'Password'),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: canSave
                        ? () => setState(() {
                            _hidePassword = !_hidePassword;
                          })
                        : null,
                    icon: Icon(
                      _hidePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              Text(
                tr(
                  '2.4 GHz Wi-Fi ağı kullanınız.',
                  'Use a 2.4 GHz Wi-Fi network.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),

              const SizedBox(height: 16),

              FilledButton(
                onPressed: canSave ? _saveWifiConfig : null,
                child: Text(
                  _savingWifi
                      ? tr('Kaydediliyor...', 'Saving...')
                      : tr('Kaydet ve Bağlan', 'Save and Connect'),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
Widget _wifiLicenseCard() {
  final licensed = _wifiLicensed;

  final canActivate = _ble.isConnected &&
      !_ble.commandBusy &&
      !_loading &&
      !_activating &&
      licensed == false;

  return Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.wifi),
          title: Text(
            tr('Wi-Fi Lisansı', 'Wi-Fi License'),
          ),
          subtitle: Text(
            licensed == null
                ? '—'
                : licensed
                    ? tr('Aktif', 'Active')
                    : tr('Aktif değil', 'Inactive'),
          ),
          trailing: licensed == true
              ? const Icon(
                  Icons.check_circle_outline,
                  color: Colors.green,
                )
              : null,
        ),

        if (licensed == false) ...[
          const Divider(height: 1),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _activationController,
                  enabled: canActivate,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: tr(
                      'Aktivasyon Kodu',
                      'Activation Code',
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 12),

                FilledButton(
                  onPressed:
                      canActivate ? _activateWifi : null,
                  child: Text(
                    _activating
                        ? tr('Etkinleştiriliyor...',
                             'Activating...')
                        : tr('Lisansı Etkinleştir',
                             'Activate License'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}
  Widget _infoRow(String label, String? value) {
    return ListTile(
      title: Text(label),
      subtitle: SelectableText(
        value ?? '—',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
      trailing: IconButton(
        tooltip: tr('Kopyala', 'Copy'),
        icon: const Icon(Icons.copy_outlined),
        onPressed: value == null
            ? null
            : () => _copy(value),
      ),
    );
  }

  @override
void dispose() {
_wifiStatusTimer?.cancel();
  _ble.removeListener(_onBleChanged);

  _activationController.dispose();
  _ssidController.dispose();
  _passwordController.dispose();

  super.dispose();
}

  @override
  Widget build(BuildContext context) {
    final connected = _ble.isConnected;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('Cihaz Ayarları', 'Device Settings'),
        ),
        actions: [
          IconButton(
            tooltip: tr('Yenile', 'Refresh'),
            icon: const Icon(Icons.refresh),
            onPressed: connected &&
                    !_loading &&
                    !_ble.commandBusy
                ? _loadDeviceInfo
                : null,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 500,
          ),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                leading: Icon(
                  Icons.bluetooth,
                  color: connected
                      ? Colors.green
                      : Colors.grey,
                ),
                title: Text(
                  connected
                      ? tr('Cihaz bağlı', 'Device connected')
                      : tr('Cihaz bağlı değil',
                           'Device disconnected'),
                ),
								trailing: connected
    ? null
    : TextButton(
        onPressed: _ble.connecting || _loading
            ? null
            : _reconnect,
        child: Text(tr('Bağlan', 'Connect')),
      ),
              ),

              if (_loading)
                const LinearProgressIndicator(),

              const SizedBox(height: 12),

              Card(
                child: Column(
                  children: [
                    _infoRow(
                      tr('Cihaz Kimliği', 'Device ID'),
                      _deviceId,
                    ),

                    const Divider(height: 1),

                    _infoRow(
                      tr('Eşleştirme Kodu', 'Pairing Code'),
                      _pairingCode,
                    ),
                  ],
                ),
              ),
const SizedBox(height: 12),

_wifiLicenseCard(),
if (_wifiLicensed == true) ...[
  const SizedBox(height: 12),
  _wifiConfigCard(),
],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}