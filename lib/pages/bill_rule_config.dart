import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tools/bill_parse_rule.dart';
import '../tools/config_service.dart';
import '../tools/native_method_channel.dart';
import '../tools/tools.dart';
import '../widgets/bill_rule_json_editor_dialog.dart';

enum BillRuleEditorMode { form, json }

class BillRuleConfigPage extends StatefulWidget {
  const BillRuleConfigPage({super.key});

  @override
  State<BillRuleConfigPage> createState() => _BillRuleConfigPageState();
}

class _BillRuleConfigPageState extends State<BillRuleConfigPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  List<BillParseRule> _rules = [];
  final Map<String, String> _packageLabels = {globalBillRulePackage: '预置规则'};
  List<String> _accounts = [];
  List<String> _consumeCategories = [];
  List<String> _incomeCategories = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait<dynamic>([
        ConfigService().getBillParseRulesJson(),
        NativeMethodChannel.instance.getAbAllowPackageConfig(),
        NativeMethodChannel.instance.getNlAllowPackageConfig(),
        getAccount(),
        getCategory('consume'),
        getCategory('income'),
      ]);

      final document = BillParseRuleDocument.fromJsonString(
        results[0] as String,
      );
      final packageLabels = <String, String>{globalBillRulePackage: '预置规则'};
      for (final rawList in [results[1], results[2]]) {
        if (rawList is! List) continue;
        for (final item in rawList) {
          if (item is! Map) continue;
          final packageName = item['packageName']?.toString() ?? '';
          if (packageName.isEmpty) continue;
          packageLabels[packageName] =
              item['appName']?.toString().trim().isNotEmpty == true
                  ? item['appName'].toString()
                  : packageName;
        }
      }
      for (final rule in document.rules) {
        packageLabels.putIfAbsent(rule.packageName, () => rule.packageName);
      }

      if (!mounted) return;
      setState(() {
        _rules = document.rules.toList();
        _packageLabels
          ..clear()
          ..addAll(packageLabels);
        _accounts = List<String>.from((results[3] as List)[0] as List);
        _consumeCategories = _flattenCategories((results[4] as List)[0]);
        _incomeCategories = _flattenCategories((results[5] as List)[0]);
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showNoticeSnackBar(context, '加载解析规则失败: $error');
    }
  }

  List<String> _flattenCategories(dynamic raw) {
    if (raw is! List) return [];
    final result = <String>[];
    for (final group in raw) {
      if (group is! Map) continue;
      for (final value in group.values) {
        if (value is List) {
          result.addAll(value.map((item) => item.toString()));
        }
      }
    }
    return result;
  }

  List<BillParseRule> get _sortedRules {
    final indexed = _rules.asMap().entries.toList();
    indexed.sort((left, right) {
      final packageCompare = left.value.packageName.compareTo(
        right.value.packageName,
      );
      if (packageCompare != 0) return packageCompare;
      final priority = right.value.priority.compareTo(left.value.priority);
      return priority != 0 ? priority : left.key.compareTo(right.key);
    });
    return indexed.map((entry) => entry.value).toList(growable: false);
  }

  Future<void> _persistRules(
    List<BillParseRule> nextRules, {
    String? message,
  }) async {
    setState(() => _isSaving = true);
    try {
      final document = BillParseRuleDocument(rules: nextRules);
      await ConfigService().setBillParseRulesJson(document.toJsonString());
      if (!mounted) return;
      setState(() {
        _rules = nextRules;
        for (final rule in nextRules) {
          _packageLabels.putIfAbsent(rule.packageName, () => rule.packageName);
        }
        _isSaving = false;
      });
      if (message != null) showNoticeSnackBar(context, message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      showNoticeSnackBar(context, '保存规则失败: $error');
    }
  }

  Future<void> _editRule({
    BillParseRule? current,
    BillRuleEditorMode initialMode = BillRuleEditorMode.form,
  }) async {
    final initialRule =
        current ??
        BillParseRule(
          id: 'rule-${DateTime.now().microsecondsSinceEpoch}',
          name: '新规则',
          packageName: globalBillRulePackage,
          enabled: true,
          priority: 100,
          titleContainsAny: const [],
          contentContainsAny: const [],
          paymentContainsAny: const [],
          amountSource: BillRuleTextSource.content,
          amountPattern: r'(\d+(?:\.\d{1,2})?)',
          amountGroup: 1,
          flow: BillRuleFlow.consume,
        );
    final rule = await showModalBottomSheet<BillParseRule>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder:
          (context) => BillRuleEditorSheet(
            rule: initialRule,
            isNew: current == null,
            initialMode: initialMode,
            reservedRuleIds:
                _rules
                    .where((rule) => rule.id != current?.id)
                    .map((rule) => rule.id)
                    .toSet(),
            packageLabels: _packageLabels,
            accounts: _accounts,
            consumeCategories: _consumeCategories,
            incomeCategories: _incomeCategories,
          ),
    );
    if (!mounted || rule == null) return;

    final nextRules = _rules.toList();
    final originalIndex =
        current == null
            ? -1
            : nextRules.indexWhere((item) => item.id == current.id);
    final duplicateIndex = nextRules.indexWhere((item) => item.id == rule.id);
    if (duplicateIndex != -1 && duplicateIndex != originalIndex) {
      showNoticeSnackBar(context, '规则 ID "${rule.id}" 已存在');
      return;
    }

    if (originalIndex == -1) {
      nextRules.add(rule);
    } else {
      nextRules[originalIndex] = rule;
    }
    await _persistRules(
      nextRules,
      message: current == null ? '规则已添加' : '规则已更新',
    );
  }

  Future<void> _setEnabled(BillParseRule rule, bool enabled) async {
    final nextRules = _rules
        .map(
          (item) => item.id == rule.id ? item.copyWith(enabled: enabled) : item,
        )
        .toList(growable: false);
    await _persistRules(nextRules);
  }

  Future<void> _deleteRule(BillParseRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('删除规则'),
            content: Text('确定删除“${rule.name}”吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('删除'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    await _persistRules(
      _rules.where((item) => item.id != rule.id).toList(growable: false),
      message: '规则已删除',
    );
  }

  Future<void> _restoreDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('恢复默认规则'),
            content: const Text('当前自定义规则将被替换。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('恢复'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    final defaults = BillParseRuleDocument.defaults();
    await _persistRules(defaults.rules.toList(), message: '已恢复默认规则');
  }

  Future<void> _showJsonEditor() async {
    final document = await showDialog<BillParseRuleDocument>(
      context: context,
      builder:
          (context) => BillRuleJsonEditorDialog(
            initialDocument: BillParseRuleDocument(rules: _rules),
          ),
    );
    if (document == null) return;
    await _persistRules(document.rules.toList(), message: 'JSON 规则已保存');
  }

  Future<void> _importJsonFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw const FormatException('无法读取所选文件');
      }

      final source = utf8.decode(bytes).replaceFirst('\uFEFF', '');
      final imported = BillParseRuleDocument.fromJsonString(source);
      final importedById = {for (final rule in imported.rules) rule.id: rule};
      final overrideCount =
          _rules.where((rule) => importedById.containsKey(rule.id)).length;

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('导入规则'),
              content: Text(
                '将合并 ${imported.rules.length} 条规则'
                '${overrideCount == 0 ? '' : '，覆盖 $overrideCount 条同 ID 规则'}。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('合并导入'),
                ),
              ],
            ),
      );
      if (confirmed != true) return;

      final remaining = Map<String, BillParseRule>.from(importedById);
      final nextRules =
          _rules.map((rule) => remaining.remove(rule.id) ?? rule).toList()
            ..addAll(remaining.values);
      await _persistRules(
        nextRules,
        message: '已导入 ${imported.rules.length} 条规则',
      );
    } on FormatException catch (error) {
      if (mounted) showNoticeSnackBar(context, '导入失败: ${error.message}');
    } catch (error) {
      if (mounted) showNoticeSnackBar(context, '导入失败: $error');
    }
  }

  String _packageTitle(String packageName) {
    final label = _packageLabels[packageName];
    if (label == null || label == packageName) return packageName;
    return '$label  $packageName';
  }

  String _sourceLabel(BillRuleTextSource source) {
    switch (source) {
      case BillRuleTextSource.title:
        return '标题';
      case BillRuleTextSource.content:
        return '内容';
      case BillRuleTextSource.payment:
        return '支付方式';
    }
  }

  String _flowLabel(BillRuleFlow flow) {
    switch (flow) {
      case BillRuleFlow.consume:
        return '支出';
      case BillRuleFlow.income:
        return '收入';
      case BillRuleFlow.transfer:
        return '转账';
    }
  }

  Widget _buildRuleTile(BillParseRule rule, bool showPackageHeader) {
    final defaults = [
      if (rule.accountName != null) rule.accountName!,
      if (rule.categoryName != null) rule.categoryName!,
    ].join(' / ');
    final extraction =
        rule.amountPattern.isEmpty
            ? '金额留空'
            : '${_sourceLabel(rule.amountSource)} · 组 ${rule.amountGroup}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showPackageHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
            child: Row(
              children: [
                Text(
                  _packageTitle(rule.packageName),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (rule.packageName == globalBillRulePackage) ...[
                  const SizedBox(width: 3),
                  Tooltip(
                    message: '规则匹配将首先匹配packageName，如果未匹配成功则使用预置规则',
                    triggerMode: TooltipTriggerMode.tap,
                    showDuration: const Duration(seconds: 5),
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(Icons.info_outline, size: 16),
                  ),
                ],
              ],
            ),
          ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          child: ListTile(
            onTap: _isSaving ? null : () => _editRule(current: rule),
            title: Text(rule.name),
            subtitle: Text(
              '优先级 ${rule.priority} · ${_flowLabel(rule.flow)} · $extraction'
              '${defaults.isEmpty ? '' : '\n$defaults'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            leading: Switch(
              value: rule.enabled,
              onChanged: _isSaving ? null : (value) => _setEnabled(rule, value),
            ),
            trailing: PopupMenuButton<String>(
              tooltip: '规则操作',
              onSelected: (value) {
                if (value == 'edit') _editRule(current: rule);
                if (value == 'delete') _deleteRule(rule);
              },
              itemBuilder:
                  (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('编辑')),
                    PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final rules = _sortedRules;
    return Scaffold(
      appBar: AppBar(
        title: const Text('账单解析规则'),
        actions: [
          IconButton(
            tooltip: '导入 JSON 文件',
            icon: const Icon(Icons.file_open),
            onPressed: _isLoading || _isSaving ? null : _importJsonFile,
          ),
          IconButton(
            tooltip: 'JSON',
            icon: const Icon(Icons.code),
            onPressed: _isLoading || _isSaving ? null : _showJsonEditor,
          ),
          IconButton(
            tooltip: '恢复默认规则',
            icon: const Icon(Icons.restore),
            onPressed: _isLoading || _isSaving ? null : _restoreDefaults,
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : rules.isEmpty
              ? const Center(child: Text('暂无解析规则'))
              : ListView.builder(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: rules.length,
                itemBuilder: (context, index) {
                  final rule = rules[index];
                  final showHeader =
                      index == 0 ||
                      rules[index - 1].packageName != rule.packageName;
                  return _buildRuleTile(rule, showHeader);
                },
              ),
      floatingActionButton: FloatingActionButton(
        tooltip: '添加规则',
        onPressed:
            _isLoading || _isSaving
                ? null
                : () => _editRule(initialMode: BillRuleEditorMode.form),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class BillRuleEditorSheet extends StatefulWidget {
  final BillParseRule rule;
  final bool isNew;
  final BillRuleEditorMode initialMode;
  final Set<String> reservedRuleIds;
  final Map<String, String> packageLabels;
  final List<String> accounts;
  final List<String> consumeCategories;
  final List<String> incomeCategories;

  const BillRuleEditorSheet({
    super.key,
    required this.rule,
    required this.isNew,
    required this.initialMode,
    required this.reservedRuleIds,
    required this.packageLabels,
    required this.accounts,
    required this.consumeCategories,
    required this.incomeCategories,
  });

  @override
  State<BillRuleEditorSheet> createState() => _BillRuleEditorSheetState();
}

class _BillRuleEditorSheetState extends State<BillRuleEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _packageController;
  late final TextEditingController _priorityController;
  late final TextEditingController _titleKeywordsController;
  late final TextEditingController _contentKeywordsController;
  late final TextEditingController _paymentKeywordsController;
  late final TextEditingController _patternController;
  late final TextEditingController _groupController;
  late final TextEditingController _commentController;
  late final TextEditingController _testTitleController;
  late final TextEditingController _testContentController;
  late final TextEditingController _testPaymentController;
  late final TextEditingController _jsonController;
  late String _ruleId;
  late BillRuleEditorMode _editorMode;
  late bool _enabled;
  late BillRuleTextSource _amountSource;
  late BillRuleFlow _flow;
  String? _accountName;
  String? _categoryName;
  String? _testResult;
  String? _jsonError;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    _nameController = TextEditingController(text: rule.name);
    _packageController = TextEditingController(text: rule.packageName);
    _priorityController = TextEditingController(text: '${rule.priority}');
    _titleKeywordsController = TextEditingController(
      text: rule.titleContainsAny.join(', '),
    );
    _contentKeywordsController = TextEditingController(
      text: rule.contentContainsAny.join(', '),
    );
    _paymentKeywordsController = TextEditingController(
      text: rule.paymentContainsAny.join(', '),
    );
    _patternController = TextEditingController(text: rule.amountPattern);
    _groupController = TextEditingController(text: '${rule.amountGroup}');
    _commentController = TextEditingController(text: rule.commentTemplate);
    _testTitleController = TextEditingController();
    _testContentController = TextEditingController();
    _testPaymentController = TextEditingController();
    _jsonController = TextEditingController(
      text: rule.toJsonString(pretty: true),
    );
    _ruleId = rule.id;
    _editorMode = widget.initialMode;
    _enabled = rule.enabled;
    _amountSource = rule.amountSource;
    _flow = rule.flow;
    _accountName = rule.accountName;
    _categoryName = rule.categoryName;
  }

  @override
  void dispose() {
    for (final controller in [
      _nameController,
      _packageController,
      _priorityController,
      _titleKeywordsController,
      _contentKeywordsController,
      _paymentKeywordsController,
      _patternController,
      _groupController,
      _commentController,
      _testTitleController,
      _testContentController,
      _testPaymentController,
      _jsonController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  List<String> _parseKeywords(String value) {
    return value
        .split(RegExp(r'[,，\n]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  List<String> get _categoryOptions {
    switch (_flow) {
      case BillRuleFlow.consume:
        return widget.consumeCategories;
      case BillRuleFlow.income:
        return widget.incomeCategories;
      case BillRuleFlow.transfer:
        return const [];
    }
  }

  BillParseRule? _buildRule() {
    if (_formKey.currentState?.validate() != true) return null;
    try {
      final rule = BillParseRule(
        id: _ruleId,
        name: _nameController.text.trim(),
        packageName: _packageController.text.trim(),
        enabled: _enabled,
        priority: int.parse(_priorityController.text),
        titleContainsAny: _parseKeywords(_titleKeywordsController.text),
        contentContainsAny: _parseKeywords(_contentKeywordsController.text),
        paymentContainsAny: _parseKeywords(_paymentKeywordsController.text),
        amountSource: _amountSource,
        amountPattern: _patternController.text,
        amountGroup: int.parse(_groupController.text),
        flow: _flow,
        accountName: _accountName,
        categoryName: _flow == BillRuleFlow.transfer ? null : _categoryName,
        commentTemplate:
            _commentController.text.trim().isEmpty
                ? null
                : _commentController.text,
      );
      rule.validate();
      if (widget.reservedRuleIds.contains(rule.id)) {
        throw FormatException('规则 ID "${rule.id}" 已存在');
      }
      return rule;
    } on FormatException catch (error) {
      setState(() => _testResult = error.message);
      return null;
    }
  }

  BillParseRule? _buildJsonRule() {
    try {
      final rule = BillParseRule.fromJsonString(_jsonController.text);
      if (widget.reservedRuleIds.contains(rule.id)) {
        throw FormatException('规则 ID "${rule.id}" 已存在');
      }
      setState(() => _jsonError = null);
      return rule;
    } on FormatException catch (error) {
      setState(() => _jsonError = error.message);
      return null;
    }
  }

  void _applyRuleToForm(BillParseRule rule) {
    _ruleId = rule.id;
    _nameController.text = rule.name;
    _packageController.text = rule.packageName;
    _priorityController.text = '${rule.priority}';
    _titleKeywordsController.text = rule.titleContainsAny.join(', ');
    _contentKeywordsController.text = rule.contentContainsAny.join(', ');
    _paymentKeywordsController.text = rule.paymentContainsAny.join(', ');
    _patternController.text = rule.amountPattern;
    _groupController.text = '${rule.amountGroup}';
    _commentController.text = rule.commentTemplate ?? '';
    _enabled = rule.enabled;
    _amountSource = rule.amountSource;
    _flow = rule.flow;
    _accountName = rule.accountName;
    _categoryName = rule.categoryName;
  }

  void _switchEditorMode(BillRuleEditorMode nextMode) {
    if (nextMode == _editorMode) return;

    if (nextMode == BillRuleEditorMode.json) {
      final rule = _buildRule();
      if (rule == null) return;
      _jsonController.text = rule.toJsonString(pretty: true);
      setState(() {
        _jsonError = null;
        _editorMode = nextMode;
      });
      return;
    }

    final rule = _buildJsonRule();
    if (rule == null) return;
    setState(() {
      _applyRuleToForm(rule);
      _editorMode = nextMode;
    });
  }

  void _saveCurrentRule() {
    if (_saveError != null) setState(() => _saveError = null);
    final rule =
        _editorMode == BillRuleEditorMode.form
            ? _buildRule()
            : _buildJsonRule();
    if (rule == null) return;
    if (widget.isNew && rule.toJsonString() == widget.rule.toJsonString()) {
      setState(() => _saveError = '请输入规则');
      return;
    }
    Navigator.of(context).pop(rule);
  }

  Widget _buildJsonEditor() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('复制'),
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: _jsonController.text),
                  );
                },
              ),
              TextButton.icon(
                icon: const Icon(Icons.paste),
                label: const Text('粘贴'),
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (!mounted || data?.text == null) return;
                  _jsonController.text = data!.text!;
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TextField(
              controller: _jsonController,
              expands: true,
              minLines: null,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              onChanged: (_) {
                if (_jsonError != null) setState(() => _jsonError = null);
              },
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                errorText: _jsonError,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _runTest() {
    final rule = _buildRule();
    if (rule == null) return;
    final enabledRule = rule.copyWith(enabled: true);
    final engine = BillParseRuleEngine(
      BillParseRuleDocument(rules: [enabledRule]),
    );
    final packageName =
        enabledRule.packageName == globalBillRulePackage
            ? 'test.package'
            : enabledRule.packageName;
    final result = engine.match(
      RawPendingBill(
        id: 'test',
        packageName: packageName,
        appName: '测试应用',
        title: _testTitleController.text,
        content: _testContentController.text,
        payment: _testPaymentController.text,
        postTime: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    setState(() {
      _testResult =
          result == null
              ? '未命中'
              : '已命中 · 金额 ${result.amount ?? '留空'} · '
                  '${_flowText(result.rule.flow)}'
                  '${result.comment == null ? '' : ' · ${result.comment}'}';
    });
  }

  String _flowText(BillRuleFlow flow) {
    switch (flow) {
      case BillRuleFlow.consume:
        return '支出';
      case BillRuleFlow.income:
        return '收入';
      case BillRuleFlow.transfer:
        return '转账';
    }
  }

  String _sourceText(BillRuleTextSource source) {
    switch (source) {
      case BillRuleTextSource.title:
        return '标题';
      case BillRuleTextSource.content:
        return '内容';
      case BillRuleTextSource.payment:
        return '支付方式';
    }
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountOptions =
        {...widget.accounts, if (_accountName != null) _accountName!}.toList();
    final categoryOptions =
        {
          ..._categoryOptions,
          if (_categoryName != null) _categoryName!,
        }.toList();

    return FractionallySizedBox(
      heightFactor: 0.94,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Text(
                  widget.isNew ? '新增规则' : '编辑规则',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  tooltip: '关闭',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: SegmentedButton<BillRuleEditorMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: BillRuleEditorMode.form,
                  icon: Icon(Icons.tune),
                  label: Text('表单'),
                ),
                ButtonSegment(
                  value: BillRuleEditorMode.json,
                  icon: Icon(Icons.code),
                  label: Text('JSON'),
                ),
              ],
              selected: {_editorMode},
              onSelectionChanged: (values) => _switchEditorMode(values.first),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child:
                _editorMode == BillRuleEditorMode.form
                    ? Form(
                      key: _formKey,
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          16,
                          16,
                          MediaQuery.of(context).viewInsets.bottom + 24,
                        ),
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('启用规则'),
                            value: _enabled,
                            onChanged:
                                (value) => setState(() => _enabled = value),
                          ),
                          _textField(
                            _nameController,
                            '规则名称',
                            validator:
                                (value) =>
                                    value == null || value.trim().isEmpty
                                        ? '请输入规则名称'
                                        : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _packageController,
                            validator:
                                (value) =>
                                    value == null || value.trim().isEmpty
                                        ? '请输入 packageName'
                                        : null,
                            decoration: InputDecoration(
                              labelText: 'packageName',
                              border: const OutlineInputBorder(),
                              suffixIcon: PopupMenuButton<String>(
                                tooltip: '选择应用',
                                icon: const Icon(Icons.apps),
                                onSelected:
                                    (value) => setState(
                                      () => _packageController.text = value,
                                    ),
                                itemBuilder:
                                    (context) =>
                                        widget.packageLabels.entries
                                            .map(
                                              (entry) => PopupMenuItem(
                                                value: entry.key,
                                                child: Text(
                                                  entry.key ==
                                                          globalBillRulePackage
                                                      ? entry.value
                                                      : '${entry.value}\n${entry.key}',
                                                ),
                                              ),
                                            )
                                            .toList(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _textField(
                            _priorityController,
                            '优先级',
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              TextInputFormatter.withFunction((
                                oldValue,
                                newValue,
                              ) {
                                return RegExp(
                                      r'^-?\d*$',
                                    ).hasMatch(newValue.text)
                                    ? newValue
                                    : oldValue;
                              }),
                            ],
                            validator:
                                (value) =>
                                    int.tryParse(value ?? '') == null
                                        ? '请输入整数'
                                        : null,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            '匹配条件',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 10),
                          _textField(
                            _titleKeywordsController,
                            '标题关键词',
                            maxLines: 2,
                          ),
                          const SizedBox(height: 10),
                          _textField(
                            _contentKeywordsController,
                            '内容关键词',
                            maxLines: 2,
                          ),
                          const SizedBox(height: 10),
                          _textField(
                            _paymentKeywordsController,
                            '支付方式关键词',
                            maxLines: 2,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            '金额',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<BillRuleTextSource>(
                            initialValue: _amountSource,
                            decoration: const InputDecoration(
                              labelText: '取值字段',
                              border: OutlineInputBorder(),
                            ),
                            items:
                                BillRuleTextSource.values
                                    .map(
                                      (source) => DropdownMenuItem(
                                        value: source,
                                        child: Text(_sourceText(source)),
                                      ),
                                    )
                                    .toList(),
                            onChanged:
                                (value) => setState(
                                  () => _amountSource = value ?? _amountSource,
                                ),
                          ),
                          const SizedBox(height: 10),
                          _textField(
                            _patternController,
                            '金额正则（留空则不提取）',
                            maxLines: 2,
                            validator: (value) {
                              if (value == null || value.isEmpty) return null;
                              try {
                                RegExp(value);
                                return null;
                              } on FormatException {
                                return '正则表达式无效';
                              }
                            },
                          ),
                          const SizedBox(height: 10),
                          _textField(
                            _groupController,
                            '捕获组',
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator:
                                (value) =>
                                    int.tryParse(value ?? '') == null
                                        ? '请输入整数'
                                        : null,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            '入账预填',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<BillRuleFlow>(
                            initialValue: _flow,
                            decoration: const InputDecoration(
                              labelText: '类型',
                              border: OutlineInputBorder(),
                            ),
                            items:
                                BillRuleFlow.values
                                    .map(
                                      (flow) => DropdownMenuItem(
                                        value: flow,
                                        child: Text(_flowText(flow)),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() {
                                _flow = value;
                                _categoryName = null;
                              });
                            },
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue:
                                accountOptions.contains(_accountName)
                                    ? _accountName
                                    : null,
                            decoration: const InputDecoration(
                              labelText: '默认账户',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('不预设'),
                              ),
                              ...accountOptions.map(
                                (name) => DropdownMenuItem(
                                  value: name,
                                  child: Text(name),
                                ),
                              ),
                            ],
                            onChanged:
                                (value) => setState(
                                  () =>
                                      _accountName =
                                          value?.isEmpty == true ? null : value,
                                ),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue:
                                categoryOptions.contains(_categoryName)
                                    ? _categoryName
                                    : null,
                            decoration: const InputDecoration(
                              labelText: '默认类目',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('不预设'),
                              ),
                              ...categoryOptions.map(
                                (name) => DropdownMenuItem(
                                  value: name,
                                  child: Text(name),
                                ),
                              ),
                            ],
                            onChanged:
                                _flow == BillRuleFlow.transfer
                                    ? null
                                    : (value) => setState(
                                      () =>
                                          _categoryName =
                                              value?.isEmpty == true
                                                  ? null
                                                  : value,
                                    ),
                          ),
                          const SizedBox(height: 10),
                          _textField(_commentController, '备注模板', maxLines: 2),
                          const SizedBox(height: 12),
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: const Text('规则测试'),
                            children: [
                              _textField(
                                _testTitleController,
                                '测试标题',
                                maxLines: 2,
                              ),
                              const SizedBox(height: 10),
                              _textField(
                                _testContentController,
                                '测试内容',
                                maxLines: 2,
                              ),
                              const SizedBox(height: 10),
                              _textField(
                                _testPaymentController,
                                '测试支付方式',
                                maxLines: 2,
                              ),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('测试'),
                                  onPressed: _runTest,
                                ),
                              ),
                              if (_testResult != null)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      top: 8,
                                      bottom: 12,
                                    ),
                                    child: Text(_testResult!),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    )
                    : _buildJsonEditor(),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_saveError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _saveError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        icon: const Icon(Icons.save),
                        label: const Text('保存'),
                        onPressed: _saveCurrentRule,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
