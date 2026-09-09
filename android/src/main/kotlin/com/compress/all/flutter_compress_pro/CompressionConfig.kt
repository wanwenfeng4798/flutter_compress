package com.compress.all.flutter_compress_pro

/** Parsed mirror of the Dart [VideoCompressConfig]. */
data class CompressionConfig(
    val quality: String,
    val qualityPercent: Int?,
    val targetSizeMB: Int?,
    val videoBitrateKbps: Int?,
    val codec: String,
    val maxWidth: Int?,
    val maxHeight: Int?,
    val frameRate: Double?,
    val removeAudio: Boolean,
    val audioBitrateKbps: Int?,
    val trimStartMs: Long?,
    val trimEndMs: Long?,
    val alignment: String,
    val keepOriginalIfLarger: Boolean,
    val minSavingsPercent: Int,
    val notification: CompressionService.NotificationSpec?,
) {
    companion object {
        fun fromMap(m: Map<String, Any?>): CompressionConfig {
            @Suppress("UNCHECKED_CAST")
            val trim = m["trim"] as? Map<String, Any?>

            @Suppress("UNCHECKED_CAST")
            val notification = m["androidNotification"] as? Map<String, Any?>
            return CompressionConfig(
                quality = m["quality"] as? String ?: "medium",
                qualityPercent = (m["qualityPercent"] as? Number)?.toInt(),
                targetSizeMB = (m["targetSizeMB"] as? Number)?.toInt(),
                videoBitrateKbps = (m["videoBitrateKbps"] as? Number)?.toInt(),
                codec = m["codec"] as? String ?: "h265",
                maxWidth = (m["maxWidth"] as? Number)?.toInt(),
                maxHeight = (m["maxHeight"] as? Number)?.toInt(),
                frameRate = (m["frameRate"] as? Number)?.toDouble(),
                removeAudio = m["removeAudio"] as? Boolean ?: false,
                audioBitrateKbps = (m["audioBitrateKbps"] as? Number)?.toInt(),
                trimStartMs = (trim?.get("startMs") as? Number)?.toLong(),
                trimEndMs = (trim?.get("endMs") as? Number)?.toLong(),
                alignment = m["alignment"] as? String ?: "auto16",
                keepOriginalIfLarger = m["keepOriginalIfLarger"] as? Boolean ?: true,
                minSavingsPercent = (m["minSavingsPercent"] as? Number)?.toInt() ?: 0,
                notification = CompressionService.NotificationSpec.fromMap(notification),
            )
        }
    }
}

/**
 * The host app did not declare a permission the operation needs. The plugin
 * declares none of its own, so this always means "the app has to opt in".
 */
internal class PermissionDeniedException(message: String) : SecurityException(message)

/** Thrown when a job is cancelled. */
class CompressionCancelledException(message: String = "Compression cancelled") :
    Exception(message)
