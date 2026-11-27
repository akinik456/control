import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

class LicenseService {
  static AsymmetricKeyPair<PublicKey, PrivateKey> generateKeyPair() {
    final random = Random.secure();

    final secureRandom = FortunaRandom();

    secureRandom.seed(
      KeyParameter(
        Uint8List.fromList(
          List<int>.generate(32, (_) => random.nextInt(256)),
        ),
      ),
    );

    final generator = ECKeyGenerator();

    generator.init(
      ParametersWithRandom(
        ECKeyGeneratorParameters(
          ECDomainParameters('prime256v1'),
        ),
        secureRandom,
      ),
    );

    return generator.generateKeyPair();
  }
	static const String keyDirectory = r'C:\LynraKeys';

static String get privateKeyPath =>
    '$keyDirectory\\private_key.json';

static String get publicKeyPath =>
    '$keyDirectory\\public_key.json';

static bool keysExist() {
  return File(privateKeyPath).existsSync() &&
      File(publicKeyPath).existsSync();
}

static void saveKeyPair(
  ECPrivateKey privateKey,
  ECPublicKey publicKey,
) {
  Directory(keyDirectory).createSync(recursive: true);

  final privateFile = File(privateKeyPath);
  final publicFile = File(publicKeyPath);

  if (privateFile.existsSync() || publicFile.existsSync()) {
    throw StateError('Mevcut anahtarların üzerine yazılamaz.');
  }

  final privateData = {
    'curve': 'prime256v1',
    'd': privateKey.d!.toRadixString(16).padLeft(64, '0'),
  };

  final publicData = {
    'curve': 'prime256v1',
    'x': publicKey.Q!.x!.toBigInteger()!
        .toRadixString(16).padLeft(64, '0'),
    'y': publicKey.Q!.y!.toBigInteger()!
        .toRadixString(16).padLeft(64, '0'),
  };

  privateFile.writeAsStringSync(
    jsonEncode(privateData),
    flush: true,
  );

  publicFile.writeAsStringSync(
    jsonEncode(publicData),
    flush: true,
  );
}

static AsymmetricKeyPair<ECPublicKey, ECPrivateKey>
    loadKeyPair() {
  final privateData = jsonDecode(
    File(privateKeyPath).readAsStringSync(),
  );

  final publicData = jsonDecode(
    File(publicKeyPath).readAsStringSync(),
  );

  final domain = ECDomainParameters('prime256v1');

  final d = BigInt.parse(privateData['d'], radix: 16);
  final x = BigInt.parse(publicData['x'], radix: 16);
  final y = BigInt.parse(publicData['y'], radix: 16);

  if (d <= BigInt.zero || d >= domain.n) {
    throw StateError('Geçersiz private key.');
  }

  final q = domain.G * d;

  if (q == null ||
      q.x!.toBigInteger() != x ||
      q.y!.toBigInteger() != y) {
    throw StateError('Anahtar çifti eşleşmiyor.');
  }

  return AsymmetricKeyPair<ECPublicKey, ECPrivateKey>(
    ECPublicKey(q, domain),
    ECPrivateKey(d, domain),
  );
}
static Uint8List _licenseMessage(String deviceId) {
  final id = deviceId.trim().toUpperCase();

  if (!RegExp(r'^[0-9A-F]{12}$').hasMatch(id)) {
    throw FormatException('Geçersiz cihaz kimliği.');
  }

  return Uint8List.fromList(
    utf8.encode('LYNRACONTROL|V1|$id|WIFI'),
  );
}
static Uint8List _toBytes32(BigInt value) {
  final result = Uint8List(32);

  for (int i = 31; i >= 0; i--) {
    result[i] = (value & BigInt.from(255)).toInt();
    value = value >> 8;
  }

  return result;
}
static BigInt _fromBytes(List<int> bytes) {
  BigInt result = BigInt.zero;

  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }

  return result;
}
static String generateActivationCode(
  String deviceId,
  ECPrivateKey privateKey,
) {
  final message = _licenseMessage(deviceId);

  final signer = ECDSASigner(
    SHA256Digest(),
    HMac(SHA256Digest(), 64),
  );

  signer.init(
    true,
    PrivateKeyParameter<ECPrivateKey>(privateKey),
  );

  final signature =
      signer.generateSignature(message) as ECSignature;

  final bytes = Uint8List.fromList([
    ..._toBytes32(signature.r),
    ..._toBytes32(signature.s),
  ]);

  return base64UrlEncode(bytes).replaceAll('=', '');
}
static bool verifyActivationCode(
  String deviceId,
  String code,
  ECPublicKey publicKey,
) {
  try {
    final normalized = code.trim();

    if (!RegExp(r'^[A-Za-z0-9_-]{86}$')
        .hasMatch(normalized)) {
      return false;
    }

    final bytes = base64Url.decode(
      base64Url.normalize(normalized),
    );

    if (bytes.length != 64) {
      return false;
    }

    final r = _fromBytes(bytes.sublist(0, 32));
    final s = _fromBytes(bytes.sublist(32, 64));

    final signer = ECDSASigner(SHA256Digest());

    signer.init(
      false,
      PublicKeyParameter<ECPublicKey>(publicKey),
    );

    return signer.verifySignature(
      _licenseMessage(deviceId),
      ECSignature(r, s),
    );
  } catch (_) {
    return false;
  }
}
}