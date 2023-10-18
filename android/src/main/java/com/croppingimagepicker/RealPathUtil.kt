package com.croppingimagepicker

import android.content.ContentUris
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import java.io.File
import java.io.FileOutputStream


object RealPathUtil {

  fun getRealPathFromURI(context: Context, uri: Uri): String? {
    if (DocumentsContract.isDocumentUri(context, uri)) {
      when {
        isExternalStorageDocument(uri) -> {
          val docId = DocumentsContract.getDocumentId(uri)
          val split = docId.split(":").toTypedArray()
          val type = split[0]
          if ("primary".equals(type, ignoreCase = true)) {
            return "${Environment.getExternalStorageDirectory()}/${split[1]}"
          } else {
            val tag = docId.substring(0, docId.indexOf(':', 1))
            val path = docId.substring(docId.indexOf(':', 1) + 1)

            getPathToNonPrimaryVolume(context, tag)?.let { nonPrimaryVolume ->
              val result = "$nonPrimaryVolume/$path"
              val file = File(result)
              if (file.exists() && file.canRead()) {
                return result
              }
            }
          }
        }

        isDownloadsDocument(uri) -> {
          val id = DocumentsContract.getDocumentId(uri)
          val contentUri = ContentUris.withAppendedId(
            Uri.parse("content://downloads/public_downloads"), java.lang.Long.valueOf(id)
          )
          return getDataColumn(context, contentUri, null, null)
        }

        isMediaDocument(uri) -> {
          val docId = DocumentsContract.getDocumentId(uri)
          val split = docId.split(":").toTypedArray()
          val type = split[0]
          val contentUri = when (type) {
            "image" -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            "video" -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            "audio" -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            else -> null
          }
          val selection = "_id=?"
          val selectionArgs = arrayOf(split[1])
          return getDataColumn(context, contentUri, selection, selectionArgs)
        }
      }
    } else if ("content".equals(uri.scheme, ignoreCase = true)) {
      return if (isGooglePhotosUri(uri)) uri.lastPathSegment else getDataColumn(
        context,
        uri,
        null,
        null
      )
    } else if ("file".equals(uri.scheme, ignoreCase = true)) {
      return uri.path
    }
    return null
  }

  /**
   * If an image/video has been selected from a cloud storage, this method
   * should be call to download the file in the cache folder.
   *
   * @param context The context
   * @param originalFileName downloaded file's name
   * @param uri file's URI
   * @return file that has been written
   */
  private fun writeToFile(context: Context, originalFileName: String, uri: Uri): File? {
    val fileName = originalFileName.substringAfterLast('/')
    val tmpDir = File(context.cacheDir, "react-native-cropping-image-picker")
    tmpDir.mkdir()
    val file = File(tmpDir, fileName)

    try {
      FileOutputStream(file).use { oos ->
        context.contentResolver.openInputStream(uri)?.use { inputStream ->
          val buf = ByteArray(8192)
          var bytesRead: Int
          while (inputStream.read(buf).also { bytesRead = it } > 0) {
            oos.write(buf, 0, bytesRead)
          }
        }
      }
    } catch (e: Exception) {
      e.printStackTrace()
    }

    return file
  }

  /**
   * Get the value of the data column for this Uri. This is useful for
   * MediaStore Uris, and other file-based ContentProviders.
   *
   * @param context The context.
   * @param uri The Uri to query.
   * @param selection (Optional) Filter used in the query.
   * @param selectionArgs (Optional) Selection arguments used in the query.
   * @return The value of the _data column, which is typically a file path.
   */
  private fun getDataColumn(
    context: Context,
    uri: Uri?,
    selection: String?,
    selectionArgs: Array<String>?
  ): String? {
    val projection = arrayOf(MediaStore.MediaColumns.DATA, MediaStore.MediaColumns.DISPLAY_NAME)

    uri ?: return null

    context.contentResolver.query(uri, projection, selection, selectionArgs, null)?.use { cursor ->
      if (cursor.moveToFirst()) {
        val columnIndex = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
        return if (columnIndex > -1) {
          cursor.getString(columnIndex)
        } else {
          val indexDisplayName = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
          val fileName = cursor.getString(indexDisplayName)
          writeToFile(context, fileName, uri)?.absolutePath
        }
      }
    }
    return null
  }

  /**
   * @param uri The Uri to check.
   * @return Whether the Uri authority is ExternalStorageProvider.
   */
  private fun isExternalStorageDocument(uri: Uri) =
    "com.android.externalstorage.documents" == uri.authority

  /**
   * @param uri The Uri to check.
   * @return Whether the Uri authority is DownloadsProvider.
   */
  private fun isDownloadsDocument(uri: Uri) =
    "com.android.providers.downloads.documents" == uri.authority

  /**
   * @param uri The Uri to check.
   * @return Whether the Uri authority is MediaProvider.
   */
  private fun isMediaDocument(uri: Uri) = "com.android.providers.media.documents" == uri.authority

  /**
   * @param uri The Uri to check.
   * @return Whether the Uri authority is Google Photos.
   */
  private fun isGooglePhotosUri(uri: Uri) =
    "com.google.android.apps.photos.content" == uri.authority

  private fun getPathToNonPrimaryVolume(context: Context, tag: String): String? {
    context.externalCacheDirs?.forEach { volume ->
      volume?.absolutePath?.let { path ->
        if (path.contains(tag)) {
          return path.substring(0, path.indexOf(tag)) + tag
        }
      }
    }
    return null
  }
}
