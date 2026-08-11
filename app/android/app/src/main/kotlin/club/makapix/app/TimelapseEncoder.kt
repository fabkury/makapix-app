package club.makapix.app

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.media.MediaMuxer
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The Timelapse export's MediaCodec host (ADR 0004): the "club.makapix.app/timelapse"
 * MethodChannel receives tightly-packed I420 frames with explicit presentation timestamps
 * from the Dart export isolate and hardware-encodes a silent H.264 MP4 via MediaMuxer.
 *
 * Threading: every channel call runs its work on one dedicated single-thread executor, so
 * the platform main thread never blocks on the encoder and frames stay strictly ordered.
 * Dart awaits each `feed` (at most one frame in flight — the backpressure). PTS is
 * caller-provided and variable (the finale carries the animation's authored durations);
 * the muxer derives durations from PTS deltas.
 */
class TimelapseEncoder {
    private var codec: MediaCodec? = null
    private var muxer: MediaMuxer? = null
    private var trackIndex = -1
    private var muxerStarted = false
    private var outputPath: String? = null
    private var executor: ExecutorService? = null
    private val bufferInfo = MediaCodec.BufferInfo()

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        // Lazily created per export, torn down on finish/abort; calls are serialized.
        val exec = executor ?: Executors.newSingleThreadExecutor().also { executor = it }
        exec.execute {
            try {
                when (call.method) {
                    "start" -> {
                        start(
                            call.argument<Int>("width")!!,
                            call.argument<Int>("height")!!,
                            call.argument<Int>("fps")!!,
                            call.argument<Int>("bitrateBps")!!,
                            call.argument<String>("path")!!,
                        )
                        result.success(null)
                    }
                    "feed" -> {
                        feed(call.argument<ByteArray>("bytes")!!, call.argument<Number>("ptsUs")!!.toLong())
                        result.success(null)
                    }
                    "finish" -> {
                        val path = finish()
                        result.success(path)
                    }
                    "abort" -> {
                        release(deleteOutput = true)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                release(deleteOutput = true)
                result.error("ENCODE_FAILED", "${call.method}: ${e.message}", null)
            }
        }
    }

    private fun start(width: Int, height: Int, fps: Int, bitrateBps: Int, path: String) {
        release(deleteOutput = false) // a stale unfinished export never blocks a new one
        require(width % 2 == 0 && height % 2 == 0) { "even dimensions required" }
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(
                MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible,
            )
            setInteger(MediaFormat.KEY_BIT_RATE, bitrateBps)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps) // a hint; real timing is per-frame PTS
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        // Surface unsupported sizes as a clean error instead of a codec configure crash.
        val codecName = MediaCodecList(MediaCodecList.REGULAR_CODECS).findEncoderForFormat(format)
            ?: throw IllegalStateException("no H.264 encoder for ${width}x$height")
        codec = MediaCodec.createByCodecName(codecName).apply {
            configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            start()
        }
        muxer = MediaMuxer(path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        outputPath = path
        trackIndex = -1
        muxerStarted = false
    }

    private fun feed(i420: ByteArray, ptsUs: Long) {
        val codec = this.codec ?: throw IllegalStateException("start was not called")
        val inIndex = codec.dequeueInputBuffer(BUFFER_TIMEOUT_US)
        if (inIndex < 0) throw IllegalStateException("encoder input stalled")
        // COLOR_FormatYUV420Flexible: copy the tightly-packed planes honoring the codec's
        // actual row/pixel strides (the classic vendor-variance hazard).
        val image = codec.getInputImage(inIndex) ?: throw IllegalStateException("no input image")
        val w = image.cropRect.width()
        val h = image.cropRect.height()
        require(i420.size == w * h * 3 / 2) { "frame size ${i420.size} != ${w * h * 3 / 2}" }
        var src = 0
        for (p in 0 until 3) {
            val plane = image.planes[p]
            val pw = if (p == 0) w else w / 2
            val ph = if (p == 0) h else h / 2
            val buf: ByteBuffer = plane.buffer
            val rowStride = plane.rowStride
            val pixStride = plane.pixelStride
            for (row in 0 until ph) {
                if (pixStride == 1) {
                    buf.position(row * rowStride)
                    buf.put(i420, src, pw)
                    src += pw
                } else {
                    for (col in 0 until pw) {
                        buf.position(row * rowStride + col * pixStride)
                        buf.put(i420[src++])
                    }
                }
            }
        }
        codec.queueInputBuffer(inIndex, 0, w * h * 3 / 2, ptsUs, 0)
        drain(endOfStream = false)
    }

    private fun finish(): String {
        val codec = this.codec ?: throw IllegalStateException("start was not called")
        val inIndex = codec.dequeueInputBuffer(BUFFER_TIMEOUT_US)
        if (inIndex >= 0) {
            codec.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
        }
        drain(endOfStream = true)
        val path = outputPath ?: ""
        release(deleteOutput = false)
        return path
    }

    private fun drain(endOfStream: Boolean) {
        val codec = this.codec ?: return
        while (true) {
            val outIndex = codec.dequeueOutputBuffer(bufferInfo, if (endOfStream) BUFFER_TIMEOUT_US else 0L)
            when {
                outIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> if (endOfStream) continue else return
                outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    val muxer = this.muxer ?: throw IllegalStateException("muxer gone")
                    trackIndex = muxer.addTrack(codec.outputFormat)
                    muxer.start()
                    muxerStarted = true
                }
                outIndex >= 0 -> {
                    val encoded = codec.getOutputBuffer(outIndex) ?: throw IllegalStateException("no output buffer")
                    if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                        bufferInfo.size = 0 // csd is carried inside the muxer's track format
                    }
                    if (bufferInfo.size > 0 && muxerStarted) {
                        encoded.position(bufferInfo.offset)
                        encoded.limit(bufferInfo.offset + bufferInfo.size)
                        muxer!!.writeSampleData(trackIndex, encoded, bufferInfo)
                    }
                    codec.releaseOutputBuffer(outIndex, false)
                    if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                }
            }
        }
    }

    private fun release(deleteOutput: Boolean) {
        try {
            codec?.stop()
        } catch (_: Exception) {}
        try {
            codec?.release()
        } catch (_: Exception) {}
        codec = null
        try {
            if (muxerStarted) muxer?.stop()
        } catch (_: Exception) {}
        try {
            muxer?.release()
        } catch (_: Exception) {}
        muxer = null
        muxerStarted = false
        trackIndex = -1
        if (deleteOutput) {
            outputPath?.let { runCatching { File(it).delete() } }
        }
        outputPath = null
    }

    companion object {
        private const val BUFFER_TIMEOUT_US = 10_000L
    }
}
