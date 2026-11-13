package app.sora

import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.lifecycle.lifecycleScope
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import com.nuvio.engine.NuvioEngine
import com.nuvio.engine.NuvioEngineConfig
import com.nuvio.engine.NuvioTorrentFile
import java.io.File
import kotlinx.coroutines.launch

/**
 * Sora — Android shell around nuvio-engine.
 *
 * Flow: magnet -> NuvioEngine.addMagnet -> files -> prepareStream ->
 * loopback URL http://127.0.0.1:<port>/stream/<id> -> ExoPlayer.
 *
 * Sora is a player. It ships no catalogue and no addons: the only input is a
 * magnet link or a media URL the user already owns or is licensed to watch.
 *
 * TODO(cursor): see docs/ROADMAP.md — file picker, resume, ASS subtitles via
 * nuvio-libass, and a proper player UI (Media3 session + controller).
 */
class MainActivity : ComponentActivity() {

    private lateinit var player: ExoPlayer
    private lateinit var status: TextView
    private lateinit var playButton: Button
    private var engine: NuvioEngine? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        status = findViewById(R.id.status)
        playButton = findViewById(R.id.play)
        val input = findViewById<EditText>(R.id.input)

        player = ExoPlayer.Builder(this).build()
        findViewById<PlayerView>(R.id.player).player = player

        playButton.setOnClickListener {
            val text = input.text.toString().trim()
            if (text.isEmpty()) {
                status.text = getString(R.string.status_need_input)
                return@setOnClickListener
            }
            playButton.isEnabled = false
            lifecycleScope.launch {
                try {
                    play(text)
                } catch (error: Throwable) {
                    status.text = getString(
                        R.string.status_failed,
                        error.message ?: error.javaClass.simpleName,
                    )
                    playButton.isEnabled = true
                }
            }
        }
    }

    private suspend fun play(input: String) {
        if (input.startsWith("magnet:", ignoreCase = true)) {
            status.setText(R.string.status_fetching_metadata)
            val engine = engine ?: createEngine().also { engine = it }

            val torrentId = engine.addMagnet(input)
            status.setText(R.string.status_picking_file)
            val file = pickVideoFile(engine.files(torrentId))

            status.text = getString(R.string.status_preparing, file.path)
            val stream = engine.prepareStream(torrentId, file.index, file.path)
            status.text = getString(R.string.status_playing, file.path)
            start(stream.url)
        } else {
            status.setText(R.string.status_direct_url)
            start(input)
        }
    }

    private fun createEngine(): NuvioEngine {
        val data = File(filesDir, "nuvio-engine").apply { mkdirs() }
        val cache = File(cacheDir, "nuvio-engine").apply { mkdirs() }
        status.text = getString(R.string.status_starting_engine, NuvioEngine.version)
        return NuvioEngine.create(
            NuvioEngineConfig(
                dataDirectory = data,
                cacheDirectory = cache,
            ),
        )
    }

    private fun pickVideoFile(files: List<NuvioTorrentFile>): NuvioTorrentFile {
        val candidates = files.filter { it.size > 0 }
        require(candidates.isNotEmpty()) { "torrent contains no files" }
        val video = candidates.filter { hasVideoExtension(it.path) }
        return (video.ifEmpty { candidates }).maxBy { it.size }
    }

    private fun hasVideoExtension(path: String): Boolean {
        val name = path.substringAfterLast('/').lowercase()
        return VIDEO_EXTENSIONS.any { name.endsWith(it) }
    }

    private fun start(url: String) {
        player.setMediaItem(MediaItem.fromUri(url))
        player.prepare()
        player.playWhenReady = true
        playButton.isEnabled = true
    }

    override fun onStop() {
        player.pause()
        super.onStop()
    }

    override fun onDestroy() {
        player.release()
        engine?.let { runCatching { it.close() } }
        engine = null
        super.onDestroy()
    }

    private companion object {
        val VIDEO_EXTENSIONS = listOf(".mp4", ".mkv", ".webm", ".m4v", ".mov", ".avi", ".ts")
    }
}
