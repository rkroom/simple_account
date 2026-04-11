import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../tools/config.dart';
import '../tools/config_service.dart';
import '../tools/native_method_channel.dart';
import '../tools/notification_service.dart';
import '../tools/tools.dart';
import '../tools/workmanager_tool.dart';
import '../widgets/account_book_home.dart';
import '../widgets/planned_task_home.dart';
import '../widgets/statement_filter.dart';

class HomeWidget extends StatefulWidget {
  const HomeWidget({super.key});

  @override
  State<StatefulWidget> createState() {
    return HomeWidgetState();
  }
}

class HomeWidgetState extends State<HomeWidget> with WidgetsBindingObserver {
  int _selectedHome = 0;
  int _accountBookTabIndex = 0;
  StatementFilterValue _statementFilter = const StatementFilterValue();

  // 定时器，应用进入后台后一定时间内未被再次打开则彻底退出应用。
  Timer? _exitTimer;
  late final StreamSubscription<String?> _notificationSubscription;

  Future<void> _openStatementFilter() async {
    final result = await showDialog<StatementFilterValue>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: StatementFilterDialogContent(initialValue: _statementFilter),
        );
      },
    );

    if (result != null && mounted) {
      setState(() {
        _statementFilter = result;
      });
    }
  }

  bool isSameDate(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  void _configureSelectNotificationListener() {
    _notificationSubscription = selectNotificationStream.stream.listen((
      String? payload,
    ) async {
      if (payload == '/home/schedule') {
        setState(() {
          _selectedHome = 1;
        });
      } else if (payload == '/statistic') {
        if (mounted) {
          Navigator.of(context).pushNamed('/statistic');
        }
      }
    });
  }

  void _checkAppLaunchFromNotification() {
    NotificationService().checkAppLaunchFromNotification();
  }

  void checkAndSetWorkmanagerTasks() async {
    bool dailyTaskStatus = await ConfigService().getNotificationTaskStatus();
    bool scheduleTaskStatus =
        await ConfigService().getScheduleNotificationTaskStatus();

    if (!dailyTaskStatus && !scheduleTaskStatus) {
      return;
    }

    bool succeeded = await ConfigService().getNotificationRegistered();
    if (!succeeded) {
      await performInitialSetup();
      return;
    }
    DateTime? scheduledTaskTime = await ConfigService().getScheduledTaskTime();
    if (scheduledTaskTime == null) {
      await WorkmanagerTool.setupAndScheduleTasks();
      return;
    }
    final now = DateTime.now();
    if (!isSameDate(scheduledTaskTime, now.add(const Duration(days: -1))) &&
        !isSameDate(scheduledTaskTime, now)) {
      await WorkmanagerTool.setupAndScheduleTasks();
      return;
    }
  }

  /// 判断是否需要检测存储权限
  /// 当设备为 Android 且 API level >= 29 时，不检测存储权限
  Future<bool> checkAndRequestStoragePermission() async {
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      if (androidInfo.version.sdkInt >= 29) {
        return true;
      }
    }
    PermissionStatus status = await Permission.storage.status;
    if (status != PermissionStatus.granted) {
      PermissionStatus requestStatus = await Permission.storage.request();
      if (requestStatus.isDenied) {
        return false;
      } else if (requestStatus.isPermanentlyDenied) {
        openAppSettings();
        return false;
      }
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _configureSelectNotificationListener();
    _checkAppLaunchFromNotification();
    checkAndSetWorkmanagerTasks();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      bool hasShownInstructions = await ConfigService().getAppInstructions();
      if (!hasShownInstructions && mounted) {
        showDialog(
          context: context,
          builder:
              (BuildContext dialogContext) => AlertDialog(
                title: const Text('说明'),
                content: const Text(
                  '欢迎使用！\n\n1. 自动记录账单相应权限。\n2. 自动记录账单需要开启自启动。\n3. 消息推送需要开启通知权限。',
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      ConfigService().setAppInstructions(true);
                    },
                    child: const Text('好的'),
                  ),
                ],
              ),
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      // 用户重新回到应用时，取消定时器
      if (_exitTimer != null && _exitTimer!.isActive) {
        _exitTimer!.cancel();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _exitTimer?.cancel();
    _notificationSubscription.cancel();
    super.dispose();
  }

  Widget _buildBody() {
    switch (_selectedHome) {
      case 1:
        return PlannedTaskHome();
      case 0:
      default:
        return AccountBookHome(
          filterValue: _statementFilter,
          onTabChanged: (index) {
            if (_accountBookTabIndex != index && mounted) {
              setState(() {
                _accountBookTabIndex = index;
              });
            }
          },
        );
    }
  }

  Widget _buildAppBarTitle() {
    switch (_selectedHome) {
      case 1:
        return const Text('计划');
      case 0:
      default:
        final bool showFilter = _accountBookTabIndex == 1;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('账本'),
            if (showFilter) ...[
              const SizedBox(width: 6),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _openStatementFilter,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    _statementFilter.hasValue
                        ? Icons.filter_alt
                        : Icons.filter_alt_outlined,
                    size: 20,
                  ),
                ),
              ),
            ],
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (!Platform.isAndroid) {
          SystemNavigator.pop();
        }
        if (_exitTimer != null && _exitTimer!.isActive) {
          _exitTimer!.cancel();
        }
        _exitTimer = Timer(const Duration(minutes: 5), () {
          // 超过五分钟未返回应用，彻底退出应用
          SystemNavigator.pop();
        });
        await NativeMethodChannel.instance.minimizeApp();
      },
      child: Scaffold(
        appBar: AppBar(
          title: GestureDetector(
            onTap: () {
              setState(() {
                _selectedHome = _selectedHome == 0 ? 1 : 0;
              });
            },
            child: _buildAppBarTitle(),
          ),
          actions: [
            Builder(
              builder:
                  (context) => IconButton(
                    icon: const Icon(Icons.settings),
                    onPressed: () => Scaffold.of(context).openEndDrawer(),
                    tooltip:
                        MaterialLocalizations.of(context).openAppDrawerTooltip,
                  ),
            ),
          ],
        ),
        drawer: Builder(
          builder:
              (drawerContext) => Drawer(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    const DrawerHeader(
                      decoration: BoxDecoration(color: Colors.blue),
                      child: Text('菜单'),
                    ),
                    ListTile(
                      title: const Text('账本'),
                      onTap: () {
                        setState(() {
                          _selectedHome = 0;
                        });
                        Navigator.of(drawerContext).pop();
                      },
                    ),
                    ExpansionTile(
                      title: const Text('计划'),
                      initiallyExpanded: true,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.only(left: 16.0),
                          child: ListTile(
                            title: const Text('日程'),
                            onTap: () {
                              setState(() {
                                _selectedHome = 1;
                              });
                              Navigator.of(drawerContext).pop();
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
        ),
        endDrawer: Builder(
          builder:
              (endDrawerContext) => Drawer(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    const DrawerHeader(
                      decoration: BoxDecoration(color: Colors.blue),
                      child: Text('管理'),
                    ),
                    ListTile(
                      title: const Text('账本设置'),
                      onTap: () {
                        Navigator.of(endDrawerContext).pop();
                        Navigator.of(
                          context,
                        ).pushNamed('/manage').then((value) => {});
                      },
                    ),
                    ListTile(
                      title: const Text('账本管理'),
                      onTap: () {
                        Navigator.of(endDrawerContext).pop();
                        Navigator.of(
                          context,
                        ).pushNamed('/accountFile').then((value) => {});
                      },
                    ),
                    ListTile(
                      title: const Text('导出账本'),
                      onTap: () async {
                        // 仅在低于API29时检测存储权限
                        if (!await checkAndRequestStoragePermission()) {
                          return;
                        }
                        String fileName = p.basename(Global.config!.path);
                        try {
                          // 调用平台方法通过 MediaStore API 导出文件到 Downloads 文件夹
                          String? result = await NativeMethodChannel.instance
                              .copyToDownloads(Global.config!.path, fileName);
                          var password = await ConfigService().getDBPassword();
                          if (result != null && context.mounted) {
                            showDialog(
                              context: context,
                              builder: (BuildContext dialogContext) {
                                return AlertDialog(
                                  content: Text('已导出到：$result\n账本密码：$password'),
                                  actions: <Widget>[
                                    TextButton(
                                      onPressed: () async {
                                        Navigator.of(dialogContext).pop();
                                        Navigator.of(endDrawerContext).pop();
                                      },
                                      child: const Text('确定'),
                                    ),
                                  ],
                                );
                              },
                            );
                          }
                        } catch (e) {
                          debugPrint("导出错误：$e");
                          if (context.mounted) {
                            Navigator.of(endDrawerContext).pop();
                            showNoticeSnackBar(context, '导出失败');
                          }
                        }
                      },
                    ),
                    ListTile(
                      title: const Text('记录图表'),
                      onTap: () {
                        Navigator.of(endDrawerContext).pop();
                        Navigator.of(
                          context,
                        ).pushNamed('/statistic').then((value) => {});
                      },
                    ),
                    ListTile(
                      title: const Text('导出记录'),
                      onTap: () async {
                        // 仅在低于API29时检测存储权限
                        if (!await checkAndRequestStoragePermission()) {
                          return;
                        }

                        try {
                          String jsonString = jsonEncode(
                            await NativeMethodChannel.instance.getBills(),
                          );
                          String fileName = "billRecord.json";
                          // 调用平台方法使用 MediaStore API 将字符串写入到 Downloads 文件夹中的文件
                          String result = await NativeMethodChannel.instance
                              .exportJsonToDownloads(jsonString, fileName);

                          if (context.mounted) {
                            showDialog(
                              context: context,
                              builder: (BuildContext dialogContext) {
                                return AlertDialog(
                                  content: Text('已导出到：$result'),
                                  actions: <Widget>[
                                    TextButton(
                                      onPressed: () async {
                                        Navigator.of(dialogContext).pop();
                                        Navigator.of(endDrawerContext).pop();
                                      },
                                      child: const Text('确定'),
                                    ),
                                  ],
                                );
                              },
                            );
                          }
                        } catch (e) {
                          debugPrint("导出错误：$e");
                          if (context.mounted) {
                            Navigator.of(endDrawerContext).pop();
                            showNoticeSnackBar(context, '导出失败');
                          }
                        }
                      },
                    ),
                    if (defaultTargetPlatform == TargetPlatform.android) ...[
                      ListTile(
                        title: const Text('账单记录'),
                        onTap: () async {
                          try {
                            final bool hasAccessibilityPermission =
                                await NativeMethodChannel.instance
                                    .checkAccessibilityPermission();
                            final bool hasNotificationPermission =
                                await NativeMethodChannel.instance
                                    .checkNotificationListenerPermission();
                            if (hasAccessibilityPermission ||
                                hasNotificationPermission) {
                              if (context.mounted) {
                                Navigator.of(endDrawerContext).pop();
                                Navigator.of(context)
                                    .pushNamed('/billListener')
                                    .then((value) => {});
                              }
                            } else {
                              if (context.mounted) {
                                showDialog(
                                  context: context,
                                  builder: (BuildContext dialogContext) {
                                    return AlertDialog(
                                      content: const Text('该功能需要权限读取账单信息。'),
                                      actions: <Widget>[
                                        TextButton(
                                          onPressed: () {
                                            Navigator.of(dialogContext).pop();
                                          },
                                          child: const Text('取消'),
                                        ),
                                        TextButton(
                                          onPressed: () async {
                                            Navigator.of(dialogContext).pop();
                                            Navigator.of(
                                              endDrawerContext,
                                            ).pop();
                                            try {
                                              Navigator.of(context)
                                                  .pushNamed('/configuration')
                                                  .then((value) => {});
                                            } on PlatformException catch (e) {
                                              debugPrint(
                                                "获取权限失败: '${e.message}'.",
                                              );
                                            }
                                          },
                                          child: const Text('确定'),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              }
                            }
                          } on PlatformException catch (e) {
                            debugPrint("检测权限失败: '${e.message}'.");
                          }
                        },
                      ),
                      ListTile(
                        title: const Text('应用设置'),
                        onTap: () {
                          Navigator.of(endDrawerContext).pop();
                          Navigator.of(
                            context,
                          ).pushNamed('/configuration').then((value) => {});
                        },
                      ),
                    ],
                  ],
                ),
              ),
        ),
        body: _buildBody(),
      ),
    );
  }
}
