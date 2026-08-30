package com.compress.all.flutter_compress

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * The foreground service is opt-in, and `NotificationSpec.fromMap` is the gate.
 * A spec that parses to null means no service is ever started — so these cases
 * are the difference between "the app opted in" and "the plugin quietly shows a
 * notification nobody designed".
 */
class NotificationSpecTest {

    private fun spec(vararg pairs: Pair<String, Any?>) =
        CompressionService.NotificationSpec.fromMap(mapOf(*pairs))

    @Test
    fun `no config at all means no service`() {
        assertNull(CompressionService.NotificationSpec.fromMap(null))
    }

    @Test
    fun `a missing icon means no service`() {
        assertNull(spec("title" to "Compressing"))
    }

    @Test
    fun `a missing title means no service`() {
        // Android would show an untitled notification; refuse instead.
        assertNull(spec("smallIcon" to "drawable/ic_x"))
    }

    @Test
    fun `blank strings count as missing`() {
        assertNull(spec("smallIcon" to "", "title" to "Compressing"))
        assertNull(spec("smallIcon" to "drawable/ic_x", "title" to "   "))
    }

    @Test
    fun `wrong types count as missing rather than crashing`() {
        // Values arrive from a platform channel, so anything can turn up here.
        assertNull(spec("smallIcon" to 42, "title" to "Compressing"))
        assertNull(spec("smallIcon" to "drawable/ic_x", "title" to listOf("x")))
    }

    @Test
    fun `a complete spec parses`() {
        val parsed = spec(
            "smallIcon" to "drawable/ic_compress",
            "title" to "Compressing video",
            "text" to "1 of 3",
            "channelName" to "Media",
        )
        assertEquals("drawable/ic_compress", parsed?.smallIcon)
        assertEquals("Compressing video", parsed?.title)
        assertEquals("1 of 3", parsed?.text)
        assertEquals("Media", parsed?.channelName)
    }

    @Test
    fun `optional fields stay null instead of getting a plugin default`() {
        // channelName falls back to the title at build time, not to a string
        // this plugin invented.
        val parsed = spec("smallIcon" to "ic_compress", "title" to "Compressing")
        assertNull(parsed?.text)
        assertNull(parsed?.channelName)
    }
}
