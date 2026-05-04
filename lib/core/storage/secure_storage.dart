import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps flutter_secure_storage with typed access for VPN secrets.
class SecureStorage {
  SecureStorage() : _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      // Use the shared Keychain access group so the Packet Tunnel extension
      // can read the auth token.
      // Replace with your actual team ID + group: $(TeamID).com.example.flutterVpnGo
      accessibility: KeychainAccessibility.first_unlock,
      accountName: 'flutter_vpn_go',
    ),
  );

  final FlutterSecureStorage _storage;

  static const _kAuthTokenPrefix = 'auth_token_';

  // ── Auth Token ──────────────────────────────────────────────────────────

  Future<void> saveAuthToken(String configId, String token) async {
    await _storage.write(key: '$_kAuthTokenPrefix$configId', value: token);
  }

  Future<String?> loadAuthToken(String configId) async {
    return _storage.read(key: '$_kAuthTokenPrefix$configId');
  }

  Future<void> deleteAuthToken(String configId) async {
    await _storage.delete(key: '$_kAuthTokenPrefix$configId');
  }

  // ── Generic ─────────────────────────────────────────────────────────────

  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
  Future<String?> read(String key) => _storage.read(key: key);
  Future<void> delete(String key) => _storage.delete(key: key);
  Future<void> deleteAll() => _storage.deleteAll();
}
