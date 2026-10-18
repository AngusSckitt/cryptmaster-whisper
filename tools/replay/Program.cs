// Replays recorded test sessions (Testing.RecordSessions) through Whisper models and scores every recogniser
// against tests\TEST_SCRIPT.md. See README.md. Recordings are real people's voices: keep them local.
using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

static class Program
{
    const string Game = @"C:\Program Files (x86)\Steam\steamapps\common\Cryptmaster\CryptMaster_Data";

    record Line(string Id, string Say, string[] Accept, string Tag);
    record Recording(int N, string File, string Engine, string Mode, string Language, string LiveFinal);

    static int Main(string[] args)
    {
        if (args.Length < 2)
        {
            Console.WriteLine("Usage: replay <recordings folder> <session, e.g. S1> [--models a.bin,b.bin] [--cli path\\whisper-cli.exe] [--script path] [--audio-ctx 256]");
            return 1;
        }
        string folder = args[0], session = args[1];
        string script = Option(args, "--script") ?? Path.Combine(AppContext.BaseDirectory, @"..\..\..\..\..\tests\TEST_SCRIPT.md");
        string cli = Option(args, "--cli");
        int minCtx = int.Parse(Option(args, "--audio-ctx") ?? "256");
        string[] models = (Option(args, "--models") ?? Path.Combine(Game, @"StreamingAssets\Whisper\ggml-tiny.bin")).Split(',');

        List<Line> lines = ReadScript(script, session);
        List<Recording> recs = ReadSessions(Path.Combine(folder, "sessions.tsv"));
        if (lines.Count == 0 || recs.Count == 0)
        {
            Console.WriteLine($"Nothing to compare: {lines.Count} script lines for {session}, {recs.Count} recordings.");
            return 1;
        }

        // Recogniser name -> text per recording.
        var results = new Dictionary<string, string[]>();
        var times = new Dictionary<string, List<long>>();
        foreach (var engine in recs.Select(r => r.Engine).Distinct())
        {
            results[$"{engine} (live)"] = recs.Select(r => r.Engine == engine ? r.LiveFinal : null).ToArray();
        }
        foreach (string model in models)
        {
            string name = $"{Path.GetFileName(model)}{(cli != null ? " (cli)" : "")}";
            results[name] = new string[recs.Count];
            times[name] = new List<long>();
            using var whisper = cli == null ? new InProcess(model) : null;
            for (int i = 0; i < recs.Count; i++)
            {
                float[] audio = Trim(ReadWav(Path.Combine(folder, recs[i].File), out int rate), rate);
                string lang = Lang(recs[i].Language);
                var sw = Stopwatch.StartNew();
                results[name][i] = audio.Length < rate * 0.15 ? "" : cli != null ? Cli(cli, model, Path.Combine(folder, recs[i].File), lang, minCtx) : whisper.Transcribe(audio, rate, lang, minCtx);
                times[name].Add(sw.ElapsedMilliseconds);
                Console.Error.Write(".");
            }
            Console.Error.WriteLine($" {name}");
        }

        // Align recordings to script lines (in order; skips and repeats allowed) using every recogniser's text.
        int[] lineOf = Align(lines, recs, results);

        var report = new StringBuilder();
        report.AppendLine($"# Replay of {session}: {Path.GetFileName(folder.TrimEnd('\\'))}");
        report.AppendLine();
        report.AppendLine("| Recogniser | Correct | Wrong word | Missed | False activations | Avg time |");
        report.AppendLine("|---|---|---|---|---|---|");
        foreach (var (name, texts) in results)
        {
            int correct = 0, wrong = 0, missed = 0, falseAct = 0, words = 0, silent = 0;
            for (int i = 0; i < recs.Count; i++)
            {
                if (texts[i] == null || lineOf[i] < 0) continue;
                Line line = lines[lineOf[i]];
                string heard = Norm(texts[i]);
                if (line.Accept.Length == 0) { silent++; if (heard != "") falseAct++; continue; }
                words++;
                if (heard == "") missed++; else if (line.Accept.Contains(heard)) correct++; else wrong++;
            }
            if (words + silent == 0) continue;
            string avg = times.TryGetValue(name, out var t) && t.Count > 0 ? $"{t.Average():0} ms" : "";
            report.AppendLine($"| {name} | {Pct(correct, words)} | {Pct(wrong, words)} | {Pct(missed, words)} | {falseAct}/{silent} | {avg} |");
        }
        report.AppendLine();
        report.AppendLine("## Every recording");
        report.AppendLine();
        report.AppendLine("| # | Line | Say | Emulate | " + string.Join(" | ", results.Keys) + " |");
        report.AppendLine("|---|---|---|---|" + string.Concat(results.Keys.Select(_ => "---|")));
        for (int i = 0; i < recs.Count; i++)
        {
            Line line = lineOf[i] >= 0 ? lines[lineOf[i]] : null;
            report.AppendLine($"| {recs[i].N} | {line?.Id ?? "?"} | {line?.Say} | {line?.Tag} | " + string.Join(" | ", results.Values.Select(v => Mark(v[i], line))) + " |");
        }
        string output = Path.Combine(folder, $"replay-{session}.md");
        File.WriteAllText(output, report.ToString(), new UTF8Encoding(false));
        Console.WriteLine(report.ToString().Split("## Every")[0]);
        Console.WriteLine($"Full report: {output}");
        return 0;
    }

