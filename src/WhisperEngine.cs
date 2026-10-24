using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using UnityEngine;
using Whisper;

namespace CryptmasterWhisper
{
    /// <summary>
    /// Runs Whisper: a current whisper.cpp shipped with the mod (NativeBackend: Vulkan GPU, or CUDA when the
    /// installer added it), or, as the fallback, the game's own libwhisper through its own whisper.unity
    /// binding. What changes from the binding's
    /// defaults (and, we think, part of why the original integration was dropped): the encoder window is sized
    /// to the utterance instead of Whisper's fixed 30 s (measured on a 4-core i5-6600K with the game's tiny
    /// models: ~860 ms per call at 30 s, ~100 ms at 256 = 5 s), output is limited to one short segment without
    /// timestamps, and the vocabulary prompt is passed as UTF-8 (the binding marshals it as ANSI, which breaks
    /// accented words).
    /// </summary>
    internal static class WhisperEngine
    {
        private static readonly Dictionary<string, WhisperWrapper> Models = new(StringComparer.OrdinalIgnoreCase);
        private static readonly object Lock = new();
        private static IntPtr _promptPtr = IntPtr.Zero;
        // A command is a word or a few: more tokens than this is Whisper repeating itself.
        private const int MaxTokens = 12;

        internal static string SystemInfo()
        {
            try
            {
                return "Whisper: " + WhisperWrapper.GetSystemInfo();
            }
            catch (Exception e)
            {
                return "Whisper library unavailable: " + e.Message;
            }
        }

        /// <summary>True when recognition runs on a GPU (a native backend that found one).</summary>
        internal static bool OnGpu
        {
            get
            {
                lock (Lock)
                {
                    ChooseBackend();
                    return _native != null && _native.UseGpu && _native.GpuName != "";
                }
            }
        }

        /// <summary>
        /// Model.PerLanguage (by game language code) first; then, on the CPU, Model.EnglishCpu/MultilingualCpu
        /// (the installer's benchmark may pick a smaller model for the CPU than for the GPU); then Model.English
        /// or Model.Multilingual.
        /// </summary>
        internal static string ModelFor(string gameLanguage, string whisperLanguage)
        {
            foreach (string pair in Plugin.ModelPerLanguage.Value.Split(';'))
            {
                string[] kv = pair.Split('=');
                if (kv.Length == 2 && string.Equals(kv[0].Trim(), gameLanguage, StringComparison.OrdinalIgnoreCase) && kv[1].Trim() != "")
                {
                    return kv[1].Trim();
                }
            }
            bool english = whisperLanguage == "en";
            if (!OnGpu)
            {
                string cpu = (english ? Plugin.ModelEnglishCpu.Value : Plugin.ModelMultilingualCpu.Value).Trim();
                if (cpu != "")
                {
                    return cpu;
                }
            }
            return english ? Plugin.ModelEnglish.Value : Plugin.ModelMultilingual.Value;
        }

        internal static string ResolveModel(string name)
        {
            foreach (string candidate in new[]
            {
                name,
                Path.Combine(Plugin.Folder, "models", name),
                Path.Combine(Application.streamingAssetsPath, "Whisper", name),
            })
            {
                if (Path.IsPathRooted(candidate) && File.Exists(candidate))
                {
                    return candidate;
                }
            }
            return null;
        }

        // ---- Backend: a current whisper.cpp shipped with the mod (native\vulkan or native\cuda), or the game's own ----

        private static bool _backendChosen;
        private static NativeBackend _native;
        private static readonly Dictionary<string, IntPtr> NativeModels = new(StringComparer.OrdinalIgnoreCase);

