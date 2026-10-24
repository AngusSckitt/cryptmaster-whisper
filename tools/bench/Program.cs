// Benchmark of the game's own libwhisper.dll and models: load time and per-utterance latency.
// Input is noise (timing only); accuracy needs real speech and is tested in-game with a microphone.
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
struct P
{
    public int strategy, n_threads, n_max_text_ctx, offset_ms, duration_ms;
    public byte translate, no_context, no_timestamps, single_segment, print_special, print_progress, print_realtime, print_timestamps, token_timestamps;
    public float thold_pt, thold_ptsum; public int max_len; public byte split_on_word; public int max_tokens;
    public byte speed_up, debug_mode; public int audio_ctx; public byte tdrz_enable;
    public IntPtr suppress_regex, initial_prompt, prompt_tokens; public int prompt_n_tokens; public IntPtr language;
    public byte detect_language, suppress_blank, suppress_non_speech_tokens;
    public float temperature, max_initial_ts, length_penalty, temperature_inc, entropy_thold, logprob_thold, no_speech_thold;
    public int greedy_best_of; public int beam_size; public float patience;
    public IntPtr cb1, ud1, cb2, ud2, cb3, ud3, cb4, ud4, cb5, ud5, grammar_rules; public UIntPtr n_grammar_rules, i_start_rule; public float grammar_penalty;
}

static class N
{
    [DllImport("kernel32", CharSet = CharSet.Unicode)] public static extern bool SetDllDirectory(string p);
    [DllImport("libwhisper")] public static extern IntPtr whisper_context_default_params_by_ref();
    [DllImport("libwhisper")] public static extern IntPtr whisper_init_from_file_with_params([MarshalAs(UnmanagedType.LPStr)] string path, IntPtr cparamsByValue);
    [DllImport("libwhisper")] public static extern IntPtr whisper_full_default_params_by_ref(int strategy);
    [DllImport("libwhisper")] public static extern unsafe int whisper_full(IntPtr ctx, ref P p, float* s, int n);
    [DllImport("libwhisper")] public static extern int whisper_full_n_segments(IntPtr ctx);
    [DllImport("libwhisper")] public static extern IntPtr whisper_full_get_segment_text(IntPtr ctx, int i);
    [DllImport("libwhisper")] public static extern void whisper_free(IntPtr ctx);
    [DllImport("libwhisper")] public static extern void whisper_log_set(IntPtr cb, IntPtr ud);
}

static class Program
{
    delegate void Log(int level, IntPtr text, IntPtr ud);
    static Log _quiet = (l, t, u) => { };

    // --native <folder with cmwhisper.dll> [--cpu] model...: the mod's NativeBackend path, model loaded once.
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr LoadLibraryExW(string path, IntPtr file, uint flags);
    [DllImport("kernel32", CharSet = CharSet.Ansi)] static extern IntPtr GetProcAddress(IntPtr module, string name);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate IntPtr CmwInit(byte[] model, int useGpu);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int CmwTranscribe(IntPtr ctx, float[] s, int n, byte[] lang, byte[] prompt, int audioCtx, int threads, int maxTokens, float tempInc, byte[] output, int size, out float noSpeech);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate void CmwLogFn(int level, IntPtr text);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate void CmwSetLog(CmwLogFn fn);
    static CmwLogFn _cmwLog = (l, t) => { string s = Marshal.PtrToStringAnsi(t); if (s != null && (s.Contains("ggml_vulkan: 0") || s.Contains("CUDA0") || s.Contains("load_backend"))) Console.Error.Write("  " + s); };
    static byte[] Z(string s) { var b = System.Text.Encoding.UTF8.GetBytes(s); Array.Resize(ref b, b.Length + 1); return b; }

