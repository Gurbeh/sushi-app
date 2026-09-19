package app.sushi.tdlibbridge.session

import java.util.concurrent.Executors
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * Process-wide serialization for every call that crosses into the gomobile-bound oxtelegram.aar
 * runtime — mobile.Client AND mobile.PlaybackSession alike, since both compile into the same
 * generated JNI layer. Confirmed live, twice, that two such calls entering at once crashes the
 * whole process with `fatal error: bulkBarrierPreWrite: unaligned arguments`, on both an x86_64
 * emulator and an arm64 device: first two Sushi protocol calls overlapping (mobile.Client, fixed
 * with a Dart-side queue too), then stopPlaybackSession's cleanup path (mobile.PlaybackSession.close,
 * via OxTelegramFileFetcher) racing a protocol call.
 *
 * A Kotlin Mutex alone is not enough: [kotlinx.coroutines.Dispatchers.IO] is a pool, so two
 * serialized-in-time callers still hop onto different OS threads, and gomobile's Seq/JNI layer
 * has been observed to fault that way after ExoPlayer.release (DataSource ensureAvailable on a
 * loader thread) overlapping sendTextAndWaitReply. Every JNI entry therefore also runs on one
 * dedicated thread.
 *
 * Shared across [OxTelegramClient], [app.sushi.tdlibbridge.media.OxTelegramFileFetcher], and
 * [app.sushi.tdlibbridge.player.OxTelegramStreamBridge].
 *
 * "Cheap" in-memory gomobile getters (armDeliveryWaiter, deliveryRef, isBotMode) used to skip
 * this gate so a 30s sendTextAndWaitReply would not stall a sync Pigeon poll. Confirmed live
 * 2026-09-19 on Pixel 10 Pro: those JNI entries overlapping HTTP ensureAvailable crashed with
 * the same `bulkBarrierPreWrite: unaligned arguments` during subtitle push + prefetch. Every
 * gomobile entry has to come through here; sync Pigeon uses [tryEnterBlocking] / [enqueue]
 * instead of waiting out a long protocol call on the platform thread.
 */
object GomobileCallGate {
    val mutex = Mutex()

    private val executor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "ox-gomobile").apply { isDaemon = true }
    }
    val dispatcher = executor.asCoroutineDispatcher()

    private val enqueueScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    suspend fun <T> enter(block: () -> T): T =
        mutex.withLock {
            withContext(dispatcher) { block() }
        }

    /**
     * Sync Pigeon / platform-thread reads. If a long JNI holder already owns the gate, return
     * [ifBusy] (a Kotlin cache) instead of blocking the UI thread for the holder's full timeout.
     *
     * Lock order matches [enter]: acquire [mutex] first, then hop onto [dispatcher]. Never launch
     * onto [dispatcher] and then wait for [mutex] — that deadlocks the single ox-gomobile thread
     * against a holder already queued for it.
     */
    fun <T> tryEnterBlocking(ifBusy: () -> T, block: () -> T): T {
        if (!mutex.tryLock()) return ifBusy()
        return try {
            runBlocking(dispatcher) { block() }
        } finally {
            mutex.unlock()
        }
    }

    /** Fire-and-forget JNI (armDeliveryWaiter). Same lock order as [enter]. */
    fun enqueue(block: () -> Unit) {
        enqueueScope.launch {
            mutex.withLock {
                withContext(dispatcher) { block() }
            }
        }
    }
}
