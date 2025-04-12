package com.rkroom.simple_account

import android.content.SharedPreferences
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import android.content.Context

class SharedPreferencesManager private constructor(context: Context) {

    companion object {
        private const val PREFERENCES_NAME = "BillPreferences"
        private const val BILLS_KEY = "bills"
        
        @Volatile
        private var instance: SharedPreferencesManager? = null

        fun getInstance(context: Context): SharedPreferencesManager =
            instance ?: synchronized(this) {
                instance ?: SharedPreferencesManager(context).also { instance = it }
            }
    }

    private val sharedPreferences: SharedPreferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
    // 添加账单，返回添加的索引 (相当于Hive的add操作)
    fun addBill(bill: String): Int {
        val bills = getBills().toMutableList() // 获取当前所有账单
        bills.add(bill) // 添加新账单
        saveBills(bills) // 保存到SharedPreferences
        return bills.size - 1 // 返回新账单的索引
    }

    // 删除指定索引的账单 (相当于Hive的deleteAt操作)
    fun delBill(index: Int) {
        val bills = getBills().toMutableList()
        if (index >= 0 && index < bills.size) {
            bills.removeAt(index) // 删除指定索引的账单
            saveBills(bills) // 保存修改后的账单列表
        }
    }

    // 获取所有账单 (相当于Hive的values操作)
    fun getBills(): List<String> {
        val billsJson = sharedPreferences.getString(BILLS_KEY, null)
        return if (billsJson != null) {
            // 反序列化JSON字符串为List
            Json.decodeFromString(billsJson)
        } else {
            emptyList() // 如果没有账单，则返回空列表
        }
    }

    // 清空所有账单 (相当于Hive的clear操作)
    fun clearBills(): Int {
        val editor = sharedPreferences.edit()
        val count = getBills().size // 获取当前账单的数量，用于返回
        editor.remove(BILLS_KEY) // 清空存储的账单
        editor.apply() // 提交更改
        return count // 返回清空的数量
    }

    // 私有方法，用于保存账单列表
    private fun saveBills(bills: List<String>) {
        // 将List序列化为JSON字符串
        val billsJson = Json.encodeToString(bills)
        sharedPreferences.edit().putString(BILLS_KEY, billsJson).apply()
    }
}