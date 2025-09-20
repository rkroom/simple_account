package com.rkroom.simple_account

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

private val Context.billDataStore: DataStore<Preferences> by preferencesDataStore(name = "BillPreferences")

class BillDataStoreManager private constructor(private val context: Context) {

    companion object {
        private val BILLS_KEY = stringPreferencesKey("bills")

        @Volatile
        private var instance: BillDataStoreManager? = null

        fun getInstance(context: Context): BillDataStoreManager =
            instance ?: synchronized(this) {
                instance ?: BillDataStoreManager(context.applicationContext).also { instance = it }
            }
    }

    /** 获取所有账单 */
    suspend fun getBills(): List<String> {
        val billsJson = context.billDataStore.data.map { preferences ->
            preferences[BILLS_KEY]
        }.first()
        return if (billsJson != null) {
            Json.decodeFromString(billsJson)
        } else {
            emptyList()
        }
    }

    /** 添加账单 */
    suspend fun addBill(bill: String) {
        context.billDataStore.edit { preferences ->
            val currentBills = getBillsFromPreferences(preferences).toMutableList()
            currentBills.add(bill)
            preferences[BILLS_KEY] = Json.encodeToString(currentBills)
        }
    }

    /** 删除指定索引的账单 */
    suspend fun delBill(index: Int) {
        context.billDataStore.edit { preferences ->
            val currentBills = getBillsFromPreferences(preferences).toMutableList()
            if (index >= 0 && index < currentBills.size) {
                currentBills.removeAt(index)
                preferences[BILLS_KEY] = Json.encodeToString(currentBills)
            }
        }
    }

    /** 清空所有账单 */
    suspend fun clearBills() {
        context.billDataStore.edit { preferences ->
            preferences.remove(BILLS_KEY)
        }
    }
    
    // 在 edit 事务中同步获取账单列表
    private fun getBillsFromPreferences(preferences: Preferences): List<String> {
        val billsJson = preferences[BILLS_KEY]
        return if (billsJson != null) {
            Json.decodeFromString(billsJson)
        } else {
            emptyList()
        }
    }
}