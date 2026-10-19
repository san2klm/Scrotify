// Standalone JVM regression probe; compile together with PcmWaveformBinner.kt.
// No Android runtime or new test dependencies required.
package cloud.templo.crotowave

import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.sqrt

private fun sample(buffer: ByteBuffer, encoding: Int, value: Double) {
    when (encoding) {
        PcmEncoding.PCM_8BIT -> buffer.put((value * 128 + 128).roundToInt().coerceIn(0, 255).toByte())
        PcmEncoding.PCM_16BIT -> buffer.putShort((value * 32768).roundToInt().toShort())
        PcmEncoding.PCM_FLOAT -> buffer.putFloat(value.toFloat())
        PcmEncoding.PCM_32BIT -> buffer.putInt((value * 2147483648.0).toLong().toInt())
        PcmEncoding.PCM_24BIT_PACKED -> {
            val n = (value * 8388608).roundToInt()
            buffer.put(n.toByte()).put((n shr 8).toByte()).put((n shr 16).toByte())
        }
        else -> error("unsupported fixture encoding")
    }
}

private fun block(encoding: Int, values: List<Pair<Double, Double>>): ByteBuffer {
    val bytes = values.size * 2 * PcmEncoding.bytesPerSample(encoding)
    val buffer = ByteBuffer.allocate(bytes + 17).order(ByteOrder.nativeOrder())
    buffer.position(7) // Nonzero BufferInfo offset; trailing bytes are excluded.
    for ((left, right) in values) {
        sample(buffer, encoding, left)
        sample(buffer, encoding, right)
    }
    buffer.limit(7 + bytes)
    buffer.position(7)
    return buffer
}

fun main() {
    var checks = 0
    for (encoding in listOf(PcmEncoding.PCM_8BIT, PcmEncoding.PCM_16BIT,
                           PcmEncoding.PCM_FLOAT, PcmEncoding.PCM_24BIT_PACKED,
                           PcmEncoding.PCM_32BIT)) {
        val levels = List(64) { i ->
            val value = if (i < 32) (if (i % 2 == 0) 0.2 else 0.8) else 0.3
            value to value
        }
        val whole = PcmWaveformBinner(16, 64_000)
        whole.consume(block(encoding, levels), encoding, 2, 1000)
        val actual = whole.finish()
        val reference = 0.3 / (0.75 * sqrt((0.2 * 0.2 + 0.8 * 0.8) / 2) + 0.25 * 0.8)
        check(actual.size == 16 && actual.all { it.isFinite() && it in 0.0..1.0 })
        check(actual.take(8).all { abs(it - 1.0) < 1e-6 })
        check(actual.drop(8).all { abs(it - reference) < 0.02 }) { "RMS/peak mismatch, encoding=$encoding" }
        checks++

        val split = PcmWaveformBinner(16, 64_000)
        split.consume(block(encoding, levels.take(19)), encoding, 2, 1000)
        split.consume(block(encoding, levels.drop(19)), encoding, 2, 1000)
        check(split.finish().zip(actual).all { (a, b) -> abs(a - b) < 1e-9 }) { "chunk boundary changed waveform" }
        checks++

        val silence = PcmWaveformBinner(16, 64_000)
        silence.consume(block(encoding, List(64) { 0.0 to 0.0 }), encoding, 2, 1000)
        check(silence.finish().all { it == 0.0 }) { "digital silence amplified" }
        checks++

        val antiPhase = PcmWaveformBinner(16, 64_000)
        antiPhase.consume(block(encoding, List(64) { 0.5 to -0.5 }), encoding, 2, 1000)
        check(antiPhase.finish().all { it == 0.0 }) { "channel averaging differs from Dart" }
        checks++
    }
    println("PCM_BINNER_SMOKE_PASS checks=$checks encodings=5")
}
