import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';

import '../tools/config_service.dart';
import '../tools/entity.dart';
import '../tools/native_method_channel.dart';
import '../tools/tools.dart';

// acc AccessibilityService，nl NotificationListenerService
enum ConfigType { acc, nl }

Map<String, dynamic> _processAppsInIsolate(Map<String, dynamic> input) {
  final List<Map<String, dynamic>> apps = List<Map<String, dynamic>>.from(
    input['apps'] as List,
  );
  final List<Map<String, dynamic>> configPackages =
      List<Map<String, dynamic>>.from(input['config'] as List);

  final selected = <String>{};
  for (var c in configPackages) {
    if ((c['isAllowed'] ?? false) == true) {
      selected.add(c['packageName'] as String);
    }
  }

  final appNameLower = <String, String>{};
  final appPkgLower = <String, String>{};
  for (var a in apps) {
    final pkg = a['packageName'] as String;
    appNameLower[pkg] = (a['name'] as String).toLowerCase();
    appPkgLower[pkg] = pkg.toLowerCase();
  }

  apps.sort((a, b) {
    final aSel = selected.contains(a['packageName'] as String);
    final bSel = selected.contains(b['packageName'] as String);
    if (aSel == bSel) {
      return (a['name'] as String).toLowerCase().compareTo(
        (b['name'] as String).toLowerCase(),
      );
    }
    return aSel ? -1 : 1;
  });

  return {
    'sortedApps': apps,
    'selectedList': selected.toList(),
    'appNameLower': appNameLower,
    'appPkgLower': appPkgLower,
  };
}

class AppSelectionScreen extends StatefulWidget {
  final ConfigType configType;

  const AppSelectionScreen({super.key, required this.configType});

  @override
  State<AppSelectionScreen> createState() => _AppSelectionScreenState();
}

class _AppSelectionScreenState extends State<AppSelectionScreen> {
  // 用于实现自动保存的防抖计时器
  Timer? _debounceTimer;
  // 是否正在加载数据的标志
  bool _isLoading = true;
  // “关键词”区域是否展开的UI状态
  bool _isKeywordsSectionExpanded = false;

  // 存储设备上所有已安装的应用信息
  List<AppInfo> _installedApps = [];
  // 实际在列表中显示的应用信息（用于懒加载）
  List<AppInfo> _displayApps = [];
  // 包名到 AppInfo 对象的映射，方便快速查找
  Map<String, AppInfo> _appInfoMap = {};
  // 存储所有被用户勾选的应用的包名
  final Set<String> _selectedPackages = {};
  // 存储页面加载时的初始勾选状态，用于在页面销毁时判断是否有变动
  Set<String> _initialSelectedPackages = {};

  // 存储辅助功能（ACC）的提取规则
  List<Map<String, dynamic>> _extractionRules = [];
  // 用于将 JSON 对象格式化为带缩进的字符串，方便在对话框中展示
  final JsonEncoder _jsonEncoder = const JsonEncoder.withIndent('   ');

  // 搜索框的查询字符串
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // 存储通知监听（NL）的关键词列表
  List<String> _keywords = [];
  final TextEditingController _keywordController = TextEditingController();

  // 这是一个写入操作队列，用于确保所有文件/配置写入操作按顺序执行，避免竞态条件
  final Queue<Future<void> Function()> _writeQueue =
      Queue<Future<void> Function()>();
  // 标记当前是否正在处理队列中的任务
  bool _isProcessingQueue = false;

  // 缓存小写的应用名和包名，以加速搜索
  final Map<String, String> _appNameLower = {};
  final Map<String, String> _appPkgLower = {};

  // ListView 的滚动控制器，用于监听滚动事件以实现懒加载
  final ScrollController _scrollController = ScrollController();
  // 懒加载时每页加载的项目数量
  final int _pageSize = 50;
  // 当前已加载到 _displayApps 中的项目数量
  int _loadedItems = 0;

  List<AppInfo> _filteredApps = [];

