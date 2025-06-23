import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_picker_plus/flutter_picker_plus.dart';

import '../tools/db.dart';
import '../tools/event_bus.dart';
import '../tools/tools.dart';

class ManageWidget extends StatefulWidget {
  const ManageWidget({super.key});

  @override
  State<StatefulWidget> createState() {
    return ManageWidgetState();
  }
}

class ManageWidgetState extends State<ManageWidget> {
  final TextEditingController _firstCategoryController =
      TextEditingController();
  final TextEditingController _specificgoryController = TextEditingController();
  final TextEditingController _newAccountNameController =
      TextEditingController();
  final TextEditingController _newAccountAmountController =
      TextEditingController(text: "0");

  List categoryTypeFlow = ["支出", "收入"];
  List<String> accountType = ["资产", "负债"];
  Map<String, String> categoryTypeFlowMap = {"支出": "consume", "收入": "income"};
  Map<String, String> accountTypeMap = {"资产": "asset", "负债": "debt"};
  List firstCategoryName = [];

  String showCategoryTypeFlow = "请选择";
  String selectedCategoryTypeFlow = '';
  String showFirstCategory = "请选择";
  String selectedFirstCategory = '';
  Map firstCategoryNameAndID = {};
  String showSelectedAccountType = "请选择";
  String selectedAccountType = '';

  void getFirstCategories() {
    DB().getFirstCategories().then((value) {
      for (var i in value) {
        if (i["flow_sign"] == "consume") {
          firstCategoryNameAndID[i["first_level"] + "（支出）"] =
              i["id"].toString();
          firstCategoryName.add(i["first_level"] + "（支出）");
        } else {
          firstCategoryNameAndID[i["first_level"] + "（收入）"] =
              i["id"].toString();
          firstCategoryName.add(i["first_level"] + "（收入）");
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    getFirstCategories();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("管理")),
      body: GestureDetector(
        onTap: () {
          FocusManager.instance.primaryFocus?.unfocus();
        },
        child: SingleChildScrollView(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Text("一级分类："),
                  SizedBox(
                    width: 100,
                    child: TextField(
                      // 通过controller可以调用用户输入的数据
                      controller: _firstCategoryController,
                    ),
                  ),
                ],
              ),
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 10),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    // 账户类别
                    Picker(
                      confirmText: "确认",
                      cancelText: "取消",
                      adapter: PickerDataAdapter<String>(
                        pickerData: categoryTypeFlow,
                      ),
                      changeToFirst: true,
                      hideHeader: false,
                      onConfirm: (Picker picker, List value) {
                        setState(() {
                          // 显示于界面
                          showCategoryTypeFlow = picker.adapter.text;
                          // 设置一级账户的类型
                          selectedCategoryTypeFlow =
                              categoryTypeFlowMap[picker
                                  .getSelectedValues()[0]]!;
                        });
                      },
                    ).showModal(context);
                  },
                  child: Text("分类类型：$showCategoryTypeFlow"),
                ),
              ),
              ElevatedButton(
                child: const Text("添加"),
                onPressed: () async {
                  if (_firstCategoryController.text.isEmpty) {
                    showNoticeSnackBar(context, "分类名不能为空");
                    return;
                  } else {
                    if (selectedCategoryTypeFlow.isEmpty) {
                      showNoticeSnackBar(context, "必须选择分类类型");
                      return;
                    }
                    try {
                      DB().addFirstCategory(
                        _firstCategoryController.text,
                        selectedCategoryTypeFlow,
                      );
                      _firstCategoryController.clear();
                      setState(() {
                        getFirstCategories();
                      });
                    } catch (error) {
                      //print(error)
                      showNoticeSnackBar(context, "添加失败");
                    }
                  }
                },
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Text("二级分类："),
                  SizedBox(
                    width: 100,
                    child: TextField(
                      // 通过controller可以调用用户输入的数据
                      controller: _specificgoryController,
                    ),
                  ),
                ],
              ),
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 10),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    // 账户类别
                    Picker(
                      confirmText: "确认",
                      cancelText: "取消",
                      adapter: PickerDataAdapter<String>(
                        pickerData: firstCategoryName,
                      ),
                      changeToFirst: true,
                      hideHeader: false,
                      onConfirm: (Picker picker, List value) {
                        setState(() {
                          // 显示于界面
                          showFirstCategory = picker.adapter.text;
                          // 设置一级账户的ID
                          selectedFirstCategory =
                              firstCategoryNameAndID[picker
                                  .getSelectedValues()[0]]!;
                        });
                      },
                    ).showModal(context);
                  },
                  child: Text("一级分类：$showFirstCategory"),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    //按钮
                    child: const Text("添加"),
                    // 点击按钮事件
                    onPressed: () async {
                      if (_specificgoryController.text.isEmpty) {
                        showNoticeSnackBar(context, "分类名不能为空");
                        return;
                      } else {
                        if (selectedFirstCategory.isEmpty) {
                          showNoticeSnackBar(context, "必须选择一级分类");
                          return;
                        }
                        try {
                          DB().addSpecificCategory(
                            selectedFirstCategory,
                            _specificgoryController.text,
                          );
                          _specificgoryController.clear();

                          bus.emit("update_category");
                        } catch (error) {
                          //print(error)
                          showNoticeSnackBar(context, "添加失败");
                        }
                      }
                    },
                  ),
                ],
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Text("账户名称："),
                  SizedBox(
                    width: 100,
                    child: TextField(
                      // 通过controller可以调用用户输入的数据
                      controller: _newAccountNameController,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Text("初始金额："),
                  SizedBox(
                    width: 100,
                    child: TextField(
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp("[0-9.]")),
                      ],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      // 通过controller可以调用用户输入的数据
                      controller: _newAccountAmountController,
                    ),
                  ),
                ],
              ),
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        // 账户类别
                        Picker(
                          confirmText: "确认",
                          cancelText: "取消",
                          adapter: PickerDataAdapter<String>(
                            pickerData: accountType,
                          ),
                          changeToFirst: true,
                          hideHeader: false,
                          onConfirm: (Picker picker, List value) {
                            setState(() {
                              // 显示于界面
                              showSelectedAccountType = picker.adapter.text;
                              // 设置账户类型
                              selectedAccountType =
                                  accountTypeMap[picker
                                      .getSelectedValues()[0]]!;
                            });
                          },
                        ).showModal(context);
                      },
                      child: Text("账户类型：$showSelectedAccountType"),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                child: const Text("添加"),
                onPressed: () async {
                  if (_newAccountNameController.text.isEmpty) {
                    showNoticeSnackBar(context, "账户名不能为空");
                    return;
                  } else {
                    if (selectedAccountType.isEmpty) {
                      showNoticeSnackBar(context, "必须选择账户类型");
                      return;
                    }
                    try {
                      DB().addAccount(
                        _newAccountNameController.text,
                        _newAccountAmountController.text,
                        selectedAccountType,
                      );
                      _newAccountNameController.clear();
                      _newAccountAmountController.text = '0';
                      bus.emit("update_account");
                    } catch (error) {
                      showNoticeSnackBar(context, "添加失败");
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