    static string Option(string[] args, string name) { int i = Array.IndexOf(args, name); return i >= 0 && i + 1 < args.Length ? args[i + 1] : null; }
    static string Pct(int n, int of) => of == 0 ? "-" : $"{100.0 * n / of:0}% ({n}/{of})";
    static string Mark(string text, Line line)
    {
        if (text == null) return "";
        string heard = Norm(text);
        string ok = line == null ? "" : line.Accept.Length == 0 ? (heard == "" ? " ✓" : " ✗") : line.Accept.Contains(heard) ? " ✓" : " ✗";
        return (heard == "" ? "(nothing)" : text.Trim().Replace("|", "/")) + ok;
    }

    static string Lang(string game) => game?.ToUpperInvariant() switch { "ENG" => "en", "SPA" => "es", "POR" => "pt", _ => "auto" };

    /// <summary>As the game compares: lower case, letters and digits only, no accents (the PT mod maps accented input).</summary>
    static string Norm(string s)
    {
        if (string.IsNullOrWhiteSpace(s)) return "";
        var b = new StringBuilder();
        foreach (char c in s.Normalize(NormalizationForm.FormD).ToLowerInvariant())
        {
            if (CharUnicodeInfo.GetUnicodeCategory(c) == UnicodeCategory.NonSpacingMark) continue;
            if (char.IsLetterOrDigit(c)) b.Append(c);
        }
        return b.ToString();
    }

    static List<Line> ReadScript(string path, string session)
    {
        var lines = new List<Line>();
        foreach (string row in File.ReadAllLines(path))
        {
            var m = Regex.Match(row, @"^\|\s*(" + Regex.Escape(session) + @"-[A-Z]?\d+)\s*\|([^|]*)\|((?:[^|\\]|\\\|)*)\|([^|]*)\|");
            if (!m.Success) continue;
            string[] accept = m.Groups[3].Value.Split(@"\|").Select(a => Norm(a)).Where(a => a != "").ToArray();
            string tag = m.Groups[4].Value.Trim().Split(' ', ',', ':')[0];
            lines.Add(new Line(m.Groups[1].Value, m.Groups[2].Value.Trim(), accept, tag));
        }
        return lines;
    }

    static List<Recording> ReadSessions(string path)
    {
        var recs = new List<Recording>();
        foreach (string row in File.ReadAllLines(path, Encoding.UTF8).Skip(1))
        {
            string[] f = row.Split('\t');
            if (f.Length >= 8) recs.Add(new Recording(int.Parse(f[0]), f[1], f[3], f[4], f[5], f[7]));
        }
        return recs;
    }

