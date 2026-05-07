import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

class LocalAuthService {
  static final LocalAuthentication _auth = LocalAuthentication();

  static Future<bool> canUseBiometrics() async {
    try {
      final bool canCheckBiometrics = await _auth.canCheckBiometrics;
      final bool isDeviceSupported = await _auth.isDeviceSupported();

      if (!canCheckBiometrics || !isDeviceSupported) {
        return false;
      }

      final biometrics = await _auth.getAvailableBiometrics();
      return biometrics.isNotEmpty;
    } on PlatformException {
      return false;
    } on LocalAuthException {
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate({
    String reason = '请验证指纹以解锁应用',
    String androidTitle = '账本需解锁',
    String androidHint = '请验证指纹',
  }) async {
    try {
      final bool canUse = await canUseBiometrics();
      if (!canUse) return false;

      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
        authMessages: <AuthMessages>[
          AndroidAuthMessages(
            signInTitle: androidTitle,
            signInHint: androidHint,
            cancelButton: '取消',
          ),
        ],
      );
    } on LocalAuthException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
