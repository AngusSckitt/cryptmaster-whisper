using System;
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
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int TranscribeFn(IntPtr ctx, float[] samples, int n, byte[] language, byte[] prompt, int audioCtx,
            int threads, int maxTokens, float temperatureInc, byte[] output, int outputSize, out float noSpeech);

        [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr LoadLibraryExW(string path, IntPtr file, uint flags);
        [DllImport("kernel32", CharSet = CharSet.Ansi)]
        private static extern IntPtr GetProcAddress(IntPtr module, string name);
        private const uint LoadWithAlteredSearchPath = 0x8;

        internal string Variant { get; }
        internal bool UseGpu { get; }
        private SetLogFn _setLog;
        private SystemInfoFn _systemInfo;
        private InitFn _init;
        private FreeFn _free;
        private TranscribeFn _transcribe;

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
            IntPtr module = LoadLibraryExW(dll, IntPtr.Zero, LoadWithAlteredSearchPath);
            if (module == IntPtr.Zero)
            {
                Plugin.Log.LogWarning($"Whisper: could not load {dll} (error {Marshal.GetLastWin32Error()}; the Microsoft Visual C++ 2015-2022 runtime may be missing).");
                return null;
            }
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
            if (version == null || version() != 1 || backend._init == null || backend._transcribe == null)
            {
                Plugin.Log.LogWarning($"Whisper: {dll} is not a compatible cmwhisper.dll.");
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

        internal string Transcribe(IntPtr model, float[] samples16k, string language, string prompt, int audioCtx, int threads,
            int maxTokens, float temperatureInc, out float noSpeech)
        {
            var output = new byte[4096];
            int result = _transcribe(model, samples16k, samples16k.Length, Utf8(language), Utf8(prompt ?? ""), audioCtx, threads, maxTokens,
                temperatureInc, output, output.Length, out noSpeech);
            if (result != 0)
            {
                Plugin.Log.LogWarning($"Whisper: whisper.cpp returned error {result}.");
                return "";
            }
            int length = Array.IndexOf(output, (byte)0);
            return Encoding.UTF8.GetString(output, 0, length < 0 ? output.Length : length);
        }

        private static byte[] Utf8(string s)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(s ?? "");
            Array.Resize(ref bytes, bytes.Length + 1);
            return bytes;
        }
    }
}