        /// <summary>Performance.Backend: Auto (Vulkan build if installed, else the game's library), Vulkan, CUDA, CPU (the shipped build without GPU) or Game.</summary>
        private static void ChooseBackend()
        {
            if (_backendChosen)
            {
                return;
            }
            _backendChosen = true;
            string choice = Plugin.Backend.Value;
            // Auto: CUDA only if it's installed and measured more than 10% faster than Vulkan on this PC.
            if (choice == Plugin.BackendAuto && NativeBackend.IsInstalled("cuda")
                && Plugin.CudaGpuMs.Value > 0 && Plugin.VulkanGpuMs.Value > 0 && Plugin.CudaGpuMs.Value * 10 < Plugin.VulkanGpuMs.Value * 9)
            {
                choice = Plugin.BackendCuda;
            }
            // whisper.cpp ended the last session (a GPU driver reset, a CUDA error...): that backend is skipped for
            // this session only, one step down (CUDA -> Vulkan -> CPU -> the game's library), so a broken GPU
            // can't end every launch. The chosen setting itself stays.
            string crashed = NativeBackend.TakeCrashReport();
            string planned = choice == Plugin.BackendCuda ? "cuda" : choice == Plugin.BackendCpu ? "vulkan-cpu" : choice == Plugin.BackendGame ? null : "vulkan";
            if (crashed != null && (crashed == planned || (crashed == "cuda-cpu" && planned == "vulkan-cpu")))
            {
                choice = planned == "cuda" ? Plugin.BackendVulkan : planned == "vulkan" ? Plugin.BackendCpu : Plugin.BackendGame;
                Plugin.Log.LogWarning($"Whisper: {crashed} ended the last session, so this session uses {choice} instead (once; Performance.Backend is unchanged).");
            }
            _native = choice switch
            {
                Plugin.BackendCuda => NativeBackend.TryLoad("cuda", true) ?? NativeBackend.TryLoad("vulkan", true),
                Plugin.BackendVulkan or Plugin.BackendAuto => NativeBackend.TryLoad("vulkan", true),
                Plugin.BackendCpu => NativeBackend.TryLoad("vulkan", false),
                _ => null,
            };
            if (_native == null)
            {
                Plugin.Log.LogInfo($"Whisper: using the game's own whisper library (CPU){(choice == Plugin.BackendGame ? "" : "; no usable native\\ build for " + choice)}.");
            }
        }

        /// <summary>
        /// After Performance.Backend changed in the menu: switches now if possible (nothing loaded yet, or
        /// GPU/CPU within the same build); returns true if it only applies after restarting the game. The
        /// Vulkan and CUDA builds both ship whisper.dll and ggml.dll, and Windows reuses an already-loaded
        /// DLL by name, so once one of them is loaded the other can't be.
        /// </summary>
        internal static bool BackendChanged()
        {
            lock (Lock)
            {
                if (_native == null && !_backendChosen)
                {
                    return false; // nothing loaded yet: the next session picks it up
                }
                string loaded = _native?.Variant;
                string wanted = Plugin.Backend.Value == Plugin.BackendCuda ? "cuda" : Plugin.Backend.Value == Plugin.BackendGame ? null : "vulkan";
                if (Plugin.Backend.Value == Plugin.BackendAuto && NativeBackend.IsInstalled("cuda")
                    && Plugin.CudaGpuMs.Value > 0 && Plugin.VulkanGpuMs.Value > 0 && Plugin.CudaGpuMs.Value * 10 < Plugin.VulkanGpuMs.Value * 9)
                {
                    wanted = "cuda";
                }
                if (loaded != null && wanted != null && loaded != wanted)
                {
                    return true;
                }
                // Same build (or the game's library): reload with the new GPU/CPU choice.
                FreeNativeModels();
                _native = null;
                _backendChosen = false;
                _nativeErrors = 0;
                return false;
            }
        }

        private static void FreeNativeModels()
        {
            foreach (IntPtr ctx in NativeModels.Values)
            {
                if (ctx != IntPtr.Zero)
                {
                    _native?.FreeModel(ctx);
                }
            }
            NativeModels.Clear();
        }

        private static int _nativeErrors;
        private const int ErrorsBeforeCpu = 3;

        /// <summary>
        /// After several whisper.cpp errors in a row (a GPU in trouble), the rest of the session runs on the CPU:
        /// the same build if it was on the GPU (no DLLs to swap; both builds carry the CPU code), else the game's
        /// own library. Call under Lock.
        /// </summary>
        private static void DropToCpu()
        {
            string from = BackendName;
            FreeNativeModels();
            _native = _native != null && _native.UseGpu ? NativeBackend.TryLoad(_native.Variant, false) : null;
            _nativeErrors = 0;
            Plugin.Log.LogWarning($"Whisper: {ErrorsBeforeCpu} errors in a row on {from}; this session now uses {BackendName} (back to normal after restarting the game).");
        }

        internal static string BackendName => _native == null ? "game" : _native.Variant + (_native.UseGpu ? "" : "-cpu");

        // ---- Silero voice activity detection ----

        private static IntPtr _vad;
        private static NativeBackend _vadOwner; // the backend whose DLL holds it (stays loaded)
        private static bool _vadTried;
        private static readonly object VadLock = new();

