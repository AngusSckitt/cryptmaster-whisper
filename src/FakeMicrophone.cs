using System.Collections.Generic;
using System.IO;
using UnityEngine;

namespace CryptmasterWhisper
{
    /// <summary>
    /// Testing only (Testing.FakeMicrophone = a playlist file): stands in for the microphone, feeding recorded
    /// clips of real people in real time, with quiet gaps between them, so the whole listening pipeline can be
    /// tested without anyone speaking (and without a virtual audio driver). Playlist lines: path|expected
    /// (expected empty for clips that should produce nothing). Every final result is logged against what the
    /// clip says. Never use synthesised speech here: the clips must be recordings of real people.
    /// </summary>
    internal static class FakeMicrophone
    {
        private sealed class Item
        {
            public string Path, Expected;
        }

        private const float Lead = 0.4f, Gap = 1.5f;
        private static readonly List<Item> Playlist = new();
        private static int _index = -1;
        private static float[] _clip;
        private static int _clipPos;
        private static float _silenceLeft;
        private static float _lastTime;
        private static int _frequency;
        private static float _clipEnded = -10f;
        private static bool _sessionClipDone; // Push to Talk: this session's clip has finished
        private static readonly System.Random Noise = new(7);
        internal static int Correct, Wrong, Missed, FalseActivations, Silent;

        internal static bool Enabled => Plugin.FakeMicrophone.Value.Trim() != "" && Playlist.Count > 0;
        internal static bool Finished => _index >= Playlist.Count;
        /// <summary>What the clip being played (or just played) says; null between clips.</summary>
        internal static string CurrentExpected { get; private set; }
        internal static string CurrentFile { get; private set; }

        internal static void Load()
        {
            string path = Plugin.FakeMicrophone.Value.Trim();
            if (path == "" || !File.Exists(path))
            {
                return;
            }
            foreach (string line in File.ReadAllLines(path))
            {
                string[] f = line.Split('|');
                if (f.Length >= 1 && f[0].Trim() != "" && !f[0].StartsWith("#") && File.Exists(f[0].Trim()))
                {
                    Playlist.Add(new Item { Path = f[0].Trim(), Expected = f.Length > 1 ? f[1].Trim().ToLowerInvariant() : "" });
                }
            }
            Plugin.Log.LogWarning($"[fakemic] TESTING: the microphone is replaced by {Playlist.Count} recorded clips from {path}.");
        }

        internal static void Start(int frequency)
        {
            _frequency = frequency;
            _lastTime = Time.unscaledTime;
            _silenceLeft = Lead;
            _clip = null;
            _sessionClipDone = false;
        }

        /// <summary>Samples since the last read: the current clip, or quiet (a little noise) between clips.</summary>
        internal static float[] Read()
        {
            float now = Time.unscaledTime;
            int count = Mathf.Max(0, (int)((now - _lastTime) * _frequency));
            _lastTime += count / (float)_frequency;
            var output = new float[count];
            for (int i = 0; i < count; i++)
            {
                if (_clip == null)
                {
                    if (_silenceLeft > 0f)
                    {
                        _silenceLeft -= 1f / _frequency;
                        output[i] = (float)(Noise.NextDouble() - 0.5) * 0.002f;
                        continue;
                    }
                    NextClip();
                    if (_clip == null)
                    {
                        continue; // playlist finished: silence
                    }
                }
                output[i] = _clip[_clipPos++];
                if (_clipPos >= _clip.Length)
                {
                    _clip = null;
                    _silenceLeft = Gap;
                    _clipEnded = now;
                    _sessionClipDone = true;
                }
            }
            return output;
        }

        /// <summary>Drops what "arrived" while the listener wasn't reading (as the real microphone path does).</summary>
        internal static void Skip() => Read();

        /// <summary>Push to Talk: the "button" is held from the start of the session until its clip has played, and a moment after.</summary>
        internal static bool Holding => !_sessionClipDone || Time.unscaledTime - _clipEnded < 0.25f;

        private static void NextClip()
        {
            // A clip nobody scored (no speech was detected at all) counts as heard nothing.
            if (CurrentExpected != null)
            {
                Score("");
            }
            _index++;
            if (_index >= Playlist.Count)
            {
                if (_index == Playlist.Count)
                {
                    Plugin.Log.LogWarning($"[fakemic] done: {Correct} correct, {Wrong} wrong, {Missed} missed of {Correct + Wrong + Missed} words; " +
                        $"{FalseActivations} false activations in {Silent} clips that should produce nothing.");
                }
                _clip = null;
                CurrentExpected = null;
                return;
            }
            Item item = Playlist[_index];
            _clip = ReadWav(item.Path, _frequency);
            _clipPos = 0;
            CurrentExpected = item.Expected;
            CurrentFile = Path.GetFileName(Path.GetDirectoryName(item.Path)) + "/" + Path.GetFileName(item.Path);
            if (item.Expected == "")
            {
                Silent++;
            }
        }

        /// <summary>A final result (or a session that ended with nothing) for the clip just played.</summary>
        internal static void Score(string heard)
        {
            if (CurrentExpected == null)
            {
                return;
            }
            string expected = CurrentExpected, h = (heard ?? "").Replace(" ", "");
            if (expected == "")
            {
                if (h != "") FalseActivations++;
            }
            else if (h == "") Missed++;
            else if (h == expected) Correct++;
            else Wrong++;
            Plugin.Log.LogInfo($"[fakemic] {CurrentFile}: said '{expected}', heard '{h}' -> {(expected == "" ? (h == "" ? "ok (nothing)" : "FALSE ACTIVATION") : h == expected ? "correct" : h == "" ? "MISSED" : "WRONG")}");
            CurrentExpected = null; // scored once
        }

        private static float[] ReadWav(string path, int frequency)
        {
            byte[] b = File.ReadAllBytes(path);
            int rate = System.BitConverter.ToInt32(b, 24);
            int data = 12;
            while (data + 8 <= b.Length && System.Text.Encoding.ASCII.GetString(b, data, 4) != "data")
            {
                data += 8 + System.BitConverter.ToInt32(b, data + 4);
            }
            int n = System.BitConverter.ToInt32(b, data + 4) / 2;
            var s = new float[n];
            for (int i = 0; i < n; i++)
            {
                s[i] = System.BitConverter.ToInt16(b, data + 8 + i * 2) / 32768f;
            }
            if (rate == frequency)
            {
                return s;
            }
            var o = new float[(int)((long)n * frequency / rate)];
            for (int i = 0; i < o.Length; i++)
            {
                o[i] = s[(int)((long)i * rate / frequency)];
            }
            return o;
        }
    }
}
