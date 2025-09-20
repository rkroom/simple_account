package com.rkroom.simple_account

import android.app.Application
import io.flutter.BuildConfig
import timber.log.Timber

class MainApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        if (BuildConfig.DEBUG) {
            Timber.plant(Timber.DebugTree(), FileLoggingTree(this))
            Timber.i("Timber 文件日志系统已初始化。")
        }
    }
}