        /// <summary>
        /// The Silero VAD (vad\ggml-silero-*.bin, through the native backend), loaded once; Zero when it isn't
        /// available (the game's own library, an old shim, the file missing, or Listening.SpeechDetector =
        /// Energy). It runs on the CPU and has its own context, so it can run while a recognition is going.
        /// </summary>
        internal static IntPtr Vad
        {
            get
            {
                lock (VadLock)
                {
                    if (_vadTried)
                    {
                        return _vad;
                    }
                    _vadTried = true;
                    if (Plugin.SpeechDetector.Value != Plugin.DetectorSilero)
                    {
                        return _vad;
                    }
                    lock (Lock)
                    {
                        ChooseBackend();
                    }
                    string folder = Path.Combine(Plugin.Folder, "vad");
                    string model = Directory.Exists(folder) ? Directory.GetFiles(folder, "ggml-silero-*.bin").OrderByDescending(f => f).FirstOrDefault() : null;
                    if (_native == null || !_native.HasVad || model == null)
                    {
                        Plugin.Log.LogInfo("Whisper: Silero speech detection not available; detecting speech by loudness.");
                        return _vad;
                    }
                    _vad = _native.LoadVad(model);
                    _vadOwner = _native;
                    Plugin.Log.LogInfo(_vad != IntPtr.Zero ? $"Whisper: Silero speech detection loaded ({Path.GetFileName(model)})." : "Whisper: Silero speech detection could not be loaded; detecting speech by loudness.");
                    return _vad;
                }
            }
        }

        internal static float VadProbability(float[] samples16k)
        {
            IntPtr vad = Vad;
            return vad == IntPtr.Zero ? -1f : _vadOwner.VadProbability(vad, samples16k);
        }

        internal static void VadReset()
        {
            if (_vad != IntPtr.Zero)
            {
                _vadOwner.VadReset(_vad);
            }
        }

        /// <summary>Folds a real final-result time into the measured time of the backend in use (shown in the menu).</summary>
        internal static void RecordLatency(long inferenceMs)
        {
            BepInEx.Configuration.ConfigEntry<int> entry = _native == null ? null
                : !OnGpu ? Plugin.CpuMs
                : _native.Variant == "cuda" ? Plugin.CudaGpuMs : Plugin.VulkanGpuMs;
            if (entry == null || inferenceMs <= 0)
            {
                return;
            }
            entry.Value = entry.Value <= 0 ? (int)inferenceMs : (int)((entry.Value * 3 + inferenceMs) / 4);
        }

        /// <summary>Loads a model (once); call from a worker thread. Returns false if it can't be loaded.</summary>
        internal static bool Get(string modelName)
        {
            lock (Lock)
            {
                ChooseBackend();
                if (_native != null)
                {
                    if (NativeModels.TryGetValue(modelName, out IntPtr ctx))
                    {
                        return ctx != IntPtr.Zero;
                    }
                    string nativePath = ResolveModel(modelName);
                    var watch = Stopwatch.StartNew();
                    ctx = nativePath == null ? IntPtr.Zero : _native.LoadModel(nativePath);
                    NativeModels[modelName] = ctx;
                    if (ctx != IntPtr.Zero)
                    {
                        Plugin.Log.LogInfo($"Whisper model {Path.GetFileName(nativePath)} loaded in {watch.ElapsedMilliseconds} ms ({BackendName}).");
                        return true;
                    }
                    Plugin.Log.LogWarning($"Whisper: model '{modelName}' could not be loaded by native\\{_native.Variant}; falling back to the game's library and the CPU models.");
                    _native = null;
                    return false; // the caller picks the CPU model next time
                }
                if (Models.TryGetValue(modelName, out WhisperWrapper loaded))
                {
                    return loaded != null;
                }
                string path = ResolveModel(modelName);
                if (path == null)
                {
                    Plugin.Log.LogError($"Whisper model '{modelName}' not found (models folder or StreamingAssets\\Whisper).");
                    Models[modelName] = null;
                    return false;
                }
                var sw = Stopwatch.StartNew();
                WhisperWrapper wrapper = WhisperWrapper.InitFromFile(path);
                Plugin.Log.LogInfo($"Whisper model {Path.GetFileName(path)} loaded in {sw.ElapsedMilliseconds} ms (game library; multilingual: {wrapper?.IsMultilingual}).");
                Models[modelName] = wrapper;
                return wrapper != null;
            }
        }

        private static float[] To16k(float[] samples, int frequency)
        {
            if (frequency == 16000)
            {
                return samples;
            }
            int n = (int)((long)samples.Length * 16000 / frequency);
            var output = new float[n];
            for (int i = 0; i < n; i++)
            {
                double position = (double)i * frequency / 16000;
                int a = (int)position;
                int b = Math.Min(a + 1, samples.Length - 1);
                output[i] = (float)(samples[a] + (samples[b] - samples[a]) * (position - a));
            }
            return output;
        }

