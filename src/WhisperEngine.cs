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
    /// Runs the game's own libwhisper through its own whisper.unity binding. What changes from the binding's
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

        /// <summary>Model.PerLanguage (by game language code) first, then the English or multilingual default.</summary>
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
            return whisperLanguage == "en" ? Plugin.ModelEnglish.Value : Plugin.ModelMultilingual.Value;
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

        /// <summary>Loads a model (once); call from a worker thread.</summary>
        internal static WhisperWrapper Get(string modelName)
        {
            lock (Lock)
            {
                if (Models.TryGetValue(modelName, out WhisperWrapper loaded))
                {
                    return loaded;
                }
                string path = ResolveModel(modelName);
                if (path == null)
                {
                    Plugin.Log.LogError($"Whisper model '{modelName}' not found (models folder or StreamingAssets\\Whisper).");
                    Models[modelName] = null;
                    return null;
                }
                var sw = Stopwatch.StartNew();
                WhisperWrapper wrapper = WhisperWrapper.InitFromFile(path);
                Plugin.Log.LogInfo($"Whisper model {Path.GetFileName(path)} loaded in {sw.ElapsedMilliseconds} ms (multilingual: {wrapper?.IsMultilingual}).");
                Models[modelName] = wrapper;
                return wrapper;
            }
        }

        internal sealed class Result
        {
            public string Text;
            public long InferenceMs;
            public float AudioSeconds;
            public bool IsFinal;
        }

        /// <summary>Transcribes one utterance; blocking, call from a worker thread.</summary>
        internal static unsafe Result Transcribe(float[] samples, int frequency, string model, string language, string prompt, bool isFinal)
        {
            WhisperWrapper whisper = Get(model);
            if (whisper == null)
            {
                return null;
            }
            float seconds = samples.Length / (float)frequency;
            var param = WhisperParams.GetDefaultParams();
            param.ThreadsCount = Plugin.Threads.Value > 0 ? Plugin.Threads.Value : Mathf.Clamp(Environment.ProcessorCount - 1, 1, 4);
            param.Language = language;
            param.NoContext = true;
            param.SingleSegment = true;
            // 50 encoder frames per second of audio, plus margin; never more than Whisper's 30 s window.
            param.AudioCtx = Mathf.Clamp(Mathf.CeilToInt(seconds * 50f) + 64, Plugin.MinAudioContext.Value, 1500);
            param._param.no_timestamps = true;
            param._param.max_tokens = 24;
            param._param.suppress_non_speech_tokens = true;
            // Temperature fallback re-decodes when unsure: better for the final result, too slow for previews.
            if (!isFinal)
            {
                param._param.temperature_inc = 0f;
            }
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
