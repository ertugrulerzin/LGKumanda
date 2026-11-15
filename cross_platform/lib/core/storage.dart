import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'protocol.dart';

abstract class TVStorage {
  Future<String?> readSecret(String key);
  Future<void> writeSecret(String key, String value);
  Future<void> deleteSecret(String key);
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class DeviceStorage implements TVStorage {
  const DeviceStorage();
  static const _secure = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  @override
  Future<String?> readSecret(String key) => _secure.read(key: key);
  @override
  Future<void> writeSecret(String key, String value) =>
      _secure.write(key: key, value: value);
  @override
  Future<void> deleteSecret(String key) => _secure.delete(key: key);
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);
  @override
  Future<void> write(String key, String value) async {
    if (!await (await SharedPreferences.getInstance()).setString(key, value)) {
      throw StateError('Ayarlar kaydedilemedi.');
    }
  }
}

class Shortcut {
  const Shortcut(this.kind, this.target, this.title);
  final String kind, target, title;
  String get id => '$kind:$target';
  Json toJson() => {'kind': kind, 'target': target, 'title': title};
  factory Shortcut.fromJson(Json j) =>
      Shortcut(j['kind'], j['target'], j['title']);
  static List<Shortcut> decode(String? text) => text == null
      ? []
      : (jsonDecode(text) as List)
            .map((e) => Shortcut.fromJson(e as Json))
            .toList();
}