  @override
  void initState() {
    super.initState();
    _loadData();
    // 添加滚动监听器
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    // 组件销毁前，取消可能仍在活动的防抖计时器
    if (_debounceTimer?.isActive ?? false) {
      _debounceTimer!.cancel();
      _debounceTimer = null;
    }

    // 检查用户的勾选状态是否有变化
    final hasChanged = !setEquals(_initialSelectedPackages, _selectedPackages);

    // 如果有变化，则在后台执行一次最终的保存操作，确保用户更改不会丢失
    if (hasChanged) {
      _writeAppSelectionNoUi();
    }

    _searchController.dispose();
    _keywordController.dispose();
    super.dispose();
  }

  /// 滚动事件监听器
  void _onScroll() {
    // 如果正在搜索，则不执行懒加载（因为搜索结果已全部显示）
    if (_searchQuery.isNotEmpty) return;

    // 当滚动到距离列表底部300像素范围内，并且还有未加载的应用时，触发加载更多
    if (_scrollController.position.pixels >
            _scrollController.position.maxScrollExtent - 300 &&
        _loadedItems < _installedApps.length) {
      _loadMoreItems();
    }
  }

  /// 加载更多应用到显示列表中
  void _loadMoreItems() {
    final remaining = _installedApps.length - _loadedItems;
    final toLoad = remaining >= _pageSize ? _pageSize : remaining;
    if (toLoad <= 0) return;
    setState(() {
      _displayApps.addAll(
        _installedApps.skip(_loadedItems).take(toLoad).toList(growable: false),
      );
      _loadedItems += toLoad;
    });
  }

  /// 将一个写入任务添加到队列中。
  /// 返回一个 Future，该 Future 在任务完成时完成。
  Future<void> _enqueueWrite(Future<void> Function() task) {
    final completer = Completer<void>();
    _writeQueue.add(() async {
      try {
        await task();
        if (!completer.isCompleted) completer.complete();
      } catch (e, st) {
        debugPrint('Write task error: $e\n$st');
        if (!completer.isCompleted) {
          try {
            completer.completeError(e, st);
          } catch (_) {
            // ignore
          }
        }
        // 这里不 rethrow，是为了让队列能够继续执行后续的任务
      }
    });

    // 如果队列当前没有在处理，则开始处理
    if (!_isProcessingQueue) _processWriteQueue();
    return completer.future;
  }

  /// 循环处理写入队列中的所有任务，直到队列为空
  Future<void> _processWriteQueue() async {
    _isProcessingQueue = true;
    while (_writeQueue.isNotEmpty) {
      final fn = _writeQueue.removeFirst();
      try {
        await fn();
      } catch (e, st) {
        // 这里的捕获是为了防止单个任务失败导致整个队列处理中断
        debugPrint('Error executing queued write: $e\n$st');
      }
    }
    _isProcessingQueue = false;
  }

  /// 异步加载所有需要的数据（应用列表、配置等）
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // installed_apps更新后需要使用命名参数
      final apps = await InstalledApps.getInstalledApps(
        excludeSystemApps: true,
        withIcon: true,
      );
      final appInfoMap = {for (var app in apps) app.packageName: app};

      final rawConfigData =
          widget.configType == ConfigType.acc
              ? await NativeMethodChannel.instance.getAbAllowPackageConfig()
              : await NativeMethodChannel.instance.getNlAllowPackageConfig();

      final configPackages =
          rawConfigData?.map((data) => PackageConfig.fromJson(data)).toList() ??
          [];

      final minimalApps =
          apps
              .map((a) => {'name': a.name, 'packageName': a.packageName})
              .toList();

      final minimalConfig =
          configPackages
              .map(
                (c) => {
                  'appName': c.appName,
                  'packageName': c.packageName,
                  'isAllowed': c.isAllowed,
                },
              )
              .toList();

      final result = await compute(_processAppsInIsolate, {
        'apps': minimalApps,
        'config': minimalConfig,
      });

      if (!mounted) return;

