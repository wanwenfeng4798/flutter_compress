package com.compress.all.flutter_compress

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Process
import android.util.Log
import java.util.concurrent.atomic.AtomicInteger

/**
 * Keeps an encode alive while the host app is backgrounded.
 *
 * Everything user-visible — icon, title, body, channel name — comes from the
 * app via [NotificationSpec]. The plugin supplies **no defaults**: a
 * foreground-service notification is prominent UI, and an icon or wording chosen
 * by a library is guaranteed to look foreign in someone else's app.
 *
 * Consequently the service is strictly opt-in. [start] refuses unless all three
 * hold, and simply logs otherwise so the encode continues foreground-only:
 *
 *  1. the app passed a notification spec,
 *  2. its `smallIcon` resolves against the app's resources,
 *  3. the app declared the foreground-service permission.
 */
class CompressionService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val spec = NotificationSpec.fromIntent(intent)
        if (spec == null) {
            // Nothing to show. Stop rather than sit in the foreground illegally.
            stopSelf()
            return START_NOT_STICKY
        }
        val iconId = spec.resolveIcon(this)
        if (iconId == 0) {
            stopSelf()
            return START_NOT_STICKY
        }
        startForegroundCompat(buildNotification(spec, iconId))
        return START_NOT_STICKY
    }

    private fun buildNotification(spec: NotificationSpec, iconId: Int): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    spec.channelName ?: spec.title,
                    // LOW: no sound, no heads-up. A progress notification that
                    // buzzes is worse than none.
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
            return Notification.Builder(this, CHANNEL_ID)
                .setContentTitle(spec.title)
                .apply { spec.text?.let { setContentText(it) } }
                .setSmallIcon(iconId)
                .setOngoing(true)
                .build()
        }
        @Suppress("DEPRECATION")
        return Notification.Builder(this)
            .setContentTitle(spec.title)
            .apply { spec.text?.let { setContentText(it) } }
            .setSmallIcon(iconId)
            .setOngoing(true)
            .build()
    }

    private fun startForegroundCompat(notification: Notification) {
        // API 34 requires every foreground service to declare its type at start.
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(
                NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    /** The app-supplied notification, carried to the service as Intent extras. */
    class NotificationSpec(
        val smallIcon: String,
        val title: String,
        val text: String?,
        val channelName: String?,
    ) {
        /**
         * Resolve `"type/name"` (or a bare name, meaning a drawable) against the
         * **app's** resources. Returns 0 when it doesn't exist, which is the
         * signal not to start at all — `setSmallIcon(0)` yields a blank status
         * bar entry on some OEMs and throws on others.
         */
        fun resolveIcon(context: Context): Int {
            val type: String
            val name: String
            val slash = smallIcon.indexOf('/')
            if (slash > 0) {
                type = smallIcon.substring(0, slash)
                name = smallIcon.substring(slash + 1)
            } else {
                type = "drawable"
                name = smallIcon
            }
            if (name.isBlank()) return 0
            val id = context.resources.getIdentifier(name, type, context.packageName)
            if (id == 0) {
                Log.w(
                    TAG,
                    "androidNotification.smallIcon '$smallIcon' does not resolve in this app; " +
                        "encoding without background protection",
                )
            }
            return id
        }

        fun into(intent: Intent): Intent = intent.apply {
            putExtra(EXTRA_ICON, smallIcon)
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_TEXT, text)
            putExtra(EXTRA_CHANNEL, channelName)
        }

        companion object {
            fun fromMap(m: Map<String, Any?>?): NotificationSpec? {
                val icon = (m?.get("smallIcon") as? String)?.takeIf { it.isNotBlank() } ?: return null
                val title = (m["title"] as? String)?.takeIf { it.isNotBlank() } ?: return null
                return NotificationSpec(
                    smallIcon = icon,
                    title = title,
                    text = (m["text"] as? String)?.takeIf { it.isNotBlank() },
                    channelName = (m["channelName"] as? String)?.takeIf { it.isNotBlank() },
                )
            }

            fun fromIntent(intent: Intent?): NotificationSpec? {
                val icon = intent?.getStringExtra(EXTRA_ICON)?.takeIf { it.isNotBlank() } ?: return null
                val title = intent.getStringExtra(EXTRA_TITLE)?.takeIf { it.isNotBlank() } ?: return null
                return NotificationSpec(
                    icon, title,
                    intent.getStringExtra(EXTRA_TEXT),
                    intent.getStringExtra(EXTRA_CHANNEL),
                )
            }
        }
    }

    companion object {
        private const val TAG = "FlutterCompress"
        private const val CHANNEL_ID = "flutter_compress_channel"
        private const val NOTIFICATION_ID = 0x7C01
        private const val EXTRA_ICON = "smallIcon"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_CHANNEL = "channelName"

        /**
         * Jobs currently holding the service up. A plain boolean would let one
         * engine's `stop` kill the notification while another is still encoding.
         */
        private val holders = AtomicInteger(0)

        private val mainHandler = Handler(Looper.getMainLooper())

        /**
         * A deferred `stopService`, cancelled if another job starts first.
         *
         * `compressAll` is a Dart-side loop that calls `compress()` once per
         * item, so stopping the instant a job ends would make the notification
         * flicker between items — and worse, on API 31+ the *restart* can be
         * refused outright if the app has gone to background by then, silently
         * dropping background protection for the rest of the batch.
         */
        private var pendingStop: Runnable? = null

        /** Long enough to bridge the gap between two items of a batch. */
        private const val LINGER_MS = 2_000L

        /**
         * Whether the app declared the permission the service needs.
         *
         * The plugin declares none, so a GRANTED result on these install-time
         * permissions means exactly "the app opted in". `POST_NOTIFICATIONS` is
         * not checked: without it the service still runs, just silently.
         */
        private fun permitted(context: Context): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return true
            if (!granted(context, "android.permission.FOREGROUND_SERVICE")) return false
            if (Build.VERSION.SDK_INT >= 34 &&
                !granted(context, "android.permission.FOREGROUND_SERVICE_DATA_SYNC")
            ) {
                return false
            }
            return true
        }

        private fun granted(context: Context, permission: String): Boolean =
            context.checkPermission(permission, Process.myPid(), Process.myUid()) ==
                PackageManager.PERMISSION_GRANTED

        /**
         * Start the service if the app opted in on both counts. Returns whether
         * it was started, so [stop] stays balanced.
         */
        fun start(context: Context, spec: NotificationSpec?): Boolean {
            if (spec == null) return false
            if (spec.resolveIcon(context) == 0) return false
            if (!permitted(context)) {
                Log.i(
                    TAG,
                    "androidNotification was supplied but the app declares no " +
                        "FOREGROUND_SERVICE permission; encoding without background protection.",
                )
                return false
            }
            // A stop may be waiting out its linger; keep the service instead.
            pendingStop?.let {
                mainHandler.removeCallbacks(it)
                pendingStop = null
            }
            if (holders.getAndIncrement() > 0) return true
            val intent = spec.into(Intent(context, CompressionService::class.java))
            return try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                true
            } catch (e: RuntimeException) {
                // Android can still refuse the start (API 31+ background-start
                // restrictions). Never abort the encode over it.
                holders.decrementAndGet()
                Log.w(TAG, "Foreground service refused; encoding without background protection", e)
                false
            }
        }

        fun stop(context: Context) {
            if (holders.get() <= 0 || holders.decrementAndGet() > 0) return
            pendingStop?.let { mainHandler.removeCallbacks(it) }
            val task = Runnable {
                pendingStop = null
                // A new job claimed the service while we waited.
                if (holders.get() > 0) return@Runnable
                runCatching {
                    context.stopService(Intent(context, CompressionService::class.java))
                }.onFailure { Log.w(TAG, "Could not stop foreground service", it) }
            }
            pendingStop = task
            mainHandler.postDelayed(task, LINGER_MS)
        }
    }
}
