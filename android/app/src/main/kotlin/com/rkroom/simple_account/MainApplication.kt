package com.rkroom.simple_account

import android.app.Application
import android.util.Log
import io.flutter.BuildConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import timber.log.Timber

class MainApplication : Application() {

    private val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onCreate() {
        super.onCreate()
        initLogging()
    }

    private fun initLogging() {
        val fileLoggingTree = FileLoggingTree(this)

        if (BuildConfig.DEBUG) {
            Timber.plant(Timber.DebugTree())
        }
        Timber.plant(fileLoggingTree)

        applicationScope.launch {
            try {
                val manager = ConfigDataStoreManager.getInstance(this@MainApplication)

                val initLevel = manager.getLogLevel()
                fileLoggingTree.minLogLevel = initLevel
                AppLogConfig.currentLogLevel = initLevel.priority

                // 这里用 Timber/Log 打一条初始化日志（Debug 控制台 + 文件 / Release 仅文件）
                Timber.i("初始化日志级别：${initLevel.name}")

                manager.logLevelFlow.collectLatest { levelEnum ->
                    // A. 更新文件日志过滤级别
                    fileLoggingTree.minLogLevel = levelEnum

                    // B. 更新 inline 判定使用的全局级别
                    AppLogConfig.currentLogLevel = levelEnum.priority

                    // C. 用 AppLog 记录配置变更（会受到级别控制）
                    AppLog.i { "日志配置已更新，当前级别：${levelEnum.name}" }
                }
            } catch (e: Exception) {
                Log.e("App", "监听日志配置失败", e)
            }
        }
        AppLog.i { "文件日志系统初始化完成。" }
    }
}
