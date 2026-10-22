using System.Threading;
using UnityEngine;

namespace CryptmasterWhisper
{
    /// <summary>
    /// Listens to what the game sends to the speakers (Unity's final mix, on the AudioListener; Cryptmaster uses
    /// plain Unity audio), so speech detection can tell the game's own sound coming back through the microphone
    /// from the player. Keeps a loudness envelope (fast rise, slow fall, to cover the speaker-to-microphone
    /// delay) and, for Testing.FakeEcho, the last two seconds as 16 kHz mono.
    /// </summary>
    internal sealed class GameOutputMonitor : MonoBehaviour
    {
        private const int RingRate = 16000;
        private static readonly float[] Ring = new float[RingRate * 2];
        private static int _ringWrite;      // total samples written (wraps via modulo)
        private static int _outputRate = 48000;
        private static float _level;        // written on the audio thread, read on the main thread
        private static double _decimator;   // fractional position for the 16 kHz copy

        /// <summary>The game's output loudness right now (RMS, with a slow fall).</summary>
        internal static float Level => Volatile.Read(ref _level);

        private static float _nextAttach;

        /// <summary>Called every frame: keeps a monitor on the current AudioListener (scenes replace it).</summary>
        internal static void Maintain()
        {
            if (Time.unscaledTime < _nextAttach)
            {
                return;
            }
            _nextAttach = Time.unscaledTime + 2f;
            AudioListener listener = FindObjectOfType<AudioListener>();
            if (listener && !listener.GetComponent<GameOutputMonitor>())
            {
                _outputRate = AudioSettings.outputSampleRate;
                listener.gameObject.AddComponent<GameOutputMonitor>();
                Plugin.Log.LogInfo($"Whisper: listening to the game's output ({_outputRate} Hz) for echo detection.");
            }
        }

        // Audio thread: data is the final mix (interleaved); it's read, never changed.
        private void OnAudioFilterRead(float[] data, int channels)
        {
            if (channels <= 0 || data.Length == 0)
            {
                return;
            }
            int frames = data.Length / channels;
            double sum = 0;
            double step = (double)_outputRate / RingRate;
            for (int f = 0; f < frames; f++)
            {
                float mono = 0f;
                for (int c = 0; c < channels; c++)
                {
                    mono += data[f * channels + c];
                }
                mono /= channels;
                sum += mono * mono;
                _decimator += 1.0;
                if (_decimator >= step)
                {
                    _decimator -= step;
                    Ring[_ringWrite % Ring.Length] = mono;
                    _ringWrite++;
                }
            }
            float rms = Mathf.Sqrt((float)(sum / frames));
            float previous = Volatile.Read(ref _level);
            // Rises at once, falls over roughly a third of a second (blocks are ~20 ms).
            float next = rms > previous ? rms : previous + (rms - previous) * 0.06f;
            Volatile.Write(ref _level, next);
        }

        /// <summary>Testing.FakeEcho: the game's output from delaySeconds ago, 16 kHz mono, for count samples
        /// ending now (the fake microphone adds it, as a room would).</summary>
        internal static void ReadDelayed(float[] into, int count, float delaySeconds, float gain)
        {
            int end = Volatile.Read(ref _ringWrite) - (int)(delaySeconds * RingRate);
            for (int i = 0; i < count; i++)
            {
                int index = end - count + i;
                if (index >= 0 && index > Volatile.Read(ref _ringWrite) - Ring.Length)
                {
                    into[i] += Ring[index % Ring.Length] * gain;
                }
            }
        }
    }
}
