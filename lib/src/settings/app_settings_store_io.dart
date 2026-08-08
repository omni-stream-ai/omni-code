import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:path_provider/path_provider.dart';

import 'app_settings_store.dart';

class FileAppSettingsStore implements AppSettingsStore {
  encrypt.Key? _key;
  Directory? _dir;

  @override
  Future<String?> read() async {
    final file = await _settingsFile();
    if (!await file.exists()) {
      return null;
    }
    final raw = await file.readAsString();
    try {
      return await _decrypt(raw);
    } catch (_) {
      return raw;
    }
  }

  @override
  Future<void> write(String value) async {
    final file = await _settingsFile();
    final encrypted = await _encrypt(value);
    await file.writeAsString(encrypted, flush: true);
  }

  Future<String> _encrypt(String plainText) async {
    final key = await _loadOrCreateKey();
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    final combined = Uint8List.fromList(iv.bytes + encrypted.bytes);
    return base64Encode(combined);
  }

  Future<String> _decrypt(String encoded) async {
    final combined = base64Decode(encoded);
    if (combined.length < 16) {
      return encoded;
    }
    final iv = encrypt.IV(Uint8List.fromList(combined.sublist(0, 16)));
    final ciphertext =
        encrypt.Encrypted(Uint8List.fromList(combined.sublist(16)));
    final key = await _loadOrCreateKey();
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    return encrypter.decrypt(ciphertext, iv: iv);
  }

  Future<encrypt.Key> _loadOrCreateKey() async {
    if (_key != null) return _key!;
    final dir = await _initDir();
    final keyFile = File('${dir.path}/.omni-code-key');
    if (await keyFile.exists()) {
      final hex = await keyFile.readAsString();
      _key = encrypt.Key(Uint8List.fromList(
        List<int>.generate(
          32,
          (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
        ),
      ));
    } else {
      final random = Random.secure();
      final bytes = List<int>.generate(32, (_) => random.nextInt(256));
      _key = encrypt.Key(Uint8List.fromList(bytes));
      await keyFile.writeAsString(
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        flush: true,
      );
      if (Platform.isLinux || Platform.isMacOS) {
        try {
          await Process.run('chmod', ['600', keyFile.path]);
        } catch (_) {}
      }
    }
    return _key!;
  }

  Future<Directory> _initDir() async {
    if (_dir != null) return _dir!;
    try {
      _dir = await getApplicationDocumentsDirectory();
    } on MissingPlatformDirectoryException {
      final home = Platform.environment['HOME'] ?? '/tmp';
      _dir = Directory('$home/.config/omni-code');
    }
    await _dir!.create(recursive: true);
    return _dir!;
  }

  Future<File> _settingsFile() async {
    final dir = await _initDir();
    return File('${dir.path}/omni-code-settings.json');
  }
}

AppSettingsStore createPlatformAppSettingsStore() => FileAppSettingsStore();
