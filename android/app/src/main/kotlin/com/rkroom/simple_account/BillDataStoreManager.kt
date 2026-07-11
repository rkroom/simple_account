package com.rkroom.simple_account

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

private val Context.billDataStore: DataStore<Preferences> by
        preferencesDataStore(name = "BillPreferences")

class BillDataStoreManager private constructor(private val context: Context) {

    private val managerScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val storeMutex = Mutex()

    companion object :
            SingletonHolder<BillDataStoreManager, Context>({
                BillDataStoreManager(it.applicationContext)
            }) {
        private val BILLS_KEY = stringPreferencesKey("bills")
        private const val PENDING_BILL_COUNT_FILE = "pending_bill_count"
    }

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = true
    }

    fun saveBillAsync(billData: BillData) {
        managerScope.launch {
            try {
                addOrUpdateBill(billData)
            } catch (e: Exception) {
                AppLog.e(e) { "BillStore: 异步保存账单失败" }
            }
        }
    }

    /** 获取所有账单 */
    suspend fun getBills(): List<String> = storeMutex.withLock {
        val bills = context.billDataStore.data
                .map { preferences -> getBillsFromPreferences(preferences) }
                .first()

        writePendingBillCount(bills.size)
        bills.map { json.encodeToString(it) }
    }

    suspend fun refreshPendingBillCount(): Int = storeMutex.withLock {
        val count = context.billDataStore.data
                .map { preferences -> getBillsFromPreferences(preferences).size }
                .first()
        writePendingBillCount(count)
        count
    }

    /** 删除指定ID的账单 */
    suspend fun delBill(id: String) = storeMutex.withLock {
        var pendingBillCount = 0
        context.billDataStore.edit { preferences ->
            val currentBills = getBillsFromPreferences(preferences).toMutableList()
            val removed = currentBills.removeAll { it.id == id }
            if (removed) {
                AppLog.i { "BillStore: 已删除记录 ID: $id" }
                saveBillsToPreferences(preferences, currentBills)
            } else {
                AppLog.w { "BillStore: 未找到要删除的记录 ID: $id" }
            }
            pendingBillCount = currentBills.size
        }
        writePendingBillCount(pendingBillCount)
    }

    /** 清空所有账单 */
    suspend fun clearBills() = storeMutex.withLock {
        context.billDataStore.edit { preferences -> preferences.remove(BILLS_KEY) }
        writePendingBillCount(0)
        AppLog.i { "BillStore: 已清空所有账单" }
    }

    // 在 edit 事务中同步获取账单列表
    private fun getBillsFromPreferences(preferences: Preferences): List<BillData> {
        val billsJson = preferences[BILLS_KEY] ?: return emptyList()

        return try {
            // 尝试直接按 List<BillData> 解析
            json.decodeFromString<List<BillData>>(billsJson)
        } catch (e: Exception) {
            try {
                // 兼容迁移：如果是旧格式 List<String> (String 中包含 JSON)
                val oldList = json.decodeFromString<List<String>>(billsJson)
                oldList.mapNotNull { str ->
                    try {
                        json.decodeFromString<BillData>(str)
                    } catch (e: Exception) {
                        null
                    }
                }
            } catch (e2: Exception) {
                AppLog.e(e2) { "BillStore: 解析账单数据失败" }
                emptyList()
            }
        }
    }

    /** 添加或更新账单 */
    suspend fun addOrUpdateBill(billData: BillData) = storeMutex.withLock {
        var pendingBillCount = 0
        context.billDataStore.edit { preferences ->
            val currentBills = getBillsFromPreferences(preferences).toMutableList()

            val index = currentBills.indexOfFirst { it.id == billData.id }

            if (index != -1) {
                val oldBill = currentBills[index]

                val mergedBill =
                        oldBill.copy(
                                content = billData.content ?: oldBill.content,
                                payment = billData.payment ?: oldBill.payment,
                                packageName = billData.packageName,
                                postTime = oldBill.postTime,
                                appName = billData.appName
                        )

                currentBills[index] = mergedBill
                AppLog.i { "BillStore: 根据 ID 合并更新记录: ${billData.id}" }
            } else {
                currentBills.add(billData)
                AppLog.i { "BillStore: 新增记录: ${billData.id}" }
            }
            saveBillsToPreferences(preferences, currentBills)
            pendingBillCount = currentBills.size
        }
        writePendingBillCount(pendingBillCount)
    }

    private suspend fun writePendingBillCount(count: Int) = withContext(Dispatchers.IO) {
        try {
            val target = File(context.filesDir, PENDING_BILL_COUNT_FILE)
            val temporary = File(context.filesDir, "$PENDING_BILL_COUNT_FILE.native.tmp")
            val value = count.coerceAtLeast(0).toString()
            temporary.writeText(value)
            if (!temporary.renameTo(target)) {
                target.writeText(value)
                temporary.delete()
            }
        } catch (e: Exception) {
            AppLog.e(e) { "BillStore: 更新暂存账单数量失败" }
        }
    }

    private fun saveBillsToPreferences(preferences: MutablePreferences, bills: List<BillData>) {
        preferences[BILLS_KEY] = json.encodeToString(bills)
    }
}
