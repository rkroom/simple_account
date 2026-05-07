import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tools/config.dart';
import '../tools/config_service.dart';
import '../tools/local_auth_service.dart';
import '../tools/native_method_channel.dart';

class BiometricLockLayer extends StatefulWidget {
  final Widget child;

  const BiometricLockLayer({super.key, required this.child});

  @override
  State<BiometricLockLayer> createState() => _BiometricLockLayerState();
}

class _BiometricLockLayerState extends State<BiometricLockLayer>
    with WidgetsBindingObserver {
  DateTime? _backgroundAt;

  bool _privacyCoverVisible =
      Global.jumpLoad &&
      Global.biometricUnlockEnabled &&
      !Global.biometricUnlockedInCurrentSession;

  bool _authInProgress = false;
  bool _authFailed = false;
  bool _backgroundedDuringAuth = false;
  bool _waitingForManualRetry = false;

  String _coverMessage = '账本需解锁';

  static const Duration _backgroundAuthDelay = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleInitialBiometricUnlock();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async {
    // 锁屏遮罩显示时，拦截 Android 返回键，防止底层路由被 pop 后露出账本页面
    if (_privacyCoverVisible) {
      return true;
    }

    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // 指纹弹窗本身可能触发生命周期变化，避免重复处理。
    // 但如果认证期间应用真的进入后台，仍然要记录后台时间，
    // 否则长时间后台后可能绕过 5 分钟重新验证逻辑。
    if (_authInProgress) {
      if (state == AppLifecycleState.hidden ||
          state == AppLifecycleState.paused) {
        _backgroundedDuringAuth = true;
        _handleAppLeaveForeground();
      }

      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _handleAppLeaveForeground();
    }

    if (state == AppLifecycleState.resumed) {
      _handleAppResumed();
    }
  }

  Future<void> _handleInitialBiometricUnlock() async {
    if (!Global.jumpLoad) {
      Global.biometricUnlockedInCurrentSession = true;
      return;
    }

    if (!Global.biometricUnlockEnabled) {
      Global.biometricUnlockedInCurrentSession = true;
      return;
    }

    if (Global.biometricUnlockedInCurrentSession) {
      _hidePrivacyCover();
      return;
    }

    if (mounted) {
      setState(() {
        _privacyCoverVisible = true;
        _authInProgress = false;
        _authFailed = false;
        _waitingForManualRetry = false;
        _coverMessage = '账本需解锁';
      });
    }

    await _authenticateAndUnlock(
      reason: '请验证指纹以解锁账本',
      androidTitle: '账本需解锁',
      androidHint: '请验证指纹',
    );
  }

  void _handleAppLeaveForeground() {
    if (!Global.biometricUnlockEnabled) {
      _backgroundAt = null;
      return;
    }

    _backgroundAt ??= DateTime.now();

    if (!_privacyCoverVisible && mounted) {
      setState(() {
        _privacyCoverVisible = true;
        _authInProgress = false;
        _authFailed = false;
        _waitingForManualRetry = false;
        _coverMessage = '应用已隐藏';
      });
    }
  }

  Future<void> _handleAppResumed() async {
    await NativeMethodChannel.instance.cancelExitTimer();

    if (!Global.biometricUnlockEnabled) {
      Global.biometricUnlockedInCurrentSession = true;
      _backgroundAt = null;
      _waitingForManualRetry = false;
      _hidePrivacyCover();
      return;
    }

    if (_waitingForManualRetry) {
      _backgroundAt = null;
      return;
    }

    final backgroundAt = _backgroundAt;

    if (backgroundAt == null) {
      if (!Global.biometricUnlockedInCurrentSession && !_authInProgress) {
        await _authenticateAndUnlock(
          reason: '请验证指纹以解锁账本',
          androidTitle: '账本需解锁',
          androidHint: '请验证指纹',
        );
      }

      return;
    }

    final elapsed = DateTime.now().difference(backgroundAt);
    _backgroundAt = null;

    // 首次进入还没成功解锁过时，不允许因为“少于 5 分钟”而直接放行。
    if (!Global.biometricUnlockedInCurrentSession) {
      await _authenticateAndUnlock(
        reason: '请验证指纹以解锁账本',
        androidTitle: '账本需解锁',
        androidHint: '请验证指纹',
      );

      return;
    }

    if (elapsed < _backgroundAuthDelay) {
      _hidePrivacyCover();
      return;
    }

    Global.biometricUnlockedInCurrentSession = false;

    await _authenticateAndUnlock(
      reason: '请验证指纹以解锁账本',
      androidTitle: '账本需解锁',
      androidHint: '请验证指纹',
    );
  }

  bool _needReauthenticateAfterAuthBackground() {
    if (!_backgroundedDuringAuth) {
      return false;
    }

    _backgroundedDuringAuth = false;

    final backgroundAt = _backgroundAt;
    _backgroundAt = null;

    if (backgroundAt == null) {
      return false;
    }

    final elapsed = DateTime.now().difference(backgroundAt);
    return elapsed >= _backgroundAuthDelay;
  }

  Future<void> _authenticateAndUnlock({
    required String reason,
    required String androidTitle,
    required String androidHint,
  }) async {
    if (_authInProgress) return;

    if (!Global.biometricUnlockEnabled) {
      Global.biometricUnlockedInCurrentSession = true;
      _waitingForManualRetry = false;
      _hidePrivacyCover();
      return;
    }

    Global.biometricUnlockedInCurrentSession = false;
    _waitingForManualRetry = false;

    if (mounted) {
      setState(() {
        _privacyCoverVisible = true;
        _authInProgress = true;
        _authFailed = false;
        _coverMessage = androidTitle;
      });
    }

    bool canUse = false;

    try {
      canUse = await LocalAuthService.canUseBiometrics();
    } on PlatformException {
      _backgroundedDuringAuth = false;
      _backgroundAt = null;
      Global.biometricUnlockedInCurrentSession = false;
      _waitingForManualRetry = true;

      if (!mounted) return;

      setState(() {
        _privacyCoverVisible = true;
        _authInProgress = false;
        _authFailed = true;
        _coverMessage = '验证异常，请重试';
      });

      return;
    } catch (_) {
      _backgroundedDuringAuth = false;
      _backgroundAt = null;
      Global.biometricUnlockedInCurrentSession = false;
      _waitingForManualRetry = true;

      if (!mounted) return;

      setState(() {
        _privacyCoverVisible = true;
        _authInProgress = false;
        _authFailed = true;
        _coverMessage = '验证异常，请重试';
      });

      return;
    }

    if (!canUse) {
      _backgroundedDuringAuth = false;
      _backgroundAt = null;
      Global.biometricUnlockedInCurrentSession = true;
      _waitingForManualRetry = false;

      await ConfigService().setBiometricUnlockEnabled(false);
      Global.biometricUnlockEnabled = false;

      if (!mounted) return;

      setState(() {
        _privacyCoverVisible = false;
        _authInProgress = false;
        _authFailed = false;
        _coverMessage = '账本需解锁';
      });

      return;
    }

    bool passed = false;

    try {
      passed = await LocalAuthService.authenticate(
        reason: reason,
        androidTitle: androidTitle,
        androidHint: androidHint,
      );
    } on PlatformException {
      _backgroundedDuringAuth = false;
      _backgroundAt = null;
      Global.biometricUnlockedInCurrentSession = false;
      _waitingForManualRetry = true;

      if (!mounted) return;

      setState(() {
        _privacyCoverVisible = true;
        _authInProgress = false;
        _authFailed = true;
        _coverMessage = '验证异常，请重试';
      });

      return;
    } catch (_) {
      _backgroundedDuringAuth = false;
      _backgroundAt = null;
      Global.biometricUnlockedInCurrentSession = false;
      _waitingForManualRetry = true;

      if (!mounted) return;

      setState(() {
        _privacyCoverVisible = true;
        _authInProgress = false;
        _authFailed = true;
        _coverMessage = '验证异常，请重试';
      });

      return;
    }

    final needReauthenticate = _needReauthenticateAfterAuthBackground();

    if (!mounted) return;

    if (passed) {
      if (needReauthenticate) {
        Global.biometricUnlockedInCurrentSession = false;
        _waitingForManualRetry = false;

        setState(() {
          _privacyCoverVisible = true;
          _authInProgress = false;
          _authFailed = false;
          _coverMessage = '账本需解锁';
        });

        await _authenticateAndUnlock(
          reason: reason,
          androidTitle: androidTitle,
          androidHint: androidHint,
        );

        return;
      }

      Global.biometricUnlockedInCurrentSession = true;
      _waitingForManualRetry = false;

      setState(() {
        _privacyCoverVisible = false;
        _authInProgress = false;
        _authFailed = false;
        _coverMessage = '账本需解锁';
      });
    } else {
      Global.biometricUnlockedInCurrentSession = false;
      _waitingForManualRetry = true;

      setState(() {
        _privacyCoverVisible = true;
        _authInProgress = false;
        _authFailed = true;
        _coverMessage = '验证失败或已取消';
      });
    }
  }

  void _hidePrivacyCover() {
    if (!_privacyCoverVisible || !mounted) return;

    setState(() {
      _privacyCoverVisible = false;
      _authInProgress = false;
      _authFailed = false;
      _waitingForManualRetry = false;
      _coverMessage = '账本需解锁';
    });
  }

  Widget _buildPrivacyCover() {
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, color: Colors.white, size: 64),
                const SizedBox(height: 20),
                Text(
                  _coverMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
                if (_authInProgress) ...[
                  const SizedBox(height: 24),
                  const CircularProgressIndicator(),
                ],
                if (_authFailed) ...[
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      _waitingForManualRetry = false;

                      _authenticateAndUnlock(
                        reason: '请验证指纹以解锁账本',
                        androidTitle: '账本需解锁',
                        androidHint: '请验证指纹',
                      );
                    },
                    child: const Text('重新验证'),
                  ),
                  TextButton(
                    onPressed: () => SystemNavigator.pop(),
                    child: const Text(
                      '退出应用',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_privacyCoverVisible,
      child: Stack(
        children: [
          Offstage(offstage: _privacyCoverVisible, child: widget.child),
          if (_privacyCoverVisible) _buildPrivacyCover(),
        ],
      ),
    );
  }
}
