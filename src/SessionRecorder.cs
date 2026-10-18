using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace CryptmasterWhisper
{
    /// <summary>
    /// Testing.RecordSessions: one folder per game run under recordings\, with NNN.wav per Ear-button session
    /// and sessions.tsv (what the recogniser heard). tools\replay runs the WAVs through other models and
    /// settings and scores them against the test script. Recordings never leave this computer.
    /// </summary>
    internal static class SessionRecorder
    {
        internal sealed class Entry
        {
            public string Engine, Mode, GameLanguage, Final = "", Raw = "";
            public readonly List<string> Partials = new();
            public DateTime Started;
            public float Seconds;
            public int LatencyMs = -1, InferenceMs = -1;
        }

        private static string _folder;
        private static int _count;

        internal static void Save(Entry entry, float[] samples, int frequency)
        {
            try
            {
                if (_folder == null)
                {
                    _folder = Path.Combine(Plugin.Folder, "recordings", DateTime.Now.ToString("yyyyMMdd-HHmmss"));
                    Directory.CreateDirectory(_folder);
                    File.WriteAllText(Path.Combine(_folder, "sessions.tsv"),
                        "n\tfile\tstarted\tengine\tmode\tgame_language\tseconds\tfinal\traw\tlatency_ms\tinference_ms\tpartials\n", new UTF8Encoding(false));
                }
                _count++;
                string file = $"{_count:000}.wav";
                WriteWav(Path.Combine(_folder, file), samples, frequency);
                string Clean(string s) => (s ?? "").Replace('\t', ' ').Replace('\n', ' ');
                File.AppendAllText(Path.Combine(_folder, "sessions.tsv"),
                    string.Join("\t", _count, file, entry.Started.ToString("HH:mm:ss.fff"), entry.Engine, entry.Mode, entry.GameLanguage,
                        entry.Seconds.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture), Clean(entry.Final), Clean(entry.Raw),
                        entry.LatencyMs, entry.InferenceMs, Clean(string.Join(" | ", entry.Partials))) + "\n",
                    new UTF8Encoding(false));
            }
            catch (Exception e)
            {
                Plugin.Log.LogWarning($"Recording not saved: {e.Message}");
            }
        }

        private static void WriteWav(string path, float[] samples, int frequency)
        {
            using var writer = new BinaryWriter(File.Create(path));
            int bytes = samples.Length * 2;
            writer.Write(Encoding.ASCII.GetBytes("RIFF"));
            writer.Write(36 + bytes);
            writer.Write(Encoding.ASCII.GetBytes("WAVEfmt "));
            writer.Write(16);
            writer.Write((short)1);
            writer.Write((short)1);
            writer.Write(frequency);
            writer.Write(frequency * 2);
            writer.Write((short)2);
            writer.Write((short)16);
            writer.Write(Encoding.ASCII.GetBytes("data"));
            writer.Write(bytes);
            foreach (float s in samples)
            {
                writer.Write((short)(Math.Max(-1f, Math.Min(1f, s)) * short.MaxValue));
            }
        }
    }
}
