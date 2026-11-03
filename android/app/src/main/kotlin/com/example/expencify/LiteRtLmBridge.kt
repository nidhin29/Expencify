package com.example.expencify

import android.app.Activity
import android.util.Log
import com.google.ai.edge.litertlm.*
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/** Owns one engine; every request gets a fresh native conversation.
 * Cancellation never closes a conversation until native completion is acknowledged.
 */
class LiteRtLmBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val debug = activity.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0
    private val channel = MethodChannel(messenger, "com.nidhi.expencify/litert_lm")
    private val worker = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean(false)
    private val cancelled = AtomicBoolean(false)
    private val disposed = AtomicBoolean(false)
    @Volatile private var active: Conversation? = null
    private var engine: Engine? = null
    private var modelPath: String? = null
    private var contextTokens = 2048
    private var backend = "CPU"

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "capabilities" -> result.success(mapOf(
                    "supported" to (android.os.Process.is64Bit() &&
                        android.os.Build.SUPPORTED_ABIS.any { it == "arm64-v8a" || it == "x86_64" }),
                    "runtime" to "0.19.0",
                ))
                "cancel" -> { cancel(); result.success(null) }
                "initialize", "converse" -> {
                    if (disposed.get() || !busy.compareAndSet(false, true)) {
                        result.error("MODEL_BUSY", "AI is still finishing a request.", null)
                    } else {
                        cancelled.set(false)
                        worker.execute {
                            var value: Any? = null
                            var failed: Throwable? = null
                            try {
                                value = if (call.method == "initialize") initialize(call) else converse(call)
                            } catch (failure: Throwable) {
                                failed = failure
                                if (debug) Log.e("SpendyLiteRT", "${call.method} failed", failure)
                            } finally {
                                // Native work and cleanup have ended before Dart may start another call.
                                busy.set(false)
                                val failure = failed
                                val code = when (failure) {
                                    is OutputLimit -> "OUTPUT_LIMIT"
                                    is java.util.concurrent.CancellationException -> "MODEL_CANCELLED"
                                    is IllegalArgumentException -> "INVALID_REQUEST"
                                    else -> "MODEL_RUNTIME_FAILED"
                                }
                                activity.runOnUiThread {
                                    if (failure == null) result.success(value)
                                    else result.error(code, "Offline AI could not complete the operation.",
                                        mapOf("type" to failure.javaClass.simpleName, "backend" to backend))
                                }
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun checkCancellation() {
        if (cancelled.get() || disposed.get()) throw java.util.concurrent.CancellationException()
    }

    private fun closeEngine() {
        engine?.let { if (it.isInitialized()) it.close() }
        engine = null
    }

    private fun createEngine(gpu: Boolean) {
        checkCancellation()
        val cache = File(activity.cacheDir, "litertlm-0.19.0-default").apply { mkdirs() }
        val candidate = Engine(EngineConfig(
            modelPath = requireNotNull(modelPath),
            backend = if (gpu) Backend.GPU() else Backend.CPU(threadCount = 4),
            maxNumTokens = contextTokens,
            cacheDir = cache.path,
        ))
        try {
            candidate.initialize()
            engine = candidate
            backend = if (gpu) "GPU" else "CPU"
            checkCancellation()
        } catch (failure: Throwable) {
            if (candidate.isInitialized()) candidate.close()
            engine = null
            throw failure
        }
    }

    private fun initialize(call: MethodCall): Map<String, Any> {
        val input = File(requireNotNull(call.argument<String>("path"))).canonicalFile
        val root = File(activity.applicationInfo.dataDir).canonicalPath + File.separator
        require(input.path.startsWith(root) && input.isFile)
        require(input.length() == call.argument<Number>("expectedSize")?.toLong())
        require(input.extension == "litertlm")
        contextTokens = requireNotNull(call.argument<Int>("contextTokens"))
        require(contextTokens in 1024..4096)
        Engine.setNativeMinLogSeverity(LogSeverity.ERROR)
        closeEngine()
        modelPath = input.path
        if (call.argument<Boolean>("preferCpu") == true) {
            createEngine(gpu = false)
            return mapOf("backend" to backend, "runtime" to "0.19.0")
        }
        try { createEngine(gpu = true) }
        catch (failure: Exception) {
            checkCancellation()
            if (debug) Log.w("SpendyLiteRT", "GPU initialization unavailable; using CPU", failure)
            createEngine(gpu = false)
        }
        return mapOf("backend" to backend, "runtime" to "0.19.0")
    }

    private class OutputLimit : Exception()

    @OptIn(ExperimentalApi::class)
    private fun converse(call: MethodCall): Map<String, Any> {
        checkCancellation()
        val started = android.os.SystemClock.elapsedRealtime()
        val instructions = requireNotNull(call.argument<String>("instructions"))
        val user = requireNotNull(call.argument<String>("user"))
        val turns = call.argument<List<Map<String, String>>>("history") ?: emptyList()
        require(turns.size <= 12)
        require(instructions.length + user.length + turns.sumOf { it["text"]?.length ?: 0 } <= 14000)
        val history = turns.map { turn ->
            when (turn["role"]) {
                "user" -> Message.user(requireNotNull(turn["text"]))
                "assistant" -> Message.model(requireNotNull(turn["text"]))
                else -> throw IllegalArgumentException("Invalid conversation role")
            }
        }
        require(history.size % 2 == 0)
        require(turns.withIndex().all { (i, t) -> t["role"] == if (i % 2 == 0) "user" else "assistant" })
        val choices = call.argument<List<String>>("choices") ?: emptyList()
        require(choices.size <= 64 && choices.all { it.matches(Regex("[a-z_]{1,64}")) })
        val schema = call.argument<Map<String, Any?>>("schema")
        require(schema == null || (choices.isEmpty() && schema.toString().length <= 16000))
        val limit = requireNotNull(call.argument<Int>("maxOutputChars"))
        require(limit in 32..3000)
        val maxTokens = requireNotNull(call.argument<Int>("maxOutputTokens"))
        require(maxTokens in 16..512)
        val prose = call.argument<Boolean>("response") == true
        // Synthetic harness only. Never expose rendered user prompts in normal app metrics.
        val testRendering = mutableMapOf<String, String>()
        var fellBack = false
        fun generate(): Pair<String, Int> {
            checkCancellation()
            val conversation = requireNotNull(engine).createConversation(ConversationConfig(
                systemInstruction = Contents.of(instructions),
                initialMessages = history,
                automaticToolCalling = false,
                samplerConfig = SamplerConfig(topK = if (prose) 20 else 1,
                    topP = if (prose) 0.8 else 1.0, temperature = if (prose) 0.3 else 0.0),
                extraContext = mapOf("enable_thinking" to false),
                thinkingConfig = ThinkingConfig(enableThinking = false, thinkingTokenBudget = 0),
                maxOutputToken = maxTokens,
                enableResponseFormat = choices.isNotEmpty() || schema != null,
            ))
            active = conversation
            try {
                if (debug && activity.packageName == "com.nidhi.expencify.modelcheck") {
                    testRendering["testPreface"] = conversation.renderPrefaceIntoString()
                    testRendering["testUser"] = conversation.renderMessageIntoString(Message.user(user))
                }
                checkCancellation()
                val done = CountDownLatch(1)
                val output = StringBuilder()
                val failure = AtomicReference<Throwable?>(null)
                conversation.sendMessageAsync(Message.user(user), object : MessageCallback {
                    override fun onMessage(message: Message) {
                        if (message.toolCalls.isNotEmpty() || message.channels.values.any { it.isNotEmpty() }) {
                            failure.compareAndSet(null, IllegalStateException("Unexpected output channel"))
                        } else if (failure.get() == null) {
                            val text = message.contents.contents.filterIsInstance<Content.Text>().joinToString("") { it.text }
                            if (output.length + text.length > limit) failure.compareAndSet(null, OutputLimit())
                            else output.append(text)
                        }
                        if (failure.get() != null || cancelled.get()) {
                            try { conversation.cancelProcess() } catch (_: Exception) { /* Await completion. */ }
                        }
                    }
                    override fun onDone() { done.countDown() }
                    override fun onError(throwable: Throwable) {
                        failure.compareAndSet(null, throwable); done.countDown()
                    }
                }, responseFormat = when {
                    schema != null -> ResponseFormat.json(schema)
                    choices.isNotEmpty() -> ResponseFormat.regex("(?:${choices.joinToString("|")})")
                    else -> null
                })
                // Outer Dart deadline calls cancel. Keep ownership until native acknowledges it.
                done.await()
                checkCancellation()
                failure.get()?.let { throw it }
                return output.toString().trim() to runCatching { conversation.getTokenCount() }.getOrDefault(-1)
            } finally {
                active = null
                conversation.close()
            }
        }
        val generated = try { generate() }
        catch (failure: Exception) {
            checkCancellation()
            if (backend != "GPU" || failure is OutputLimit || failure is IllegalArgumentException) throw failure
            closeEngine(); createEngine(gpu = false); fellBack = true
            generate()
        }
        return mapOf("text" to generated.first, "backend" to backend, "tokens" to generated.second,
             "gpuFallback" to fellBack, "elapsedMs" to (android.os.SystemClock.elapsedRealtime() - started)) + testRendering
    }

    private fun cancel() {
        cancelled.set(true)
        try { active?.cancelProcess() } catch (_: Exception) { /* Native completion still owns cleanup. */ }
    }

    fun dispose() {
        disposed.set(true); channel.setMethodCallHandler(null); cancel()
        worker.execute { closeEngine() }
        worker.shutdown()
    }
}