        internal sealed class Result
        {
            public string Text;
            public long InferenceMs;
            public float AudioSeconds;
            public bool IsFinal;
            public float NoSpeech; // whisper.cpp's no-speech probability (native backends only)
        }

        /// <summary>Transcribes one utterance; blocking, call from a worker thread.</summary>
        internal static unsafe Result Transcribe(float[] samples, int frequency, string gameLanguage, string language, string prompt, bool isFinal)
        {
            // Chosen per call: if the GPU fails, the next attempt uses the CPU model.
            string model = ModelFor(gameLanguage, language);
            if (!Get(model))
            {
                model = ModelFor(gameLanguage, language);
                if (!Get(model))
                {
                    return null;
                }
            }
            float seconds = samples.Length / (float)frequency;
            int threads = Plugin.Threads.Value > 0 ? Plugin.Threads.Value : Mathf.Clamp(Environment.ProcessorCount - 1, 1, 4);
            // 50 encoder frames per second of audio, plus margin; never more than Whisper's 30 s window.
            int audioCtx = Mathf.Clamp(Mathf.CeilToInt(seconds * 50f) + 64, Plugin.MinAudioContext.Value, 1500);
            // Temperature fallback re-decodes when unsure: better for the final result, too slow for previews.
            float temperatureInc = isFinal ? 0.2f : 0f;

            lock (Lock)
            {
                if (_native != null && NativeModels.TryGetValue(model, out IntPtr ctx) && ctx != IntPtr.Zero)
                {
                    float[] audio16k = To16k(samples, frequency);
                    var watch = Stopwatch.StartNew();
                    string text;
                    float noSpeech = 0f;
                    string simulate = _native.UseGpu ? Plugin.SimulateGpuFailure.Value : Plugin.FailureNone;
                    if (simulate == Plugin.FailureCrash && _native.TestAbort())
                    {
                        text = null; // not reached: the game has ended
                    }
                    else if (simulate == Plugin.FailureErrors)
                    {
                        Plugin.Log.LogWarning("Whisper: TEST: Testing.SimulateGpuFailure = Errors, this GPU recognition counts as failed.");
                        text = null;
                    }
                    else
                    {
                        text = _native.Transcribe(ctx, audio16k, language, prompt, audioCtx, threads, MaxTokens, temperatureInc, out noSpeech);
                    }
                    if (text == null)
                    {
                        if (++_nativeErrors >= ErrorsBeforeCpu)
                        {
                            DropToCpu();
                        }
                        text = "";
                    }
                    else
                    {
                        _nativeErrors = 0;
                    }
                    return new Result { Text = text, InferenceMs = watch.ElapsedMilliseconds, AudioSeconds = seconds, IsFinal = isFinal, NoSpeech = noSpeech };
                }
            }

            WhisperWrapper whisper;
            lock (Lock)
            {
                Models.TryGetValue(model, out whisper);
            }
            if (whisper == null)
            {
                return null;
            }
            var param = WhisperParams.GetDefaultParams();
            param.ThreadsCount = threads;
            param.Language = language;
            param.NoContext = true;
            param.SingleSegment = true;
            param.AudioCtx = audioCtx;
            param._param.no_timestamps = true;
            param._param.max_tokens = MaxTokens;
            param._param.suppress_non_speech_tokens = true;
            param._param.temperature_inc = temperatureInc;
            lock (Lock)
            {
                SetPrompt(param, prompt);
                var sw = Stopwatch.StartNew();
                WhisperResult result = whisper.GetText(samples, frequency, 1, param);
                return new Result { Text = result?.Result ?? "", InferenceMs = sw.ElapsedMilliseconds, AudioSeconds = seconds, IsFinal = isFinal };
            }
        }

        private static unsafe void SetPrompt(WhisperParams param, string prompt)
        {
            if (_promptPtr != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(_promptPtr);
                _promptPtr = IntPtr.Zero;
            }
            if (string.IsNullOrEmpty(prompt))
            {
                param._param.initial_prompt = null;
                return;
            }
            byte[] bytes = Encoding.UTF8.GetBytes(prompt);
            _promptPtr = Marshal.AllocHGlobal(bytes.Length + 1);
            Marshal.Copy(bytes, 0, _promptPtr, bytes.Length);
            Marshal.WriteByte(_promptPtr, bytes.Length, 0);
            param._param.initial_prompt = (byte*)_promptPtr;
        }
    }
}
