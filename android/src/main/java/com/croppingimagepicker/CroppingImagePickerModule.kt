package com.croppingimagepicker

import android.Manifest
import android.app.Activity
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Base64
import android.util.Log
import android.webkit.MimeTypeMap
import androidx.core.app.ActivityCompat
import androidx.core.content.FileProvider
import androidx.core.net.toUri
import com.facebook.react.bridge.ActivityEventListener
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.PromiseImpl
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.WritableMap
import com.facebook.react.bridge.WritableNativeMap
import com.facebook.react.modules.core.PermissionAwareActivity
import com.facebook.react.modules.core.PermissionListener
import com.yalantis.ucrop.UCrop
import com.yalantis.ucrop.UCropActivity
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.UUID

class CroppingImagePickerModule(private val reactContext: ReactApplicationContext) :
  ReactContextBaseJavaModule(reactContext), ActivityEventListener {

  private var mediaType: String = "any"
  private var multiple = false
  private var includeBase64 = false
  private var includeExif = false
  private var cropping = false
  private var cropperCircleOverlay = false
  private var freeStyleCropEnabled = false
  private var showCropGuidelines = true
  private var showCropFrame = true
  private var hideBottomControls = false
  private var enableRotationGesture = false
  private var disableCropperColorSetters = false
  private var useFrontCamera = false
  private var forceJpg = false
  private var options: ReadableMap? = null
  private var cropperActiveWidgetColor: String? = null
  private var cropperStatusBarColor: String? = null
  private var cropperToolbarColor: String? = null
  private var cropperToolbarTitle: String? = null
  private var cropperToolbarWidgetColor: String? = null
  private var width = 0
  private var height = 0
  private var mCameraCaptureURI: Uri? = null
  private var mCurrentMediaPath: String? = null
  private val resultCollector = ResultCollector()
  private val compression = Compression()

  init {
    reactContext.addActivityEventListener(this)
  }

  override fun getName(): String {
    return NAME
  }

  private fun getTmpDir(activity: Activity): String {
    return (activity.cacheDir.toString() + "/react-native-cropping-image-picker").also { File(it).mkdir() }
  }

  private fun setConfiguration(options: ReadableMap) {
    mediaType = getStringOption(options, "mediaType", "any") ?: "any"
    multiple = getBooleanOption(options, "multiple")
    includeBase64 = getBooleanOption(options, "includeBase64")
    includeExif = getBooleanOption(options, "includeExif")
    width = getIntOption(options, "width")
    height = getIntOption(options, "height")
    cropping = getBooleanOption(options, "cropping")
    cropperActiveWidgetColor = getStringOption(options, "cropperActiveWidgetColor", null)
    cropperStatusBarColor = getStringOption(options, "cropperStatusBarColor", null)
    cropperToolbarColor = getStringOption(options, "cropperToolbarColor", null)
    cropperToolbarTitle = getStringOption(options, "cropperToolbarTitle", null)
    cropperToolbarWidgetColor = getStringOption(options, "cropperToolbarWidgetColor", null)
    cropperCircleOverlay = getBooleanOption(options, "cropperCircleOverlay")
    freeStyleCropEnabled = getBooleanOption(options, "freeStyleCropEnabled")
    showCropGuidelines = getBooleanOptionWithDefaultTrue(options, "showCropGuidelines")
    showCropFrame = getBooleanOptionWithDefaultTrue(options, "showCropFrame")
    hideBottomControls = getBooleanOption(options, "hideBottomControls")
    enableRotationGesture = getBooleanOption(options, "enableRotationGesture")
    disableCropperColorSetters = getBooleanOption(options, "disableCropperColorSetters")
    useFrontCamera = getBooleanOption(options, "useFrontCamera")
    forceJpg = getBooleanOption(options, "forceJpg")
    this.options = options
  }

  private fun getStringOption(options: ReadableMap, key: String, defaultValue: String?): String? {
    return if (options.hasKey(key)) options.getString(key) else defaultValue
  }

  private fun getIntOption(options: ReadableMap, key: String): Int {
    return if (options.hasKey(key)) options.getInt(key) else 0
  }

  private fun getBooleanOption(options: ReadableMap, key: String): Boolean {
    return options.hasKey(key) && options.getBoolean(key)
  }

  private fun getBooleanOptionWithDefaultTrue(options: ReadableMap, key: String): Boolean {
    return !options.hasKey(key) || options.getBoolean(key)
  }

  private fun File.deleteRecursive() {
    this.takeIf { it.isDirectory }?.listFiles()?.forEach { it.deleteRecursive() }
    this.delete()
  }

  @ReactMethod
  fun clean(promise: Promise) {
    val activity = currentActivity ?: run {
      promise.reject(E_ACTIVITY_DOES_NOT_EXIST_KEY, E_ACTIVITY_DOES_NOT_EXIST_MSG)
      return
    }

    permissionsCheck(activity, promise, listOf(Manifest.permission.WRITE_EXTERNAL_STORAGE)) {
      File(getTmpDir(activity)).takeIf { it.exists() }?.let {
        it.deleteRecursive()
        promise.resolve(null)
      } ?: run {
        promise.reject(E_ERROR_WHILE_CLEANING_FILES, "File does not exist")
      }
    }
  }

  @ReactMethod
  fun cleanSingle(pathToDelete: String?, promise: Promise) {
    if (pathToDelete == null) {
      promise.reject(E_ERROR_WHILE_CLEANING_FILES, "Cannot cleanup empty path")
      return
    }

    val activity = currentActivity

    if (activity == null) {
      promise.reject(E_ACTIVITY_DOES_NOT_EXIST_KEY, E_ACTIVITY_DOES_NOT_EXIST_MSG)
      return
    }

    permissionsCheck(activity, promise, listOf(Manifest.permission.WRITE_EXTERNAL_STORAGE)) {
      try {
        var path = pathToDelete
        val filePrefix = "file://"
        if (path.startsWith(filePrefix)) {
          path = path.substring(filePrefix.length)
        }

        val file = File(path)
        if (!file.exists()) throw Exception("File does not exist. Path: $path")

        file.deleteRecursive()
        promise.resolve(null)
      } catch (ex: Exception) {
        ex.printStackTrace()
        promise.reject(E_ERROR_WHILE_CLEANING_FILES, ex.message)
      }
    }
  }

  private fun permissionsCheck(
    activity: Activity,
    promise: Promise,
    requiredPermissions: List<String>,
    callback: () -> Unit
  ) {
    val missingPermissions = mutableListOf<String>()
    val supportedPermissions = requiredPermissions.toMutableList()

    if (Build.VERSION.SDK_INT > Build.VERSION_CODES.Q) {
      supportedPermissions.remove(Manifest.permission.WRITE_EXTERNAL_STORAGE)
    }

    for (permission in supportedPermissions) {
      val status = ActivityCompat.checkSelfPermission(activity, permission)
      if (status != PackageManager.PERMISSION_GRANTED) {
        missingPermissions.add(permission)
      }
    }

    if (missingPermissions.isNotEmpty()) {
      (activity as PermissionAwareActivity).requestPermissions(
        missingPermissions.toTypedArray(),
        1,
        object : PermissionListener {
          override fun onRequestPermissionsResult(
            requestCode: Int,
            permissions: Array<String>,
            grantResults: IntArray
          ): Boolean {
            if (requestCode == 1) {
              for (permissionIndex in permissions.indices) {
                val permission = permissions[permissionIndex]
                val grantResult = grantResults[permissionIndex]

                if (grantResult == PackageManager.PERMISSION_DENIED) {
                  when (permission) {
                    Manifest.permission.CAMERA -> promise.reject(
                      E_NO_CAMERA_PERMISSION_KEY,
                      E_NO_CAMERA_PERMISSION_MSG
                    )

                    Manifest.permission.WRITE_EXTERNAL_STORAGE -> promise.reject(
                      E_NO_LIBRARY_PERMISSION_KEY,
                      E_NO_LIBRARY_PERMISSION_MSG
                    )

                    else -> promise.reject(
                      E_NO_LIBRARY_PERMISSION_KEY,
                      "Required permission missing"
                    )
                  }
                  return true
                }
              }
              try {
                callback()
              } catch (e: Exception) {
                promise.reject(E_CALLBACK_ERROR, "Unknown error", e)
              }
            }
            return true
          }
        })
      return
    }

    try {
      callback()
    } catch (e: Exception) {
      promise.reject(E_CALLBACK_ERROR, "Unknown error", e)
    }
  }

  @ReactMethod
  fun openCamera(options: ReadableMap, promise: Promise) {
    val activity = currentActivity

    if (activity == null) {
      promise.reject(E_ACTIVITY_DOES_NOT_EXIST_KEY, E_ACTIVITY_DOES_NOT_EXIST_MSG)
      return
    }

    if (!isCameraAvailable(activity)) {
      promise.reject(E_CAMERA_IS_NOT_AVAILABLE, "Camera not available")
      return
    }

    setConfiguration(options)
    resultCollector.setup(promise, false)

    permissionsCheck(
      activity,
      promise,
      listOf(Manifest.permission.CAMERA, Manifest.permission.WRITE_EXTERNAL_STORAGE)
    ) {
      initiateCamera(activity)
    }
  }

  private fun initiateCamera(activity: Activity) {
    try {
      val (intent, dataFile) = when (mediaType) {
        "video" -> Pair(MediaStore.ACTION_VIDEO_CAPTURE, createVideoFile())
        else -> Pair(MediaStore.ACTION_IMAGE_CAPTURE, createImageFile())
      }

      val cameraIntent = Intent(intent)
      mCameraCaptureURI = FileProvider.getUriForFile(
        activity,
        "${activity.applicationContext.packageName}.provider",
        dataFile
      )

      cameraIntent.putExtra(MediaStore.EXTRA_OUTPUT, mCameraCaptureURI)
      if (useFrontCamera) {
        cameraIntent.putExtra("android.intent.extras.CAMERA_FACING", 1)
        cameraIntent.putExtra("android.intent.extras.LENS_FACING_FRONT", 1)
        cameraIntent.putExtra("android.intent.extra.USE_FRONT_CAMERA", true)
      }

      if (cameraIntent.resolveActivity(activity.packageManager) == null) {
        resultCollector.notifyProblem(E_CANNOT_LAUNCH_CAMERA, "Cannot launch camera")
        return
      }

      activity.startActivityForResult(cameraIntent, CAMERA_PICKER_REQUEST)
    } catch (e: Exception) {
      resultCollector.notifyProblem(E_FAILED_TO_OPEN_CAMERA, e)
    }
  }

  private fun initiatePicker(activity: Activity) {
    try {
      val galleryIntent = Intent(Intent.ACTION_GET_CONTENT)

      when {
        cropping || mediaType == "photo" -> {
          galleryIntent.type = "image/*"
          if (cropping) {
            galleryIntent.putExtra(
              Intent.EXTRA_MIME_TYPES,
              arrayOf("image/jpeg", "image/png")
            )
          }
        }

        mediaType == "video" -> galleryIntent.type = "video/*"
        else -> {
          galleryIntent.type = "*/*"
          galleryIntent.putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "video/*"))
        }
      }

      galleryIntent.flags = Intent.FLAG_ACTIVITY_CLEAR_TOP
      galleryIntent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, multiple)
      galleryIntent.addCategory(Intent.CATEGORY_OPENABLE)

      val chooserIntent = Intent.createChooser(galleryIntent, "Pick an image")
      activity.startActivityForResult(chooserIntent, IMAGE_PICKER_REQUEST)
    } catch (e: Exception) {
      resultCollector.notifyProblem(E_FAILED_TO_SHOW_PICKER, e)
    }
  }

  @ReactMethod
  fun openPicker(options: ReadableMap, promise: Promise) {
    val activity = currentActivity

    activity?.let {
      setConfiguration(options)
      resultCollector.setup(promise, multiple)

      val permissions = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
        listOf(Manifest.permission.WRITE_EXTERNAL_STORAGE)
      } else {
        listOf(Manifest.permission.READ_MEDIA_IMAGES)
      }
      permissionsCheck(activity, promise, permissions) {
        initiatePicker(activity)
      }
    } ?: promise.reject(E_ACTIVITY_DOES_NOT_EXIST_KEY, E_ACTIVITY_DOES_NOT_EXIST_MSG)
  }

  @ReactMethod
  fun openCropper(options: ReadableMap, promise: Promise) {
    val activity = currentActivity

    activity?.let {
      setConfiguration(options)
      resultCollector.setup(promise, false)

      val uri = Uri.parse(options.getString("path"))
      // TODO: Cropping won't work if file is GIF, so maybe save as JPEG before cropping?
      permissionsCheck(activity, promise, listOf(Manifest.permission.WRITE_EXTERNAL_STORAGE)) {
        startCropping(activity, uri)
      }
    } ?: promise.reject(E_ACTIVITY_DOES_NOT_EXIST_KEY, E_ACTIVITY_DOES_NOT_EXIST_MSG)
  }

  private fun getBase64StringFromFile(absoluteFilePath: String): String? {
    val file = File(absoluteFilePath)
    val bytes = file.readBytes()
    return Base64.encodeToString(bytes, Base64.NO_WRAP)
  }

  private fun getMimeType(url: String): String? {
    val uri = Uri.fromFile(File(url))
    return if (uri.scheme == ContentResolver.SCHEME_CONTENT) {
      reactContext.contentResolver.getType(uri)
    } else {
      MimeTypeMap.getFileExtensionFromUrl(uri.toString())?.let {
        MimeTypeMap.getSingleton().getMimeTypeFromExtension(it.lowercase())
      }
    }
  }

  private fun getSelection(activity: Activity, uri: Uri, isCamera: Boolean): WritableMap? {
    return resolveRealPath(activity, uri, isCamera)?.let { path ->
      getMimeType(path)?.let { mime ->
        if (mime.startsWith("video/")) {
          getVideo(activity, path, mime)
          null
        } else {
          getImage(path, mime)
        }
      }
    }
  }

  private fun getAsyncSelection(activity: Activity, uri: Uri, isCamera: Boolean = false) {
    resolveRealPath(activity, uri, isCamera)?.let { path ->
      getMimeType(path)?.let { mime ->
        if (mime.startsWith("video/")) {
          getVideo(activity, path, mime)
        } else {
          val image = getImage(path, mime)
          if (image != null) {
            resultCollector.notifySuccess(image)
          } else {
            resultCollector.notifyProblem(
              "ERROR_GETTING_ASYNC_SELECTION",
              "IMAGE is null"
            ) //TODO: see what makes sense here
          }
        }
      }
    }
  }

  private fun validateVideo(path: String): Bitmap {
    val retriever = MediaMetadataRetriever()
    retriever.setDataSource(path)
    return retriever.frameAtTime ?: throw Exception("Cannot retrieve video data")
  }

  private fun getVideoDuration(path: String): Long {
    return try {
      val retriever = MediaMetadataRetriever()
      retriever.setDataSource(path)
      retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLong() ?: -1L
    } catch (e: Exception) {
      -1L
    }
  }

  private fun getVideo(activity: Activity, path: String, mime: String) {
    validateVideo(path)
    val compressedVideoPath = "${getTmpDir(activity)}/${UUID.randomUUID()}.mp4"

    Thread {
      compression.compressVideo(
        activity, options, path, compressedVideoPath,
        PromiseImpl({ args ->
          val videoPath = args[0] as? String ?: return@PromiseImpl

          try {
            val bmp = validateVideo(videoPath)
            val modificationDate = File(videoPath).lastModified()
            val duration = getVideoDuration(videoPath)

            val video = WritableNativeMap().apply {
              putInt("width", bmp.width)
              putInt("height", bmp.height)
              putString("mime", mime)
              putInt("size", File(videoPath).length().coerceIn(0, Int.MAX_VALUE.toLong()).toInt())
              putInt("duration", duration.coerceIn(0, Int.MAX_VALUE.toLong()).toInt())
              putString("path", "file://$videoPath")
              putString("fileName", File(videoPath).name)
              putString("modificationDate", modificationDate.toString())
            }

            resultCollector.notifySuccess(video)
          } catch (exception: Exception) {
            resultCollector.notifyProblem(E_NO_IMAGE_DATA_FOUND, exception)
          }
        }) { args ->
          val ex = args[0] as? WritableNativeMap
          val exCode = ex?.getString("code")
          val exMsg = ex?.getString("message")
          if (exCode != null && exMsg != null) {
            resultCollector.notifyProblem(exCode, exMsg)
          }
        }
      )
    }.start()
  }


  private fun resolveRealPath(activity: Activity, uri: Uri, isCamera: Boolean): String? {
    val path = when {
      isCamera -> Uri.parse(mCurrentMediaPath)?.path
      else -> RealPathUtil.getRealPathFromURI(activity, uri)
    }

    return when {
      Build.VERSION.SDK_INT < Build.VERSION_CODES.Q -> path
      else -> {
        val externalCacheDirPath = Uri.fromFile(activity.externalCacheDir)?.path
        val externalFilesDirPath = Uri.fromFile(activity.getExternalFilesDir(null))?.path
        val cacheDirPath = Uri.fromFile(activity.cacheDir)?.path
        val filesDirPath = Uri.fromFile(activity.filesDir)?.path

        when {
          listOf(externalCacheDirPath, externalFilesDirPath, cacheDirPath, filesDirPath).any {
            path?.let { subPath ->
              path.startsWith(
                subPath
              )
            } == true
          } -> path

          else -> {
            val copiedFile = createExternalStoragePrivateFile(activity, uri)
            RealPathUtil.getRealPathFromURI(activity, Uri.fromFile(copiedFile))
          }
        }
      }
    }
  }

  private fun createExternalStoragePrivateFile(context: Context, uri: Uri): File {
    val extension = getExtension(context, uri)
    val file =
      File(context.externalCacheDir, "/temp/${System.currentTimeMillis()}.$extension").apply {
        parentFile?.mkdirs()
      }

    context.contentResolver.openInputStream(uri)?.use { inputStream ->
      try {
        val data = ByteArray(inputStream.available())
        inputStream.read(data)
        FileOutputStream(file).use { outputStream ->
          outputStream.write(data)
        }
      } catch (e: IOException) {
        Log.w("cropping-image-picker", "Error writing $file", e)
      }
    }

    return file
  }

  private fun getExtension(context: Context, uri: Uri): String? {
    return when (uri.scheme) {
      ContentResolver.SCHEME_CONTENT -> {
        val mime = MimeTypeMap.getSingleton()
        mime.getExtensionFromMimeType(context.contentResolver.getType(uri))
      }

      else -> MimeTypeMap.getFileExtensionFromUrl(Uri.fromFile(File(uri.path ?: "")).toString())
    }
  }

  private fun validateImage(path: String): BitmapFactory.Options {
    return BitmapFactory.Options().apply {
      inJustDecodeBounds = true
      inPreferredConfig = Bitmap.Config.RGB_565
      BitmapFactory.decodeFile(path, this)

      if (outMimeType == null || outWidth == 0 || outHeight == 0) {
        throw Exception("Invalid image selected")
      }
    }
  }

  private fun getImage(path: String, mime: String): WritableMap? {
    if (path.startsWith("http://") || path.startsWith("https://")) {
      throw Exception("Cannot select remote files")
    }

    val originalOptions = validateImage(path)
    val localOptions = options
    if (localOptions != null) {
      val responseMap = WritableNativeMap()
      if (mime != "image/gif" || forceJpg) {
        val compressedImage =
          compression.compressImage(reactContext, localOptions, path, originalOptions)
        val compressedImagePath = compressedImage.path
        val compressedImageOptions = validateImage(compressedImagePath)

        responseMap.apply {
          putString("path", "file://$compressedImagePath")
          putInt("width", compressedImageOptions.outWidth)
          putInt("height", compressedImageOptions.outHeight)
          putString("mime", compressedImageOptions.outMimeType)
          putInt("size", File(compressedImagePath).length().toInt())
          putString("modificationDate", File(path).lastModified().toString())
          putString("filename", File(path).name.toString())

          if (includeBase64) {
            putString("data", getBase64StringFromFile(compressedImagePath))
          }
        }
      } else {
        val originalFile = File(path)
        responseMap.apply {
          putString("path", "file://${originalFile.path}")
          putInt("width", originalOptions.outWidth)
          putInt("height", originalOptions.outHeight)
          putString("mime", originalOptions.outMimeType)
          putInt("size", originalFile.length().toInt())
          putString("modificationDate", originalFile.lastModified().toString())
          putString("filename", originalFile.name.toString())

          if (includeBase64) {
            putString("data", getBase64StringFromFile(originalFile.path))
          }
        }
      }

      if (includeExif) {
        try {
          val exif = ExifExtractor.extract(path)
          responseMap.putMap("exif", exif)
        } catch (ex: Exception) {
          ex.printStackTrace()
        }
      }

      return responseMap
    }
    return null
  }

  private fun configureCropperColors(options: UCrop.Options) {
    cropperActiveWidgetColor?.let {
      options.setActiveControlsWidgetColor(Color.parseColor(it))
    }

    cropperToolbarColor?.let {
      options.setToolbarColor(Color.parseColor(it))
    }

    cropperStatusBarColor?.let {
      options.setStatusBarColor(Color.parseColor(it))
    }

    cropperToolbarWidgetColor?.let {
      options.setToolbarWidgetColor(Color.parseColor(it))
    }
  }

  private fun startCropping(activity: Activity, uri: Uri) {
    val options = UCrop.Options().apply {
      setCompressionFormat(Bitmap.CompressFormat.JPEG)
      setCompressionQuality(100)
      setCircleDimmedLayer(cropperCircleOverlay)
      setFreeStyleCropEnabled(freeStyleCropEnabled)
      setShowCropGrid(showCropGuidelines)
      setShowCropFrame(showCropFrame)
      setHideBottomControls(hideBottomControls)

      cropperToolbarTitle?.let { setToolbarTitle(it) }

      if (enableRotationGesture) {
        setAllowedGestures(
          tabScale = UCropActivity.ALL,  // When 'scale'-tab active
          tabRotate = UCropActivity.ALL,  // When 'rotate'-tab active
          tabAspectRatio = UCropActivity.ALL   // When 'aspect ratio'-tab active
        )
      }

      if (!disableCropperColorSetters) {
        configureCropperColors(this)
      }
    }
    val outputPath = Uri.fromFile(File(getTmpDir(activity), "${UUID.randomUUID()}.jpg"))
    val mime = if (uri.scheme == ContentResolver.SCHEME_CONTENT) {
      reactContext.contentResolver.getType(uri)
    } else {
      MimeTypeMap.getFileExtensionFromUrl(uri.toString())?.let {
        MimeTypeMap.getSingleton().getMimeTypeFromExtension(it.lowercase())
      }
    }

    // To be able to crop GIFs, we have to convert them first to JPGs
    if (forceJpg && mime == "image/gif") {
      uri.path?.let {
        val file = getImage(it, mime)
        file?.getString("path")?.let { path ->
          val uCrop = UCrop.of(path.toUri(), outputPath).withOptions(options)
          if (width > 0 && height > 0) {
            uCrop.withAspectRatio(width.toFloat(), height.toFloat())
          }
          uCrop.start(activity)
        }
      }
    } else {
      val uCrop = UCrop.of(uri, outputPath).withOptions(options)
      if (width > 0 && height > 0) {
        uCrop.withAspectRatio(width.toFloat(), height.toFloat())
      }
      uCrop.start(activity)
    }
  }

  private fun imagePickerResult(
    activity: Activity,
    resultCode: Int,
    data: Intent?
  ) {
    when (resultCode) {
      Activity.RESULT_CANCELED -> resultCollector.notifyProblem(
        E_PICKER_CANCELLED_KEY,
        E_PICKER_CANCELLED_MSG
      )

      Activity.RESULT_OK -> {
        if (multiple) {
          val clipData = data?.clipData
          try {
            if (clipData == null) {
              resultCollector.setWaitCount(1)
              data?.data?.let { getAsyncSelection(activity, it) }
            } else {
              resultCollector.setWaitCount(clipData.itemCount)
              for (i in 0 until clipData.itemCount) {
                getAsyncSelection(activity, clipData.getItemAt(i).uri)
              }
            }
          } catch (ex: Exception) {
            resultCollector.notifyProblem(E_NO_IMAGE_DATA_FOUND, ex.message ?: "")
          }
        } else {
          val uri = data?.data
          if (uri == null) {
            resultCollector.notifyProblem(E_NO_IMAGE_DATA_FOUND, "Cannot resolve image url")
            return
          }

          if (cropping) {
            startCropping(activity, uri)
          } else {
            try {
              getAsyncSelection(activity, uri)
            } catch (ex: Exception) {
              resultCollector.notifyProblem(E_NO_IMAGE_DATA_FOUND, ex.message ?: "")
            }
          }
        }
      }
    }
  }

  private fun cameraPickerResult(
    activity: Activity,
    resultCode: Int,
  ) {
    when (resultCode) {
      Activity.RESULT_CANCELED -> resultCollector.notifyProblem(
        E_PICKER_CANCELLED_KEY,
        E_PICKER_CANCELLED_MSG
      )

      Activity.RESULT_OK -> {
        val uri = mCameraCaptureURI

        if (uri == null) {
          resultCollector.notifyProblem(E_NO_IMAGE_DATA_FOUND, "Cannot resolve image url")
          return
        }

        if (cropping) {
          val options = UCrop.Options()
          options.setCompressionFormat(Bitmap.CompressFormat.JPEG)
          startCropping(activity, uri)
        } else {
          try {
            resultCollector.setWaitCount(1)
            val result = getSelection(activity, uri, true)

            // If recording a video, getSelection handles resultCollector part itself and returns null
            result?.let {
              resultCollector.notifySuccess(it)
            }
          } catch (ex: Exception) {
            resultCollector.notifyProblem(E_NO_IMAGE_DATA_FOUND, ex.message ?: "")
          }
        }
      }
    }
  }

  private fun croppingResult(activity: Activity, data: Intent?) {

    data?.let {
      val resultUri = UCrop.getOutput(it)
      if (resultUri != null) {
        try {
          if (width > 0 && height > 0) {
            val resized =
              compression.resize(
                reactContext,
                resultUri.path.toString(),
                width,
                height,
                width,
                height,
                100
              )
            val uri = Uri.fromFile(resized)
            val result = getSelection(activity, uri, false)

            result?.let { writeableMap ->
              writeableMap.putMap("cropRect", getCroppedRectMap(data))
              resultCollector.setWaitCount(1)
              resultCollector.notifySuccess(writeableMap)
            } ?: throw Exception("Cannot crop video files")
          }
        } catch (ex: Exception) {
          resultCollector.notifyProblem(E_NO_IMAGE_DATA_FOUND, ex.message ?: "")
        }
      } else {
        resultCollector.notifyProblem(E_NO_IMAGE_DATA_FOUND, "Cannot find image data")
      }
    } ?: run {
      resultCollector.notifyProblem(E_PICKER_CANCELLED_KEY, E_PICKER_CANCELLED_MSG)
    }
  }


  override fun onActivityResult(
    activity: Activity,
    requestCode: Int,
    resultCode: Int,
    data: Intent?
  ) {
    when (requestCode) {
      IMAGE_PICKER_REQUEST -> imagePickerResult(activity, resultCode, data)
      CAMERA_PICKER_REQUEST -> cameraPickerResult(activity, resultCode)
      UCrop.REQUEST_CROP -> croppingResult(activity, data)
    }
  }

  override fun onNewIntent(intent: Intent) {}

  private fun isCameraAvailable(activity: Activity): Boolean {
    val pm = activity.packageManager
    return pm.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
  }

  @Throws(IOException::class)
  private fun createImageFile(): File {
    val imageFileName = "image-${UUID.randomUUID()}"
    val path = reactContext.getExternalFilesDir(Environment.DIRECTORY_PICTURES)
    path?.run {
      if (!exists() && !isDirectory) {
        mkdirs()
      }
    }
    val image = File.createTempFile(imageFileName, ".jpg", path)
    mCurrentMediaPath = "file:${image.absolutePath}"
    return image
  }

  @Throws(IOException::class)
  private fun createVideoFile(): File {
    val videoFileName = "video-${UUID.randomUUID()}"
    val path = reactContext.getExternalFilesDir(Environment.DIRECTORY_PICTURES)
    path?.run {
      if (!exists() && !isDirectory) {
        mkdirs()
      }
    }
    val video = File.createTempFile(videoFileName, ".mp4", path)
    mCurrentMediaPath = "file:${video.absolutePath}"
    return video
  }

  private fun getCroppedRectMap(data: Intent): WritableMap {
    val defaultValue = -1
    return WritableNativeMap().apply {
      putInt("x", data.getIntExtra(UCrop.EXTRA_OUTPUT_OFFSET_X, defaultValue))
      putInt("y", data.getIntExtra(UCrop.EXTRA_OUTPUT_OFFSET_Y, defaultValue))
      putInt("width", data.getIntExtra(UCrop.EXTRA_OUTPUT_IMAGE_WIDTH, defaultValue))
      putInt("height", data.getIntExtra(UCrop.EXTRA_OUTPUT_IMAGE_HEIGHT, defaultValue))
    }
  }

  companion object {
    const val NAME = "CroppingImagePicker"
    private const val IMAGE_PICKER_REQUEST = 61110
    private const val CAMERA_PICKER_REQUEST = 61111
    private const val E_ACTIVITY_DOES_NOT_EXIST_KEY = "E_ACTIVITY_DOES_NOT_EXIST"
    private const val E_ACTIVITY_DOES_NOT_EXIST_MSG = "Activity doesn't exist"

    private const val E_PICKER_CANCELLED_KEY = "E_PICKER_CANCELLED"
    private const val E_PICKER_CANCELLED_MSG = "User cancelled image selection"

    private const val E_CALLBACK_ERROR = "E_CALLBACK_ERROR"
    private const val E_FAILED_TO_SHOW_PICKER = "E_FAILED_TO_SHOW_PICKER"
    private const val E_FAILED_TO_OPEN_CAMERA = "E_FAILED_TO_OPEN_CAMERA"
    private const val E_NO_IMAGE_DATA_FOUND = "E_NO_IMAGE_DATA_FOUND"
    private const val E_CAMERA_IS_NOT_AVAILABLE = "E_CAMERA_IS_NOT_AVAILABLE"
    private const val E_CANNOT_LAUNCH_CAMERA = "E_CANNOT_LAUNCH_CAMERA"
    private const val E_ERROR_WHILE_CLEANING_FILES = "E_ERROR_WHILE_CLEANING_FILES"

    private const val E_NO_LIBRARY_PERMISSION_KEY = "E_NO_LIBRARY_PERMISSION"
    private const val E_NO_LIBRARY_PERMISSION_MSG = "User did not grant library permission."
    private const val E_NO_CAMERA_PERMISSION_KEY = "E_NO_CAMERA_PERMISSION"
    private const val E_NO_CAMERA_PERMISSION_MSG = "User did not grant camera permission."
  }
}
