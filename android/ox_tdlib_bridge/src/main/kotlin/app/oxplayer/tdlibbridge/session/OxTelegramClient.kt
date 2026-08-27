package app.oxplayer.tdlibbridge.session

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
 * bridge against [app.oxplayer.tdlibbridge.media.OxTelegramFileFetcher] and
 * [app.oxplayer.tdlibbridge.player.OxTelegramStreamBridge] — see GomobileCallGate's doc. Cheap
 * in-memory reads (connectionHealth, isBotMode, armDeliveryWaiter, locator lookups) stay off the
 * gate so a 30s protocol call cannot stall a sync Pigeon poll.
 */
class OxTelegramClient(
    apiId: Long,
    apiHash: String,
    storage: SessionStorage,
) {
    val native: Client = Client(apiId, apiHash, storage)

    suspend fun configure(sink: AuthEventSink) =
        GomobileCallGate.enter { native.configure(sink) }

    /**
     * Rebuilds the connection if its run loop died; no-op when healthy. See mobile.Client's doc for
     * why "already configured" must never be assumed from the presence of a client object alone.
     */
    suspend fun ensureConnected(sink: AuthEventSink) =
        GomobileCallGate.enter { native.ensureConnected(sink) }

    /** Registers the connection-health listener. Reconnection happens with or without one. */
    fun setConnectionSink(sink: ConnectionSink?) = native.setConnectionSink(sink)

    /**
     * "uninitialized" / "connecting" / "ready" / "degraded" — an in-memory read on the Go side, so
     * it stays off Dispatchers.IO and can answer a synchronous Pigeon call.
     */
    fun connectionHealth(): String = native.connectionHealth()

    /**
     * Whether the CURRENT session is a bot, including one restored from disk at configure() —
     * accurate on a cold app start unlike Dart's own submitBotToken-tracked flag. In-memory read
     * on the Go side, so it stays off Dispatchers.IO and can answer a synchronous Pigeon call.
     */
    fun isBotMode(): Boolean = native.isBotMode()

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
        GomobileCallGate.enter {
            native.startPlaybackSession(providerBotId, messageId, cacheDir, locator)
        }

    /**
     * Resolves the delivery and records where it landed, without opening a download — the warm-up
     * path. Still a real MTProto call, so it belongs on Dispatchers.IO.
     */
    suspend fun warmDelivery(providerBotId: Long, messageId: Long, locator: String) =
        GomobileCallGate.enter { native.warmDelivery(providerBotId, messageId, locator) }

    /**
     * Starts, mutes and archives every delivery sender. [botsJson] is
     * `[{"id":123,"username":"SomeBot"}]` — gomobile cannot bind a slice of structs, so the list
     * crosses the JNI boundary as JSON.
     */
    suspend fun ensureProviderBotsReady(botsJson: String) =
        GomobileCallGate.enter { native.ensureProviderBotsReady(botsJson) }

    /**
     * Registers interest in [locator] before the delivery is requested. Touches an in-memory map on
     * the Go side — no MTProto round-trip, so it stays off Dispatchers.IO.
     */
    fun armDeliveryWaiter(locator: String) = native.armDeliveryWaiter(locator)

    /**
     * The DM message id this session read for [locator], or 0. Reads an in-memory map on the Go
     * side — no MTProto round-trip, so it stays off Dispatchers.IO and can answer a synchronous
     * Pigeon call.
     */
    fun deliveryMessageIDForLocator(locator: String): Long = native.deliveryMessageIDForLocator(locator)

    /** The delivery bot whose DM held [locator], or 0. Same in-memory read as above. */
    fun deliveryProviderBotIDForLocator(locator: String): Long = native.deliveryProviderBotIDForLocator(locator)

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
        GomobileCallGate.enter { native.sendTextAndWaitReply(username, text, timeoutMs.toLong()) }

    /** DMs [username] with [text] without waiting for a reply (Sushi `/ack`, future watch-progress
     *  reports) — see mobile.Client.SendTextFireAndForget. */
    suspend fun sendTextFireAndForget(username: String, text: String) =
        GomobileCallGate.enter { native.sendTextFireAndForget(username, text) }

    /** Clicks a session account through main-bot's onboarding conversation (Sushi /initbot). */
    suspend fun ensureMainBotOnboarded(username: String, timeoutMs: Int) =
        GomobileCallGate.enter { native.ensureMainBotOnboarded(username, timeoutMs.toLong()) }

    /** Fire-and-forget from the caller's perspective — mirrors TdlibClient.close(). */
    fun close() {
        runCatching { runBlocking { GomobileCallGate.enter { native.close() } } }
    }
}
