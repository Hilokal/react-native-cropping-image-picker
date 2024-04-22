package com.croppingimagepicker

import androidx.exifinterface.media.ExifInterface
import androidx.exifinterface.media.ExifInterface.*
import com.facebook.react.bridge.WritableMap
import com.facebook.react.bridge.WritableNativeMap
import java.io.IOException

object ExifExtractor {

  @Throws(IOException::class)
  fun extract(path: String, mime: String): WritableMap {
    val exifData = WritableNativeMap()

    val attributes = getBasicAttributes(mime)

    val exif = ExifInterface(path)

    try {
      val geoDegree = GeoDegree(exif)
      geoDegree.latitude?.let { latitude ->
        geoDegree.longitude?.let { longitude ->
          exifData.putDouble("Latitude", latitude.toDouble())
          exifData.putDouble("Longitude", longitude.toDouble())
        }
      }
    } catch (e: Exception) {
      e.printStackTrace()
    }

    for (attribute in attributes) {
      val value = exif.getAttribute(attribute)
      exifData.putString(attribute, value)
    }

    return exifData
  }

  private fun getBasicAttributes(mime: String): List<String> {
    val standardTags = mutableListOf(
      TAG_DATETIME,
      TAG_EXPOSURE_TIME,
      TAG_F_NUMBER,
      TAG_FLASH,
      TAG_FOCAL_LENGTH,
      TAG_GPS_ALTITUDE,
      TAG_GPS_ALTITUDE_REF,
      TAG_GPS_DATESTAMP,
      TAG_GPS_LATITUDE,
      TAG_GPS_LATITUDE_REF,
      TAG_GPS_LONGITUDE,
      TAG_GPS_LONGITUDE_REF,
      TAG_GPS_PROCESSING_METHOD,
      TAG_GPS_TIMESTAMP,
      TAG_MAKE,
      TAG_MODEL,
      TAG_ORIENTATION,
      TAG_PHOTOGRAPHIC_SENSITIVITY,
      TAG_WHITE_BALANCE,
      TAG_DATETIME_DIGITIZED,
      TAG_SUBSEC_TIME,
      TAG_SUBSEC_TIME_DIGITIZED,
      TAG_SUBSEC_TIME_ORIGINAL
    )
    if (mime != "image/jpeg") {
      // In JPEG compressed data, this tag shall not be used because a JPEG marker is used instead of it.
      standardTags.addAll(listOf(TAG_IMAGE_LENGTH, TAG_IMAGE_WIDTH))
    }
    return standardTags
  }

  @Throws(IOException::class)
  fun extractOrientation(path: String): Boolean {
    val exif = ExifInterface(path)
    val value = exif.getAttributeInt(TAG_ORIENTATION, 1)
    //ORIENTATION_ROTATE_90 = 6
    //Indicates the image is rotated by 90 degree clockwise.
    //ORIENTATION_ROTATE_270 = 8
    //Indicates the image is rotated by 270 degree clockwise.
    return value == 6 || value == 8
  }
}
