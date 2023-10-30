package com.croppingimagepicker

import android.util.Log
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.WritableArray
import com.facebook.react.bridge.WritableMap
import com.facebook.react.bridge.WritableNativeArray
import java.util.concurrent.atomic.AtomicInteger

class ResultCollector {
  private var promise: Promise? = null
  private var waitCount = 0
  private var multiple = false
  private var waitCounter = AtomicInteger(0)
  private var arrayResult: WritableArray? = null
  private var resultSent = false

  @Synchronized
  fun setup(promise: Promise, multiple: Boolean) {
    this.promise = promise
    this.multiple = multiple
    this.resultSent = false
    this.waitCount = 0
    this.waitCounter = AtomicInteger(0)
    if (multiple) {
      this.arrayResult = WritableNativeArray()
    }
  }

  @Synchronized
  fun setWaitCount(waitCount: Int) {
    this.waitCount = waitCount
    this.waitCounter = AtomicInteger(0)
  }

  @Synchronized
  private fun isRequestValid(): Boolean {
    if (resultSent) {
      Log.w("cropping-image-picker", "Skipping result, already sent...")
      return false
    }
    if (promise == null) {
      Log.w("cropping-image-picker", "Trying to notify success but promise is not set")
      return false
    }
    return true
  }

  @Synchronized
  fun notifySuccess(result: WritableMap) {
    if (!isRequestValid()) {
      return
    }
    if (multiple) {
      arrayResult?.pushMap(result)
      val currentCount = waitCounter.addAndGet(1)
      if (currentCount == waitCount) {
        promise?.resolve(arrayResult)
        resultSent = true
      }
    } else {
      promise?.resolve(result)
      resultSent = true
    }
  }

  @Synchronized
  fun notifyProblem(code: String, message: String) {
    if (!isRequestValid()) {
      return
    }
    Log.e("cropping-image-picker", "Promise rejected. $message")
    promise?.reject(code, message)
    resultSent = true
  }

  @Synchronized
  fun notifyProblem(code: String, throwable: Throwable) {
    if (!isRequestValid()) {
      return
    }
    Log.e("cropping-image-picker", "Promise rejected. ${throwable.message}")
    promise?.reject(code, throwable)
    resultSent = true
  }
}
