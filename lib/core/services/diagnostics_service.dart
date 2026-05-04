import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../platform/vpn_platform_service.dart';
import '../../platform/vpn_api.g.dart';
import '../utils/validators.dart';

class DiagnosticsReport {
  const DiagnosticsReport({
    required this.platform,
    required this.appVersion,
    required this.buildNumber,
    required this.osVersion,
    required this.deviceModel,
    required this.vpnPermissionGranted,
    required this.networkExtensionStatus,
    required this.runnerBundleId,
    required this.extensionBundleId,
    required this.appGroupId,
    required this.goClientVersion,
    required this.keychainAccessGroup,
  });

  final String platform;
  final String appVersion;
  final String buildNumber;
  final String osVersion;
  final String deviceModel;
  final bool vpnPermissionGranted;
  final String networkExtensionStatus;
  final String runnerBundleId;
  final String extensionBundleId;
  final String appGroupId;
  final String goClientVersion;
  final String keychainAccessGroup;

  Map<String, dynamic> toJson() => {
        'platform': platform,
        'appVersion': appVersion,
        'buildNumber': buildNumber,
        'osVersion': osVersion,
        'deviceModel': deviceModel,
        'vpnPermissionGranted': vpnPermissionGranted,
        'networkExtensionStatus': networkExtensionStatus,
        'runnerBundleId': runnerBundleId,
        'extensionBundleId': extensionBundleId,
        'appGroupId': appGroupId,
        'goClientVersion': goClientVersion,
        'keychainAccessGroup': keychainAccessGroup,
      };

  String toJsonString() =>
      const JsonEncoder.withIndent('  ').convert(toJson());

  static DiagnosticsReport fromDto(DiagnosticsDto dto) => DiagnosticsReport(
        platform: dto.platform,
        appVersion: dto.appVersion,
        buildNumber: dto.buildNumber,
        osVersion: dto.osVersion,
        deviceModel: dto.deviceModel,
        vpnPermissionGranted: dto.vpnPermissionGranted,
        networkExtensionStatus: dto.networkExtensionStatus,
        runnerBundleId: dto.runnerBundleId,
        extensionBundleId: dto.extensionBundleId,
        appGroupId: dto.appGroupId,
        goClientVersion: dto.goClientVersion,
        keychainAccessGroup: dto.keychainAccessGroup,
      );
}

class DiagnosticsService {
  DiagnosticsService(this._platform);

  final VpnPlatformService _platform;

  Future<DiagnosticsReport> collect() async {
    try {
      final dto = await _platform.getDiagnostics();
      return DiagnosticsReport.fromDto(dto);
    } catch (_) {
      // Fallback with Dart-side info when native is unavailable (e.g. desktop)
      final pkg = await PackageInfo.fromPlatform();
      final deviceInfo = DeviceInfoPlugin();

      String osVersion = 'unknown';
      String deviceModel = 'unknown';
      String platformStr = Platform.operatingSystem;

      try {
        if (Platform.isAndroid) {
          final info = await deviceInfo.androidInfo;
          osVersion = 'Android ${info.version.release} (SDK ${info.version.sdkInt})';
          deviceModel = '${info.manufacturer} ${info.model}';
        } else if (Platform.isIOS) {
          final info = await deviceInfo.iosInfo;
          osVersion = '${info.systemName} ${info.systemVersion}';
          deviceModel = info.model;
        }
      } catch (_) {}

      return DiagnosticsReport(
        platform: platformStr,
        appVersion: pkg.version,
        buildNumber: pkg.buildNumber,
        osVersion: osVersion,
        deviceModel: deviceModel,
        vpnPermissionGranted: false,
        networkExtensionStatus: 'unknown',
        runnerBundleId: pkg.packageName,
        extensionBundleId: '${pkg.packageName}.PacketTunnel',
        appGroupId: 'group.com.example.flutterVpnGo',
        goClientVersion: 'unavailable',
        keychainAccessGroup: 'com.example.flutterVpnGo',
      );
    }
  }
}
