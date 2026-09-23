package app.sushi.tdlibbridge.session

import kotlinx.coroutines.runBlocking
import mobile.AuthEventSink
import mobile.Client
import mobile.ConnectionSink
import mobile.PlaybackSession
import mobile.SessionStorage

/**
 * Coroutine-friendly wrapper around the gomobile-bound mobile.Client (github.com/gotd/td facade,
 * go/oxtelegram) — the replacement for TdlibClient. Every mobile.Client method is already a
 * plain blocking JNI call (gotd/td's auth API is call/response, not TDLib's async
 * request/response protocol needing a CompletableDeferred bridge).
 *
 * [GomobileCallGate] serializes every method that actually crosses into gomobile's generated JNI
 * bridge against [app.sushi.tdlibbridge.media.OxTelegramFileFetcher] and
 * [app.sushi.tdlibbridge.player.OxTelegramStreamBridge] — see GomobileCallGate's doc. Sync Pigeon
 * polls (deliveryRef, isBotMode, armDeliveryWaiter) used to skip the gate; they do not anymore.
 */
class OxTelegramClient(
    apiId: Long,
    apiHash: String,
    storage: SessionStorage,
) {
    val native: Client = Client(apiId, apiHash, storage)

    @Volatile private var cachedBotMode: Boolean = false
    @Volatile private var cachedHealth: String = "uninitialized"
    private val deliveryRefCache = java.util.concurrent.ConcurrentHashMap<String, Pair<Long, Long>>()

    suspend fun configure(sink: AuthEventSink) =
        GomobileCallGate.enter { native.configure(sink) }

    /**
     * Rebuilds the connection if its run loop died; no-op when healthy. See mobile.Client's doc for
     * why "already configured" must never be assumed from the presence of a client object alone.
     */
    suspend fun ensureConnected(sink: AuthEventSink) =
        GomobileCallGate.enter { native.ensureConnected(sink) }

    /** Registers the connection-health listener. Reconnection happens with or without one. */
    fun setConnectionSink(sink: ConnectionSink?) {
        runBlocking { GomobileCallGate.enter { native.setConnectionSink(sink) } }
    }

    /**
     * "uninitialized" / "connecting" / "ready" / "degraded" — TdlibBridgeObject answers Pigeon
     * from lastConnectionHealth; this native read is only for callers that still go through JNI.
     */
    fun connectionHealth(): String =
        GomobileCallGate.tryEnterBlocking(ifBusy = { cachedHealth }) {
            native.connectionHealth().also { cachedHealth = it }
        }

    /**
     * Whether the CURRENT session is a bot, including one restored from disk at configure() —
     * accurate on a cold app start unlike Dart's own submitBotToken-tracked flag.
     */
    fun isBotMode(): Boolean =
        GomobileCallGate.tryEnterBlocking(ifBusy = { cachedBotMode }) {
            native.isBotMode().also { cachedBotMode = it }
        }

    suspend fun submitPhoneNumber(phone: String) =
        GomobileCallGate.enter { native.submitPhoneNumber(phone) }

    suspend fun submitBotToken(token: String) =
        GomobileCallGate.enter { native.submitBotToken(token) }

    suspend fun submitCode(code: String) =
        GomobileCallGate.enter { native.submitCode(code) }

    suspend fun submitTwoFactorPassword(password: String) =
        GomobileCallGate.enter { native.submitTwoFactorPassword(password) }

    suspend fun requestQrLogin() =
        GomobileCallGate.enter { native.requestQrLogin() }

    suspend fun logOut() = GomobileCallGate.enter { native.logOut() }

    suspend fun startPlaybackSession(
        providerBotId: Long,
        messageId: Long,
        cacheDir: String,
        locator: String,
    ): PlaybackSession =
        GomobileCallGate.enter("startPlayback") {
            native.startPlaybackSession(providerBotId, messageId, cacheDir, locator)
        }

    /**
     * Resolves the delivery and records where it landed, without opening a download — the warm-up
     * path. Still a real MTProto call, so it belongs on Dispatchers.IO.
     */
    suspend fun warmDelivery(providerBotId: Long, messageId: Long, locator: String) =
        GomobileCallGate.enter("warmDelivery") { native.warmDelivery(providerBotId, messageId, locator) }

    /**
     * Starts, mutes and archives every delivery sender. [botsJson] is
     * `[{"id":123,"username":"SomeBot"}]` — gomobile cannot bind a slice of structs, so the list
     * crosses the JNI boundary as JSON.
     */
    suspend fun ensureProviderBotsReady(botsJson: String) =
        GomobileCallGate.enter { native.ensureProviderBotsReady(botsJson) }

    /**
     * Registers interest in [locator] before the delivery is requested. Enqueued on the gate —
     * returning before the JNI runs is safe: Go already buffers an early push (pushArrived).
     */
    fun armDeliveryWaiter(locator: String) {
        GomobileCallGate.enqueue("armWaiter") { native.armDeliveryWaiter(locator) }
    }

    /** Message id + sending bot this session read for [locator], or zeros. */
    fun deliveryRef(locator: String): Pair<Long, Long> =
        GomobileCallGate.tryEnterBlocking(
            op = "deliveryRef",
            ifBusy = { deliveryRefCache[locator] ?: (0L to 0L) },
        ) {
            val id = native.deliveryMessageIDForLocator(locator)
            val bot = native.deliveryProviderBotIDForLocator(locator)
            (id to bot).also { deliveryRefCache[locator] = it }
        }

    /**
     * The DM message id this session read for [locator], or 0.
     */
    fun deliveryMessageIDForLocator(locator: String): Long = deliveryRef(locator).first

    /** The delivery bot whose DM held [locator], or 0. */
    fun deliveryProviderBotIDForLocator(locator: String): Long = deliveryRef(locator).second

    suspend fun fetchWebAppInitData(
        botUsername: String,
        webAppShortName: String,
        hostedHttpsUrl: String,
        platform: String = "android",
    ): String = GomobileCallGate.enter {
        native.fetchWebAppInitData(botUsername, webAppShortName, hostedHttpsUrl, platform)
    }

    /** DMs [username] with [text]; returns next '!' framed reply (Sushi /initbot). */
    suspend fun sendTextAndWaitReply(username: String, text: String, timeoutMs: Int): String =
        GomobileCallGate.enter("sendText") { native.sendTextAndWaitReply(username, text, timeoutMs.toLong()) }

    /** Whole subtitle document from this session's chat (doc 15 §7 live-push resolve). */
    suspend fun fetchSmallDocument(
        botId: Long,
        messageId: Long,
        locator: String,
        timeoutMs: Int,
        cacheDir: String,
    ): String = GomobileCallGate.enter("fetchSmall") {
        native.fetchSmallDocument(botId, messageId, locator, timeoutMs.toLong(), cacheDir)
    }

    /** DMs [username] with [text] without waiting for a reply (Sushi `/ack`, future watch-progress
     *  reports) — see mobile.Client.SendTextFireAndForget. */
    suspend fun sendTextFireAndForget(username: String, text: String) =
        GomobileCallGate.enter("sendFire") { native.sendTextFireAndForget(username, text) }

    /** Clicks a session account through main-bot's onboarding conversation (Sushi /initbot). */
    suspend fun ensureMainBotOnboarded(username: String, timeoutMs: Int) =
        GomobileCallGate.enter { native.ensureMainBotOnboarded(username, timeoutMs.toLong()) }

    /** Fire-and-forget from the caller's perspective — mirrors TdlibClient.close(). */
    fun close() {
        runCatching { runBlocking { GomobileCallGate.enter { native.close() } } }
    }
}
