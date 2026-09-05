package app.oxplayer.composables.dialogs

import SushiAiKeySetup
import SushiOnlineSubtitlePack
import SushiSubtitleActionResult
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.util.Log
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import app.oxplayer.objects.VideoPlayerObject
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter

@Composable
fun SushiOnlineSubtitleSheet(onDismissRequest: () -> Unit) {
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var packs by remember { mutableStateOf<List<SushiOnlineSubtitlePack>>(emptyList()) }
    var files by remember { mutableStateOf<List<String>>(emptyList()) }
    var openTag by remember { mutableStateOf<String?>(null) }
    var status by remember { mutableStateOf<String?>(null) }

    fun loadPacks() {
        loading = true
        error = null
        files = emptyList()
        openTag = null
        VideoPlayerObject.videoPlayerControls?.searchSushiOnlineSubtitles { result ->
            loading = false
            result.fold(
                onSuccess = { list ->
                    packs = list
                    if (list.isEmpty()) error = "No subtitles found"
                },
                onFailure = { error = it.message ?: "Could not load subtitle" },
            )
        }
    }

    fun applyResult(result: Result<SushiSubtitleActionResult>, closeOnOk: Boolean = true) {
        loading = false
        result.fold(
            onSuccess = { r ->
                when {
                    r.ok -> {
                        status = r.label ?: "Subtitle loaded"
                        if (closeOnOk) onDismissRequest()
                    }
                    r.errorCode == "need_pick" -> {
                        openTag = r.tag
                        files = r.fileNames ?: emptyList()
                    }
                    r.errorCode == "no_results" -> error = "No subtitles found"
                    else -> error = "Could not load subtitle"
                }
            },
            onFailure = { error = it.message ?: "Could not load subtitle" },
        )
    }

    LaunchedEffect(Unit) { loadPacks() }

    CustomModalBottomSheet(onDismissRequest, maxWidth = 600.dp) {
        LazyColumn(
            modifier = Modifier
                .wrapContentWidth()
                .padding(horizontal = 8.dp, vertical = 16.dp),
        ) {
            item {
                Text(
                    text = status ?: "Online subtitles",
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                )
            }
            if (loading) {
                item {
                    CircularProgressIndicator(modifier = Modifier.padding(24.dp))
                }
            } else if (error != null) {
                item {
                    TrackButton(onClick = { loadPacks() }, modifier = Modifier.fillMaxWidth()) {
                        Text(error!!)
                    }
                }
            } else if (files.isNotEmpty() && openTag != null) {
                item {
                    TrackButton(
                        onClick = {
                            files = emptyList()
                            openTag = null
                        },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text("Back to results")
                    }
                }
                items(files) { name ->
                    TrackButton(
                        onClick = {
                            loading = true
                            VideoPlayerObject.videoPlayerControls?.downloadSushiOnlineSubtitle(
                                openTag!!,
                                name,
                            ) { applyResult(it) }
                        },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(name)
                    }
                }
            } else {
                items(packs) { pack ->
                    TrackButton(
                        onClick = {
                            loading = true
                            VideoPlayerObject.videoPlayerControls?.downloadSushiOnlineSubtitle(
                                pack.tag,
                                "",
                            ) { applyResult(it) }
                        },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Column {
                            Text(pack.hint.ifBlank { pack.title })
                            if (pack.hint.isNotBlank() && pack.title.isNotBlank()) {
                                Text(pack.title)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun SushiAiKeyMissingSheet(onDismissRequest: () -> Unit) {
    var setup by remember { mutableStateOf<SushiAiKeySetup?>(null) }
    var showQr by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf<String?>(null) }
    val context = LocalContext.current

    LaunchedEffect(Unit) {
        VideoPlayerObject.videoPlayerControls?.sushiAiKeySetup { result ->
            result.onSuccess { setup = it }
            result.onFailure { status = it.message }
        }
    }

    CustomModalBottomSheet(onDismissRequest, maxWidth = 520.dp) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text("Translate with AI (Persian)")
            Text("AI translate needs a free Gemini API key. Set it in the Sushi bot.")
            if (status != null) Text(status!!)
            val info = setup
            if (info == null) {
                CircularProgressIndicator()
            } else if (!info.telegramInstalled || showQr) {
                val bmp = remember(info.deepLink) { qrBitmap(info.deepLink) }
                if (bmp != null) {
                    Image(
                        bitmap = bmp.asImageBitmap(),
                        contentDescription = "QR",
                        modifier = Modifier.size(220.dp),
                    )
                } else {
                    Text(info.deepLink)
                }
                if (info.telegramInstalled) {
                    TrackButton(onClick = { showQr = false }, modifier = Modifier.fillMaxWidth()) {
                        Text("Hide QR")
                    }
                }
            } else {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    TrackButton(
                        modifier = Modifier.weight(1f),
                        onClick = {
                            try {
                                context.startActivity(
                                    Intent(Intent.ACTION_VIEW, Uri.parse(info.deepLink)).apply {
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    },
                                )
                            } catch (_: Exception) {
                                showQr = true
                            }
                        },
                    ) {
                        Text("Set API key")
                    }
                    TrackButton(
                        modifier = Modifier.defaultMinSize(minWidth = 72.dp),
                        onClick = { showQr = true },
                    ) {
                        Text("QR")
                    }
                }
            }
            TrackButton(
                onClick = {
                    status = "Translating to Persian…"
                    VideoPlayerObject.videoPlayerControls?.translateSubtitleToPersian { result ->
                        result.fold(
                            onSuccess = { r ->
                                if (r.ok) onDismissRequest()
                                else if (r.errorCode == "missing_key") {
                                    status = "Key not saved yet — scan QR or open the bot, then retry"
                                    VideoPlayerObject.videoPlayerControls?.sushiAiKeySetup {
                                        it.onSuccess { s -> setup = s }
                                    }
                                } else {
                                    status = r.errorCode ?: "Could not translate"
                                }
                            },
                            onFailure = { status = it.message },
                        )
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Retry")
            }
        }
    }
}

/** Blocks the player until Automatic / AI translate finishes. Not swipe-dismissible. */
@Composable
fun SushiSubtitleBusyOverlay(message: String) {
    Dialog(
        onDismissRequest = {},
        properties = DialogProperties(
            dismissOnBackPress = false,
            dismissOnClickOutside = false,
            usePlatformDefaultWidth = false,
        ),
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.82f)),
            contentAlignment = Alignment.Center,
        ) {
            Column(
                modifier = Modifier
                    .background(Color.Black.copy(alpha = 0.92f), RoundedCornerShape(16.dp))
                    .padding(horizontal = 28.dp, vertical = 24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                CircularProgressIndicator()
                Text(text = message, color = Color.White)
            }
        }
    }
}

private fun qrBitmap(text: String, size: Int = 512): Bitmap? {
    return try {
        val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size)
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.RGB_565)
        for (x in 0 until size) {
            for (y in 0 until size) {
                bmp.setPixel(x, y, if (matrix[x, y]) android.graphics.Color.BLACK else android.graphics.Color.WHITE)
            }
        }
        bmp
    } catch (e: Exception) {
        Log.e("SushiSubtitles", "QR encode failed", e)
        null
    }
}
