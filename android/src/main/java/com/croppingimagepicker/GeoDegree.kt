package com.croppingimagepicker

import androidx.exifinterface.media.ExifInterface

class GeoDegree(exif: ExifInterface) {
  var latitude: Float? = null
  var longitude: Float? = null

  init {
    val attrLATITUDE = exif.getAttribute(ExifInterface.TAG_GPS_LATITUDE)
    val attrLATITUDE_REF = exif.getAttribute(ExifInterface.TAG_GPS_LATITUDE_REF)
    val attrLONGITUDE = exif.getAttribute(ExifInterface.TAG_GPS_LONGITUDE)
    val attrLONGITUDE_REF = exif.getAttribute(ExifInterface.TAG_GPS_LONGITUDE_REF)

    if (attrLATITUDE != null && attrLATITUDE_REF != null && attrLONGITUDE != null && attrLONGITUDE_REF != null) {
      latitude = if (attrLATITUDE_REF == "N") {
        convertToDegree(attrLATITUDE)
      } else {
        0 - convertToDegree(attrLATITUDE)
      }

      longitude = if (attrLONGITUDE_REF == "E") {
        convertToDegree(attrLONGITUDE)
      } else {
        0 - convertToDegree(attrLONGITUDE)
      }
    }
  }

  private fun convertToDegree(stringDMS: String): Float {
    val DMS = stringDMS.split(",", limit = 3)

    val (D0, D1) = DMS[0].split("/", limit = 2).map { it.toDouble() }
    val FloatD = D0 / D1

    val (M0, M1) = DMS[1].split("/", limit = 2).map { it.toDouble() }
    val FloatM = M0 / M1

    val (S0, S1) = DMS[2].split("/", limit = 2).map { it.toDouble() }
    val FloatS = S0 / S1

    return (FloatD + (FloatM / 60) + (FloatS / 3600)).toFloat()
  }
}