      setState(() {
        final sortedMinimal = List<Map<String, dynamic>>.from(
          result['sortedApps'] as List,
        );

        final fullList = sortedMinimal
            .map((m) => appInfoMap[m['packageName']]!)
            .toList(growable: false);

        _installedApps = fullList;

        _loadedItems =
            fullList.length >= _pageSize ? _pageSize : fullList.length;
        _displayApps = fullList.take(_loadedItems).toList();
        _appInfoMap = appInfoMap;

        _selectedPackages
          ..clear()
          ..addAll(List<String>.from(result['selectedList'] as List));

        _initialSelectedPackages = Set<String>.from(_selectedPackages);

        _appNameLower
          ..clear()
          ..addAll(Map<String, String>.from(result['appNameLower'] as Map));
        _appPkgLower
          ..clear()
          ..addAll(Map<String, String>.from(result['appPkgLower'] as Map));

        _isLoading = false;
      });

      if (widget.configType == ConfigType.acc) {
        _extractionRules =
            await NativeMethodChannel.instance.getExtractionRules();
      }
      if (widget.configType == ConfigType.nl) {
        final savedKeywords =
            await NativeMethodChannel.instance.getAllowKeywords();
        _keywords = savedKeywords ?? [];
      }
    } catch (e, st) {
      debugPrint('Failed to load data: $e\n$st');
      if (mounted) {
        showNoticeSnackBar(context, '加载应用列表失败: $e');
        setState(() => _isLoading = false);
      }
    }
  }

  // 根据当前搜索查询返回需要显示的应用列表
  List<AppInfo> get _visibleApps {
    if (_searchQuery.trim().isNotEmpty) {
      return _filteredApps;
    }
    return _displayApps;
  }

  /// getter，返回当前已勾选的应用数量
  int get _selectedCount => _selectedPackages.length;

  /// 显示一个包含所有提取规则的对话框
  Future<void> _showAllRulesDialog() async {
    final allRulesJson = _jsonEncoder.convert(_extractionRules);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('全部规则'),
          content: SingleChildScrollView(
            child: SelectableText(
              allRulesJson,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _performSaveAction({
    required Future<void> Function() saveFunction,
    required String successMessage,
    String? errorMessage,
  }) async {
    if (!mounted) {
      try {
        await saveFunction();
      } catch (e, st) {
        debugPrint('Save failed while not mounted: $e\n$st');
      }
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (BuildContext context) =>
              const Center(child: CircularProgressIndicator()),
    );

    var dialogClosed = false;
    try {
      await saveFunction();
      if (!mounted) return;
      try {
        Navigator.of(context, rootNavigator: true).pop();
        dialogClosed = true;
      } catch (_) {
        // 忽略可能出现的错误
      }
      showNoticeSnackBar(context, successMessage);
    } catch (e, st) {
      debugPrint('Save error: $e\n$st');
      if (mounted) {
        if (!dialogClosed) {
          try {
            Navigator.of(context, rootNavigator: true).pop();
          } catch (_) {}
        }
        showNoticeSnackBar(context, '${errorMessage ?? '操作失败'}: $e');
      }
    }
  }

  Future<void> _writeAppSelectionNoUi() {
    return _enqueueWrite(() async {
      final List<Map<String, dynamic>> updatedConfig =
          _selectedPackages.map((packageName) {
            final app = _appInfoMap[packageName];
            return {
              'appName': app?.name ?? '',
              'packageName': packageName,
              'isAllowed': true,
            };
          }).toList();

      if (widget.configType == ConfigType.acc) {
        await NativeMethodChannel.instance.putAbAllowPackageConfig(
          updatedConfig,
        );
        await ConfigService().setSavedAccConfig(true);
      } else {
        await NativeMethodChannel.instance.putNlAllowPackageConfig(
          updatedConfig,
        );
        await ConfigService().setSavedNlConfig(true);
      }
    });
  }

  Future<void> _saveAppSelection({bool showUi = true}) async {
    if (!showUi) {
      await _writeAppSelectionNoUi();
      return;
    }

    await _performSaveAction(
      saveFunction: _writeAppSelectionNoUi,
      successMessage: '应用选择已保存',
      errorMessage: '保存应用选择失败',
    );
  }

  Future<void> _saveExtractionRules() async {
    await _performSaveAction(
      saveFunction:
          () => _enqueueWrite(() async {
            await NativeMethodChannel.instance.putExtractionRules(
              _extractionRules,
            );
          }),
      successMessage: '提取规则已保存',
      errorMessage: '保存提取规则失败',
    );
  }

  /// 保存关键词
  Future<void> _saveKeywords() async {
    try {
      await _enqueueWrite(() async {
        await NativeMethodChannel.instance.putAllowKeywords(_keywords);
      });
      if (mounted) {
        showNoticeSnackBar(context, '关键词已更新');
      }
    } catch (e, st) {
      debugPrint('保存关键词失败: $e\n$st');
      if (mounted) {
        showNoticeSnackBar(context, '更新关键词失败: $e');
      }
    }
  }

  void _onAppSelectionChanged(String packageName, bool? isSelected) {
    if (isSelected == null) return;
    setState(() {
      if (isSelected) {
        _selectedPackages.add(packageName);
      } else {
        _selectedPackages.remove(packageName);
      }
    });

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _saveAppSelection(showUi: false);
      _debounceTimer = null;
    });
  }

  Future<void> _showRuleEditorDialog(String packageName) async {
    final rulesForPackage =
        _extractionRules
            .where((rule) => rule['packageName'] == packageName)
            .toList();

    final String initialText;
    if (rulesForPackage.isEmpty) {
      final defaultRule = [
        {
          "ruleName": "Rule for $packageName",
          "packageName": packageName,
          "activityName": "",
          "continueOnContentFailure": true,
          "allowContentChangeTrigger": true,
          "triggerOnEmptyNodes": false,
          "preFilterByKeywords": false,
          "contentRules": [
            {
              "keywords": ["请填写关键字"],
              "strategy": {
                "type": "ExtractByViewId",
                "viewId": "在此处填写控件ID(如: amount_text)",
                "useExactMatch": false,
              },
            },
          ],
          "paymentRules": [
            {
              "keywords": ["请填写关键字"],
              "strategy": {
                "type": "SimpleOffset",
                "offset": 1,
                "useExactMatch": false,
              },
            },
          ],
        },
      ];
      initialText = _jsonEncoder.convert(defaultRule);
    } else {
      initialText = _jsonEncoder.convert(rulesForPackage);
    }

    final controller = TextEditingController(text: initialText);

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('编辑规则: $packageName'),
          content: TextField(
            controller: controller,
            maxLines: 15,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '输入 JSON 格式的规则',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                try {
                  final newRulesJson = controller.text;
                  final decoded = jsonDecode(newRulesJson);

                  if (decoded is! List) {
                    throw Exception('JSON 顶层必须是数组 (List)。');
                  }

                  final newRulesForPackage = <Map<String, dynamic>>[];
                  for (var i = 0; i < decoded.length; i++) {
                    final item = decoded[i];
                    if (item is! Map) {
                      throw Exception('第 ${i + 1} 项不是对象 (Map)。');
                    }
                    final map = Map<String, dynamic>.from(item);
                    if (map['packageName'] != packageName) {
                      throw Exception(
                        '第 ${i + 1} 项的 packageName 必须是 "$packageName"。',
                      );
                    }

                    final activityName = map['activityName'];
                    if (activityName == null ||
                        (activityName is! String) ||
                        activityName.trim().isEmpty) {
                      throw Exception('第 ${i + 1} 项规则缺少有效的 activityName 字段。');
                    }

                    newRulesForPackage.add(map);
                  }

                  setState(() {
                    _extractionRules.removeWhere(
                      (rule) => rule['packageName'] == packageName,
                    );
                    _extractionRules.addAll(newRulesForPackage);
                  });
                  Navigator.of(context).pop();
                  _saveExtractionRules();
                } catch (e) {
                  showNoticeSnackBar(context, '保存失败: $e');
                }
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  /// 添加关键词
  void _addKeyword() {
    final keyword = _keywordController.text.trim();
    if (keyword.isNotEmpty && !_keywords.contains(keyword)) {
      setState(() {
        _keywords.add(keyword);
        _keywordController.clear();
      });
      FocusScope.of(context).unfocus();
      _saveKeywords();
    } else {
      final String errorMessage;
      if (keyword.isEmpty) {
        errorMessage = '关键词不能为空';
      } else {
        errorMessage = '关键词 "$keyword" 已存在';
      }
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  void _removeKeyword(String keyword) {
    setState(() {
      _keywords.remove(keyword);
    });
    _saveKeywords();
  }

  String _getTitle() {
    switch (widget.configType) {
      case ConfigType.acc:
        return '配置辅助功能应用';
      case ConfigType.nl:
        return '配置通知监听';
    }
  }

  void _updateFilteredApps() {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) {
      _filteredApps.clear();
    } else {
      _filteredApps =
          _installedApps.where((app) {
            final nameLower = _appNameLower[app.packageName] ?? '';
            final pkgLower = _appPkgLower[app.packageName] ?? '';
            return nameLower.contains(q) || pkgLower.contains(q);
          }).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getTitle()),
        actions: [
          if (widget.configType == ConfigType.acc)
            IconButton(
              icon: const Icon(Icons.description_outlined),
              tooltip: '查看所有规则',
              onPressed: _showAllRulesDialog,
            ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child:
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildListView(),
          ),
          if (widget.configType == ConfigType.nl) _buildKeywordsSection(),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color:
                    Theme.of(context).inputDecorationTheme.fillColor ??
                    Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                          _updateFilteredApps(); // 调用新的过滤方法
                        });
                      },
                      decoration: const InputDecoration(
                        hintText: '搜索应用名或包名',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建应用列表UI
  Widget _buildListView() {
    final visible = _visibleApps;
    if (visible.isEmpty) {
      return Center(
        child: Text(
          _installedApps.isEmpty
              ? '未发现已安装的应用'
              : (_searchQuery.isEmpty
                  ? '没有可显示的应用'
                  : '未找到匹配 "$_searchQuery" 的应用'),
        ),
      );
    }

    return Scrollbar(
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: visible.length,
        itemBuilder: (context, index) {
          final app = visible[index];
          final isChecked = _selectedPackages.contains(app.packageName);
          return ListTile(
            key: ValueKey(app.packageName),
            onTap: () {
              _onAppSelectionChanged(app.packageName, !isChecked);
            },
            leading:
                app.icon != null
                    ? Image.memory(
                      app.icon!,
                      width: 40,
                      height: 40,
                      gaplessPlayback: true,
                    )
                    : const Icon(Icons.apps, size: 40),
            title: Text(app.name),
            subtitle: Text(
              app.packageName,
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.configType == ConfigType.acc)
                  IconButton(
                    icon: const Icon(Icons.edit_note),
                    tooltip: '编辑提取规则',
                    onPressed: () => _showRuleEditorDialog(app.packageName),
                  ),
                Checkbox(
                  value: isChecked,
                  onChanged: (bool? newValue) {
                    _onAppSelectionChanged(app.packageName, newValue);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color:
            Theme.of(context).bottomAppBarTheme.color ??
            Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            offset: const Offset(0, -1),
            blurRadius: 4,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Text(
              '已选择: $_selectedCount',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeywordsSection() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      constraints: BoxConstraints(
        maxHeight: _isKeywordsSectionExpanded ? 180 : 73,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey.shade300, width: 1.0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    _isKeywordsSectionExpanded = !_isKeywordsSectionExpanded;
                  });
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 1,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '关键词',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        _isKeywordsSectionExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _keywordController,
                    onSubmitted: (_) => _addKeyword(),
                    onTap: () {
                      if (!_isKeywordsSectionExpanded) {
                        setState(() {
                          _isKeywordsSectionExpanded = true;
                        });
                      }
                    },
                    decoration: const InputDecoration(
                      hintText: '输入关键词',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: _addKeyword, child: const Text('添加')),
            ],
          ),
          if (_isKeywordsSectionExpanded) ...[
            const SizedBox(height: 8),
            Expanded(
              child:
                  _keywords.isEmpty
                      ? const Center(
                        child: Text(
                          '未添加关键词。如果列表为空，则只匹配金额。',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                      : SingleChildScrollView(
                        child: Wrap(
                          spacing: 8.0,
                          runSpacing: 3.0,
                          children:
                              _keywords.map((keyword) {
                                return Chip(
                                  label: Text(keyword),
                                  onDeleted: () => _removeKeyword(keyword),
                                  deleteIcon: const Icon(
                                    Icons.cancel,
                                    size: 18,
                                  ),
                                );
                              }).toList(),
                        ),
                      ),
            ),
          ],
        ],
      ),
    );
  }
}