    /// <summary>Order-preserving alignment (like a diff): each recording maps to one line or none.</summary>
    static int[] Align(List<Line> lines, List<Recording> recs, Dictionary<string, string[]> results)
    {
        double Score(int r, int l)
        {
            var line = lines[l];
            double best = 0;
            foreach (var texts in results.Values)
            {
                string h = Norm(texts[r]);
                if (line.Accept.Length == 0) best = Math.Max(best, h == "" ? 0.6 : 0.3);
                else foreach (string a in line.Accept) best = Math.Max(best, h == "" ? 0.2 : 1.0 - (double)Lev(h, a) / Math.Max(h.Length, a.Length));
            }
            return best;
        }
        int R = recs.Count, L = lines.Count;
        var dp = new double[R + 1, L + 1];
        var from = new int[R + 1, L + 1];
        const double skip = -0.15;
        for (int r = 0; r <= R; r++)
            for (int l = 0; l <= L; l++)
            {
                if (r == 0 && l == 0) continue;
                double best = double.NegativeInfinity; int how = 0;
                if (r > 0 && l > 0 && dp[r - 1, l - 1] + Score(r - 1, l - 1) > best) { best = dp[r - 1, l - 1] + Score(r - 1, l - 1); how = 1; }
                if (r > 0 && dp[r - 1, l] + skip > best) { best = dp[r - 1, l] + skip; how = 2; }   // extra recording (retake)
                if (l > 0 && dp[r, l - 1] + skip > best) { best = dp[r, l - 1] + skip; how = 3; }   // skipped line
                dp[r, l] = best; from[r, l] = how;
            }
        var lineOf = Enumerable.Repeat(-1, R).ToArray();
        for (int r = R, l = L; r > 0 || l > 0;)
        {
            switch (from[r, l])
            {
                case 1: lineOf[r - 1] = l - 1; r--; l--; break;
                case 2: r--; break;
                default: l--; break;
            }
        }
        return lineOf;
    }

