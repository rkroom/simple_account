package com.rkroom.simple_account

import timber.log.Timber

object AppLog {
    // --- Verbose ---
    inline fun v(t: Throwable? = null, crossinline message: () -> String) {
        if (AppLogConfig.isLoggable(AppLogLevel.VERBOSE.priority)) {
            log(AppLogLevel.VERBOSE.priority, t, message())
        }
    }

    // --- Debug ---
    inline fun d(t: Throwable? = null, crossinline message: () -> String) {
        if (AppLogConfig.isLoggable(AppLogLevel.DEBUG.priority)) {
            log(AppLogLevel.DEBUG.priority, t, message())
        }
    }

    // --- Info ---
    inline fun i(t: Throwable? = null, crossinline message: () -> String) {
        if (AppLogConfig.isLoggable(AppLogLevel.INFO.priority)) {
            log(AppLogLevel.INFO.priority, t, message())
        }
    }

    // --- Warn ---
    inline fun w(t: Throwable? = null, crossinline message: () -> String) {
        if (AppLogConfig.isLoggable(AppLogLevel.WARN.priority)) {
            log(AppLogLevel.WARN.priority, t, message())
        }
    }

    // --- Error ---
    inline fun e(t: Throwable? = null, crossinline message: () -> String) {
        if (AppLogConfig.isLoggable(AppLogLevel.ERROR.priority)) {
            log(AppLogLevel.ERROR.priority, t, message())
        }
    }

    /** 内部转发，非 inline 以减少字节码膨胀 */
    fun log(priority: Int, t: Throwable?, message: String) {
        if (t != null) {
            Timber.log(priority, t, message)
        } else {
            Timber.log(priority, message)
        }
    }
}
