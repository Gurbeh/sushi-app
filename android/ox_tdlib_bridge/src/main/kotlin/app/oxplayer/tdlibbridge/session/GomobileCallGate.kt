package app.oxplayer.tdlibbridge.session

import java.util.concurrent.Executors
import kotlinx.coroutines.asCoroutineDispatcher
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
 * Shared across [OxTelegramClient], [app.oxplayer.tdlibbridge.media.OxTelegramFileFetcher], and
 * [app.oxplayer.tdlibbridge.player.OxTelegramStreamBridge].
 */
object GomobileCallGate {
    val mutex = Mutex()

    private val executor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "ox-gomobile").apply { isDaemon = true }
    }
    val dispatcher = executor.asCoroutineDispatcher()

    suspend fun <T> enter(block: () -> T): T =
        mutex.withLock {
            withContext(dispatcher) { block() }
        }
}
