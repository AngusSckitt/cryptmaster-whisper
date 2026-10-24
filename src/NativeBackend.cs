using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace CryptmasterWhisper
{
    /// <summary>
    /// A current whisper.cpp (GPU-capable) shipped with the mod in native\&lt;variant&gt;\, reached through
    /// cmwhisper.dll, the mod's own small C interface compiled against whisper.cpp's headers
    /// (native\cmwhisper.cpp). Loaded by full path so its whisper.dll and ggml backends come from that folder.
    /// </summary>
    internal sealed class NativeBackend
    {
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int VersionFn();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void LogFn(int level, IntPtr text);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void SetLogFn(LogFn fn);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate IntPtr SystemInfoFn();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate IntPtr InitFn(byte[] modelUtf8, int useGpu);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void FreeFn(IntPtr ctx);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int GpuFn(byte[] name, int size);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate IntPtr VadInitFn(byte[] modelUtf8);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate float VadProbFn(IntPtr vad, float[] samples, int n);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void VadFn(IntPtr vad);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void CrashReportFn(byte[] pathUtf8, byte[] headerUtf8);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void TestAbortFn();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int TranscribeFn(IntPtr ctx, float[] samples, int n, byte[] language, byte[] prompt, int audioCtx,
            int threads, int maxTokens, float temperatureInc, byte[] output, int outputSize, out float noSpeech);

        [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr LoadLibraryExW(string path, IntPtr file, uint flags);
        [DllImport("kernel32", SetLastError = true)]
        private static extern bool FreeLibrary(IntPtr module);
        [DllImport("kernel32", CharSet = CharSet.Ansi)]
        private static extern IntPtr GetProcAddress(IntPtr module, string name);
        // The DLL's own folder (for whisper.dll, ggml*.dll) plus System32, never PATH or the current folder.
        // Unlike LOAD_WITH_ALTERED_SEARCH_PATH, a ';' in the game's folder name doesn't break it.
        private const uint LoadSearchDllDirAndDefaults = 0x100 | 0x1000;

        internal string Variant { get; }
        internal bool UseGpu { get; }
        private SetLogFn _setLog;
        private SystemInfoFn _systemInfo;
        private InitFn _init;
        private FreeFn _free;
        private TranscribeFn _transcribe;
        private VadInitFn _vadInit;
        private VadProbFn _vadProb;
        private VadFn _vadReset, _vadFree;
        private TestAbortFn _testAbort;

        /// <summary>What ggml writes if it ends the game (GPU driver reset, CUDA error...); read on the next launch.</summary>
        private static string CrashFile => Path.Combine(Path.Combine(Plugin.Folder, "logs"), "native-crash.txt");

        /// <summary>The GPU in use ("" when recognition runs on the CPU), and its free memory in MB.</summary>
        internal string GpuName { get; private set; } = "";
        internal int GpuFreeMb { get; private set; } = -1;
        private static LogFn _logKeepAlive; // the native side keeps this pointer

        private NativeBackend(string variant, bool useGpu)
        {
            Variant = variant;
            UseGpu = useGpu;
        }

        internal static string Folder(string variant) => Path.Combine(Plugin.Folder, "native", variant);

        internal static bool IsInstalled(string variant) => File.Exists(Path.Combine(Folder(variant), "cmwhisper.dll"));

        /// <summary>Loads native\&lt;variant&gt;\cmwhisper.dll; null (with a log line) if it can't.</summary>
        internal static NativeBackend TryLoad(string variant, bool useGpu)
        {
            string dll = Path.Combine(Folder(variant), "cmwhisper.dll");
            if (!File.Exists(dll))
            {
                return null;
            }
            // Its dependencies first, by full path, in import order: Windows can't search a folder whose name has
            // a ';' (a Steam library can be called anything), and a DLL that's already loaded is found by name.
            var loaded = new List<IntPtr>();
            foreach (string dependency in new[] { "ggml-base.dll", "ggml.dll", "whisper.dll" })
            {
                string path = Path.Combine(Folder(variant), dependency);
                IntPtr handle = File.Exists(path) ? LoadLibraryExW(path, IntPtr.Zero, LoadSearchDllDirAndDefaults) : IntPtr.Zero;
                if (handle != IntPtr.Zero) loaded.Add(handle);
            }
            // On failure, everything loaded here is unloaded again: the Vulkan and CUDA builds share DLL names, so
            // a CUDA leftover would otherwise stand in for the Vulkan build's own files in the fallback.
            void Unload()
            {
                for (int i = loaded.Count - 1; i >= 0; i--) FreeLibrary(loaded[i]);
            }
            IntPtr module = LoadLibraryExW(dll, IntPtr.Zero, LoadSearchDllDirAndDefaults);
            if (module == IntPtr.Zero)
            {
                int error = Marshal.GetLastWin32Error();
                string why = error == 126 ? "a file it needs is missing: the Microsoft Visual C++ 2015-2022 runtime, or one of that folder's DLLs"
                    : error == 193 ? "the file is damaged or not a 64-bit DLL; reinstalling the mod replaces it"
                    : "see the error code";
                Plugin.Log.LogWarning($"Whisper: could not load {dll} (error {error}: {why}).");
                Unload();
                return null;
            }
            loaded.Add(module);
            var backend = new NativeBackend(variant, useGpu);
            T Get<T>(string name) where T : Delegate
            {
                IntPtr fn = GetProcAddress(module, name);
                return fn == IntPtr.Zero ? null : (T)Marshal.GetDelegateForFunctionPointer(fn, typeof(T));
            }
            VersionFn version = Get<VersionFn>("cmw_interface_version");
            backend._setLog = Get<SetLogFn>("cmw_set_log");
            backend._systemInfo = Get<SystemInfoFn>("cmw_system_info");
            backend._init = Get<InitFn>("cmw_init");
            backend._free = Get<FreeFn>("cmw_free");
            backend._transcribe = Get<TranscribeFn>("cmw_transcribe");
            // Silero voice activity detection (optional: older shims don't have it).
            backend._vadInit = Get<VadInitFn>("cmw_vad_init");
            backend._vadProb = Get<VadProbFn>("cmw_vad_prob");
            backend._vadReset = Get<VadFn>("cmw_vad_reset");
            backend._vadFree = Get<VadFn>("cmw_vad_free");
            if (version == null || version() != 1 || backend._init == null || backend._transcribe == null)
            {
                Plugin.Log.LogWarning($"Whisper: {dll} is not a compatible cmwhisper.dll.");
                Unload();
                return null;
            }
            _logKeepAlive = (level, text) =>
            {
                string line = Marshal.PtrToStringAnsi(text)?.TrimEnd();
                // Backend and device lines are worth keeping; the rest (per-call timings) is noise.
                if (!string.IsNullOrEmpty(line) && (level >= 3 || line.Contains("backend") || line.Contains("ggml_vulkan: 0") || line.Contains("CUDA0") || line.Contains("using")))
                {
                    Plugin.Log.LogInfo($"[whisper.cpp] {line}");
                }
            };
            backend._setLog?.Invoke(_logKeepAlive);
            // Optional (older shims don't have it): a crash report names the backend that was in use.
            backend._testAbort = Get<TestAbortFn>("cmw_test_abort");
            CrashReportFn crashReport = Get<CrashReportFn>("cmw_set_crash_report");
            if (crashReport != null)
            {
                Directory.CreateDirectory(Path.GetDirectoryName(CrashFile));
                crashReport(Utf8(CrashFile), Utf8($"backend={variant}{(useGpu ? "" : "-cpu")}\n"));
            }
            GpuFn gpu = Get<GpuFn>("cmw_gpu");
            if (useGpu && gpu != null)
            {
                var name = new byte[256];
                backend.GpuFreeMb = gpu(name, name.Length);
                int length = Array.IndexOf(name, (byte)0);
                backend.GpuName = backend.GpuFreeMb >= 0 ? Encoding.UTF8.GetString(name, 0, length < 0 ? name.Length : length) : "";
            }
            Plugin.Log.LogInfo($"Whisper: using whisper.cpp from native\\{variant} on " +
                (backend.GpuName != "" ? $"the GPU ({backend.GpuName}, {backend.GpuFreeMb} MB free)." : "the CPU."));
            return backend;
        }

        internal string SystemInfo() => _systemInfo == null ? "" : Marshal.PtrToStringAnsi(_systemInfo());

        internal IntPtr LoadModel(string path) => _init(Utf8(path), UseGpu ? 1 : 0);

        internal void FreeModel(IntPtr model) => _free?.Invoke(model);

        internal bool HasVad => _vadInit != null && _vadProb != null && _vadReset != null;
        internal IntPtr LoadVad(string path) => HasVad ? _vadInit(Utf8(path)) : IntPtr.Zero;
        /// <summary>Highest speech probability (0..1) over 16 kHz samples (a multiple of 512), or -1.</summary>
        internal float VadProbability(IntPtr vad, float[] samples16k) => _vadProb(vad, samples16k, samples16k.Length);
        internal void VadReset(IntPtr vad) => _vadReset(vad);

        internal string Transcribe(IntPtr model, float[] samples16k, string language, string prompt, int audioCtx, int threads,
            int maxTokens, float temperatureInc, out float noSpeech)
        {
            var output = new byte[4096];
            int result = _transcribe(model, samples16k, samples16k.Length, Utf8(language), Utf8(prompt ?? ""), audioCtx, threads, maxTokens,
                temperatureInc, output, output.Length, out noSpeech);
            if (result != 0)
            {
                Plugin.Log.LogWarning($"Whisper: whisper.cpp returned error {result}.");
                return null;
            }
            int length = Array.IndexOf(output, (byte)0);
            return Encoding.UTF8.GetString(output, 0, length < 0 ? output.Length : length);
        }

        /// <summary>Testing only: ends the game the way a GPU error does (false if this shim can't).</summary>
        internal bool TestAbort()
        {
            if (_testAbort == null)
            {
                return false;
            }
            _testAbort();
            return true;
        }

        /// <summary>
        /// A crash report left by the last session, if any: logged, kept in logs\ under a dated name, and the
        /// backend that crashed returned ("cuda", "vulkan", "vulkan-cpu"...); null if there was none.
        /// </summary>
        internal static string TakeCrashReport()
        {
            try
            {
                if (!File.Exists(CrashFile))
                {
                    return null;
                }
                string[] lines = File.ReadAllLines(CrashFile);
                string kept = Path.Combine(Path.GetDirectoryName(CrashFile), $"native-crash-{File.GetLastWriteTime(CrashFile):yyyyMMdd-HHmmss}.txt");
                File.Delete(kept);
                File.Move(CrashFile, kept);
                string backend = lines.Length > 0 && lines[0].StartsWith("backend=") ? lines[0].Substring(8).Trim() : "";
                Plugin.Log.LogWarning($"Whisper: whisper.cpp ended the last session ({backend}): {string.Join(" ", lines, 1, Math.Max(0, lines.Length - 1)).Trim()} (kept in {kept}).");
                return backend;
            }
            catch (Exception e)
            {
                Plugin.Log.LogWarning($"Whisper: could not read the last crash report: {e.Message}");
                return null;
            }
        }

        private static byte[] Utf8(string s)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(s ?? "");
            Array.Resize(ref bytes, bytes.Length + 1);
            return bytes;
        }
    }
}
