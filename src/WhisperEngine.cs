using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
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

        internal static string BackendName => _native == null ? "game" : _native.Variant + (_native.UseGpu ? "" : "-cpu");

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
                    string text = _native.Transcribe(ctx, audio16k, language, prompt, audioCtx, threads, 24, temperatureInc, out float noSpeech);
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
            param._param.max_tokens = 24;
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