    static int Lev(string a, string b)
    {
        var d = new int[a.Length + 1, b.Length + 1];
        for (int i = 0; i <= a.Length; i++) d[i, 0] = i;
        for (int j = 0; j <= b.Length; j++) d[0, j] = j;
        for (int i = 1; i <= a.Length; i++)
            for (int j = 1; j <= b.Length; j++)
                d[i, j] = Math.Min(Math.Min(d[i - 1, j] + 1, d[i, j - 1] + 1), d[i - 1, j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
        return d[a.Length, b.Length];
    }

    static float[] ReadWav(string path, out int rate)
    {
        byte[] b = File.ReadAllBytes(path);
        rate = BitConverter.ToInt32(b, 24);
        int data = 12;
        while (Encoding.ASCII.GetString(b, data, 4) != "data") data += 8 + BitConverter.ToInt32(b, data + 4);
        int n = BitConverter.ToInt32(b, data + 4) / 2;
        var s = new float[n];
        for (int i = 0; i < n; i++) s[i] = BitConverter.ToInt16(b, data + 8 + i * 2) / 32768f;
        return s;
    }

    /// <summary>Drops leading and trailing silence, like the mod's Automatic mode (0.25 s margins).</summary>
    static float[] Trim(float[] s, int rate)
    {
        int frame = rate / 50, first = -1, last = -1;
        float floor = 0.002f;
        for (int f = 0; f * frame + frame <= s.Length; f++)
        {
            double sum = 0; for (int i = 0; i < frame; i++) sum += s[f * frame + i] * s[f * frame + i];
            float rms = (float)Math.Sqrt(sum / frame);
            bool voiced = rms > Math.Max(floor * 3, 0.01f);
            if (!voiced) floor += (rms - floor) * 0.05f;
            else { if (first < 0) first = f; last = f; }
        }
        if (first < 0) return Array.Empty<float>();
        int start = Math.Max(0, first * frame - rate / 4), end = Math.Min(s.Length, (last + 1) * frame + rate / 4);
        return s[start..end];
    }

    static string Cli(string exe, string model, string wav, string lang, int minCtx)
    {
        var p = new ProcessStartInfo(exe, $"-m \"{model}\" -f \"{wav}\" -l {lang} -ac {minCtx} -nt -bs 1 -bo 1 -mc 0 -np")
        { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false, StandardOutputEncoding = Encoding.UTF8 };
        using var proc = Process.Start(p);
        string text = proc.StandardOutput.ReadToEnd();
        proc.StandardError.ReadToEnd();
        proc.WaitForExit();
        return text.Trim();
    }

    // ---- The game's own libwhisper (whisper.cpp 1.5.4), the same parameters as the mod ----

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

    sealed class InProcess : IDisposable
    {
        [DllImport("kernel32", CharSet = CharSet.Unicode)] static extern bool SetDllDirectory(string p);
        [DllImport("libwhisper")] static extern IntPtr whisper_context_default_params_by_ref();
        [DllImport("libwhisper")] static extern IntPtr whisper_init_from_file_with_params([MarshalAs(UnmanagedType.LPStr)] string path, IntPtr cparams);
        [DllImport("libwhisper")] static extern IntPtr whisper_full_default_params_by_ref(int strategy);
        [DllImport("libwhisper")] static extern unsafe int whisper_full(IntPtr ctx, ref P p, float* s, int n);
        [DllImport("libwhisper")] static extern int whisper_full_n_segments(IntPtr ctx);
        [DllImport("libwhisper")] static extern IntPtr whisper_full_get_segment_text(IntPtr ctx, int i);
        [DllImport("libwhisper")] static extern void whisper_free(IntPtr ctx);
        [DllImport("libwhisper")] static extern void whisper_log_set(IntPtr cb, IntPtr ud);
        delegate void Log(int level, IntPtr text, IntPtr ud);
        static readonly Log Quiet = (l, t, u) => { };
        readonly IntPtr _ctx;

        public InProcess(string model)
        {
            SetDllDirectory(Path.Combine(Game, @"Plugins\x86_64"));
            whisper_log_set(Marshal.GetFunctionPointerForDelegate(Quiet), IntPtr.Zero);
            _ctx = whisper_init_from_file_with_params(model, whisper_context_default_params_by_ref());
            if (_ctx == IntPtr.Zero) throw new Exception("Could not load " + model);
        }

        public unsafe string Transcribe(float[] audio, int rate, string lang, int minCtx)
        {
            if (rate != 16000) audio = Resample(audio, rate);
            P p = Marshal.PtrToStructure<P>(whisper_full_default_params_by_ref(0));
            p.n_threads = Math.Clamp(Environment.ProcessorCount - 1, 1, 4);
            p.no_context = 1; p.single_segment = 1; p.no_timestamps = 1; p.max_tokens = 24; p.suppress_non_speech_tokens = 1;
            p.print_progress = p.print_realtime = p.print_timestamps = 0;
            p.audio_ctx = Math.Clamp((int)Math.Ceiling(audio.Length / 16000.0 * 50) + 64, minCtx, 1500);
            IntPtr l = Marshal.StringToHGlobalAnsi(lang);
            p.language = l;
            try
            {
                fixed (float* s = audio) { if (whisper_full(_ctx, ref p, s, audio.Length) != 0) return ""; }
                var b = new StringBuilder();
                for (int i = 0; i < whisper_full_n_segments(_ctx); i++) b.Append(Utf8(whisper_full_get_segment_text(_ctx, i)));
                return b.ToString();
            }
            finally { Marshal.FreeHGlobal(l); }
        }

        static string Utf8(IntPtr p) { int n = 0; while (Marshal.ReadByte(p, n) != 0) n++; var b = new byte[n]; Marshal.Copy(p, b, 0, n); return Encoding.UTF8.GetString(b); }
        static float[] Resample(float[] s, int rate) { int n = (int)((long)s.Length * 16000 / rate); var o = new float[n]; for (int i = 0; i < n; i++) o[i] = s[(int)((long)i * rate / 16000)]; return o; }
        public void Dispose() => whisper_free(_ctx);
    }
}
