package com.croppingimagepicker

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Environment
import androidx.exifinterface.media.ExifInterface
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReadableMap
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.OutputStream
import java.util.UUID

class Compression {

  @Throws(IOException::class)
  fun resize(
    context: Context,
    originalImagePath: String,
    originalWidth: Int,
    originalHeight: Int,
    maxWidth: Int,
    maxHeight: Int,
    quality: Int
  ): File {
    val (targetWidth, targetHeight) = calculateTargetDimensions(
      originalWidth, originalHeight, maxWidth, maxHeight
    )

    val options = BitmapFactory.Options().apply {
      inSampleSize = calculateInSampleSize(originalWidth, originalHeight, targetWidth, targetHeight)
    }

    val bitmap = BitmapFactory.decodeFile(originalImagePath, options)

    // Use original image exif orientation data to preserve image orientation
    val originalExif = ExifInterface(originalImagePath)
    val originalOrientation = originalExif.getAttribute(ExifInterface.TAG_ORIENTATION)

    val resizedBitmap = Bitmap.createScaledBitmap(bitmap, targetWidth, targetHeight, true)
    val imageDirectory = context.getExternalFilesDir(Environment.DIRECTORY_PICTURES)

    imageDirectory?.mkdirs()

    val resizeImageFile = File(imageDirectory, UUID.randomUUID().toString() + ".jpg")

    BufferedOutputStream(FileOutputStream(resizeImageFile)).use { os ->
      resizedBitmap.compress(Bitmap.CompressFormat.JPEG, quality, os)

      // Don't set unnecessary exif attribute
      if (shouldSetOrientation(originalOrientation)) {
        val exif = ExifInterface(resizeImageFile.absolutePath)
        exif.setAttribute(ExifInterface.TAG_ORIENTATION, originalOrientation)
        exif.saveAttributes()
      }
    }

    resizedBitmap.recycle()

    return resizeImageFile
  }

  private fun calculateInSampleSize(
    originalWidth: Int, originalHeight: Int,
    requestedWidth: Int, requestedHeight: Int
  ): Int {
    var inSampleSize = 1

    if (originalWidth > requestedWidth || originalHeight > requestedHeight) {
      val halfWidth = originalWidth / 2
      val halfHeight = originalHeight / 2

      while (halfWidth / inSampleSize >= requestedWidth && halfHeight / inSampleSize >= requestedHeight) {
        inSampleSize *= 2
      }
    }

    return inSampleSize
  }

  private fun shouldSetOrientation(orientation: String?): Boolean {
    return orientation != null && orientation != ExifInterface.ORIENTATION_NORMAL.toString() &&
      orientation != ExifInterface.ORIENTATION_UNDEFINED.toString()
  }

  @Throws(IOException::class)
  fun compressImage(
    context: Context, options: ReadableMap,
    originalImagePath: String, bitmapOptions: BitmapFactory.Options
  ): File {
    val maxWidth =
      options.takeIf { it.hasKey("compressImageMaxWidth") }?.getInt("compressImageMaxWidth") ?: 1000
    val maxHeight =
      options.takeIf { it.hasKey("compressImageMaxHeight") }?.getInt("compressImageMaxHeight")
        ?: 1000
    val quality =
      (options.takeIf { it.hasKey("compressImageQuality") }?.getDouble("compressImageQuality")
        ?: 1.0) * 100

    return resize(
      context,
      originalImagePath,
      bitmapOptions.outWidth,
      bitmapOptions.outHeight,
      maxWidth,
      maxHeight,
      quality.toInt()
    )
  }

  private fun calculateTargetDimensions(
    currentWidth: Int, currentHeight: Int,
    maxWidth: Int, maxHeight: Int
  ): Pair<Int, Int> {
    var width = currentWidth
    var height = currentHeight

    if (width > maxWidth) {
      val ratio = maxWidth.toFloat() / width
      height = (height * ratio).toInt()
      width = maxWidth
    }

    if (height > maxHeight) {
      val ratio = maxHeight.toFloat() / height
      width = (width * ratio).toInt()
      height = maxHeight
    }

    return Pair(width, height)
  }

  @Synchronized
  fun compressVideo(
    activity: Activity?, options: ReadableMap?,
    originalVideo: String?, compressedVideo: String?, promise: Promise
  ) {
    // TODO: video compression
    promise.resolve(originalVideo)
  }
}