    static void NativeBench(string folder, bool cpu, string[] models, float[] audio)
    {
        // As the mod: dependencies first by full path (folder names with ';'), then the shim; DLL folder + System32.
        foreach (string d in new[] { "ggml-base.dll", "ggml.dll", "whisper.dll" })
            if (File.Exists(Path.Combine(folder, d))) LoadLibraryExW(Path.Combine(folder, d), IntPtr.Zero, 0x100 | 0x1000);
        IntPtr m = LoadLibraryExW(Path.Combine(folder, "cmwhisper.dll"), IntPtr.Zero, 0x100 | 0x1000);
        if (m == IntPtr.Zero) { Console.WriteLine($"cannot load cmwhisper.dll from {folder} (error {Marshal.GetLastWin32Error()})"); return; }
        T F<T>(string n) => Marshal.GetDelegateForFunctionPointer<T>(GetProcAddress(m, n));
        F<CmwSetLog>("cmw_set_log")(_cmwLog);
        var init = F<CmwInit>("cmw_init"); var transcribe = F<CmwTranscribe>("cmw_transcribe");
        foreach (string model in models)
        {
            var sw = Stopwatch.StartNew();
            IntPtr ctx = init(Z(model), cpu ? 0 : 1);
            long load = sw.ElapsedMilliseconds;
            if (ctx == IntPtr.Zero) { Console.WriteLine($"{Path.GetFileName(model)}: failed to load"); continue; }
            var output = new byte[4096];
            transcribe(ctx, audio, audio.Length, Z("pt"), Z(""), 256, 4, 24, 0f, output, output.Length, out _); // warm-up
            var times = new long[5];
            for (int i = 0; i < times.Length; i++) { sw.Restart(); transcribe(ctx, audio, audio.Length, Z("pt"), Z(""), 256, 4, 24, 0f, output, output.Length, out _); times[i] = sw.ElapsedMilliseconds; }
            Array.Sort(times);
            Console.WriteLine($"{Path.GetFileName(folder.TrimEnd('\\')),-34} {Path.GetFileName(model),-30} load {load,5} ms | 2 s utterance: {times[2],5} ms (median of 5, warm){(cpu ? " CPU" : "")}");
        }
    }

    static unsafe void Main(string[] args)
    {
        if (args.Length > 1 && args[0] == "--native")
        {
            bool cpu = args.Contains("--cpu");
            var r = new Random(1);
            float[] noise = Enumerable.Range(0, 16000 * 2).Select(_ => (float)(r.NextDouble() - 0.5) * 0.02f).ToArray();
            NativeBench(args[1], cpu, args.Skip(2).Where(a => a != "--cpu").ToArray(), noise);
            return;
        }
        string game = @"C:\Program Files (x86)\Steam\steamapps\common\Cryptmaster\CryptMaster_Data";
        N.SetDllDirectory(Path.Combine(game, @"Plugins\x86_64"));
        N.whisper_log_set(Marshal.GetFunctionPointerForDelegate(_quiet), IntPtr.Zero);
        var rnd = new Random(1);
        float[] audio = Enumerable.Range(0, 16000 * 2).Select(_ => (float)(rnd.NextDouble() - 0.5) * 0.02f).ToArray();
        int threads = Environment.ProcessorCount;
        foreach (string model in args.Length > 0 ? args : new[] { "ggml-model-whisper-tiny-q5_1.bin", "ggml-tiny.bin", "ggml-model-whisper-tiny.en-q8_0.bin" })
        {
            var sw = Stopwatch.StartNew();
            // whisper_context_params is passed by value; on x64 a struct this size goes as a pointer to a copy.
            IntPtr ctx = N.whisper_init_from_file_with_params(Path.IsPathRooted(model) ? model : Path.Combine(game, "StreamingAssets", "Whisper", model), N.whisper_context_default_params_by_ref());
            long load = sw.ElapsedMilliseconds;
            if (ctx == IntPtr.Zero) { Console.WriteLine($"{model}: failed to load"); continue; }
            foreach (int audioCtx in new[] { 0, 256 })
            {
                P p = Marshal.PtrToStructure<P>(N.whisper_full_default_params_by_ref(0));
                p.n_threads = threads; p.no_context = 1; p.single_segment = 1; p.no_timestamps = 1; p.max_tokens = 10;
                p.print_progress = 0; p.print_realtime = 0; p.print_timestamps = 0; p.audio_ctx = audioCtx;
                p.temperature_inc = 0; // no fallback re-decoding: keeps latency bounded
                p.language = Marshal.StringToHGlobalAnsi(model.Contains(".en") ? "en" : "pt");
                long[] times = new long[4];
                for (int run = 0; run < times.Length; run++)
                {
                    sw.Restart();
                    fixed (float* s = audio) { N.whisper_full(ctx, ref p, s, audio.Length); }
                    times[run] = sw.ElapsedMilliseconds;
                }
                Array.Sort(times);
                Console.WriteLine($"{Path.GetFileName(model),-38} load {load,5} ms | audio_ctx {(audioCtx == 0 ? "1500 (30 s)" : audioCtx.ToString()),-11} | 2 s utterance: {times[1],5} ms (median), {threads} threads");
            }
            N.whisper_free(ctx);
        }
    }
}
