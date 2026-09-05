import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage();

  static Future<void> saveAuthData({
    required String token,
    required String idUsuario,
  }) async {
    await _storage.write(key: 'auth_token', value: token);
    await _storage.write(key: 'user_id', value: idUsuario);
  }

  static Future<String?> getToken() async => await _storage.read(key: 'auth_token');
  static Future<String?> getUserId() async => await _storage.read(key: 'user_id');
  static Future<void> clearAll() async => await _storage.deleteAll();
}