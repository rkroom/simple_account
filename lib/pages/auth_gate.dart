import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tools/config.dart';
import '../tools/config_service.dart';
import '../tools/local_auth_service.dart';

class AuthGateWidget extends StatefulWidget {
  const AuthGateWidget({super.key});

  @override
  State<AuthGateWidget> createState() => _AuthGateWidgetState();
}

class _AuthGateWidgetState extends State<AuthGateWidget> {
  bool _checking = true;
  String _message = '正在验证身份...';

  @override
  void initState() {
    super.initState();
    _checkAndUnlock();
  }

  Future<void> _checkAndUnlock() async {
    setState(() {
      _checking = true;
      _message = '正在验证身份...';
    });

    final enabled = await ConfigService().getBiometricUnlockEnabled();

    if (!enabled) {
      _goHome();
      return;
    }

    final canUse = await LocalAuthService.canUseBiometrics();

    if (!canUse) {
      await ConfigService().setBiometricUnlockEnabled(false);
      Global.biometricUnlockEnabled = false;

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前设备未录入指纹，已自动关闭指纹解锁')));

      _goHome();
      return;
    }

    final passed = await LocalAuthService.authenticate(reason: '请验证指纹以解锁账本');

    if (!mounted) return;

    if (passed) {
      _goHome();
    } else {
      setState(() {
        _checking = false;
        _message = '验证失败或已取消';
      });
    }
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child:
            _checking
                ? const CircularProgressIndicator()
                : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.fingerprint, size: 64),
                      const SizedBox(height: 16),
                      Text(_message, textAlign: TextAlign.center),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _checkAndUnlock,
                        child: const Text('重新验证'),
                      ),
                      TextButton(
                        onPressed: () => SystemNavigator.pop(),
                        child: const Text('退出应用'),
                      ),
                    ],
                  ),
                ),
      ),
    );
  }
}
