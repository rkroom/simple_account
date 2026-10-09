package com.rkroom.pending_bill_plugin

fun interface PendingBillCountProvider {
    suspend fun getPendingBillCount(): Int
}
