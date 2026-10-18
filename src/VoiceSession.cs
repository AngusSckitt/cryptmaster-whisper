using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Threading.Tasks;
using UnityEngine;

namespace CryptmasterWhisper
{
    /// <summary>
    /// One press of the game's Ear button in Whisper mode: records the microphone, finds where speech starts
    /// and ends (energy against an adaptive noise floor), shows provisional results while the player speaks,
    /// and hands the final text to the game exactly as Windows Speech Recognition does
    /// (SaveManager.TranslateSpeechText), then ends the session.
    /// </summary>
    internal sealed class VoiceSession : MonoBehaviour
    {
        private enum State { Off, Waiting, Speaking, Finishing }

        internal static VoiceSession Instance { get; private set; }
        internal bool IsActive => _state != State.Off;

        private const int PreferredFrequency = 16000;
        private const float FrameSeconds = 0.02f;
        private const float PreRollSeconds = 0.25f;

        private State _state;
        private SaveManager _save;
        private AudioClip _clip;
        private int _frequency;
        private int _readPosition;
        private readonly List<float> _pending = new();
        private readonly List<float> _utterance = new();
        private readonly Queue<float[]> _preRoll = new();
        private float _noiseFloor;
        private float _sessionStart, _speechStart, _lastVoice, _lastPartial, _speechEnd;
        private bool _busy;          // a recognition is running
        private bool _finalPending;  // speech ended while a preview was running
        private string _language;
        private string _prompt;
        private int _generation;
        private readonly ConcurrentQueue<(int generation, WhisperEngine.Result result)> _results = new();

        private void Awake() => Instance = this;

        /// <summary>Starts listening; false if there is no microphone.</summary>
        internal bool Begin(SaveManager save)
        {
            if (IsActive)
            {
                return true;
            }
            if (Microphone.devices.Length == 0)
            {
                Plugin.Log.LogWarning("Whisper: no microphone found.");
                return false;
            }
            Microphone.GetDeviceCaps(null, out int min, out int max);
            _frequency = max == 0 ? PreferredFrequency : Mathf.Clamp(PreferredFrequency, min, max);
            _clip = Microphone.Start(null, true, 10, _frequency);
            _save = save;
            _state = State.Waiting;
            _generation++;
            _readPosition = 0;
            _pending.Clear();
            _utterance.Clear();
            _preRoll.Clear();
            _noiseFloor = 0.002f;
            _busy = _finalPending = false;
            _sessionStart = Time.unscaledTime;
            _language = GameLanguages.ToWhisper(save.language);
            _prompt = Vocabulary.BuildPrompt(save.myGameManager);
            SetEar(true, Plugin.InitialSilenceSeconds.Value);
            // Load the model in the background now, so the first utterance doesn't wait for it.
            string model = WhisperEngine.ModelFor(_language);
            Task.Run(() => WhisperEngine.Get(model));
            return true;
        }

        internal void End()
        {
            if (!IsActive)
            {
                return;
            }
            Microphone.End(null);
            SetEar(false, 0f);
            _state = State.Off;
            _save = null;
            _clip = null;
            _generation++; // results still being computed are dropped
        }

        private void SetEar(bool listening, float seconds)
        {
            _save.isDictationActive = listening;
            _save.isHighlightingEar = listening;
            _save.startCurrTimeBegin = Time.unscaledTime;
            _save.speechCurrTime = Time.unscaledTime;
            _save.speechLastEndTime = Time.unscaledTime + seconds;
            SetEarColour(0.5f);
        }

        private void SetEarColour(float value)
        {
            if (_save && _save.myGameManager && _save.myGameManager.myMenuManager)
            {
                _save.myGameManager.myMenuManager.speechBarColor = value;
            }
        }

        private void Update()
        {
            DeliverResults();
            if (!IsActive)
            {
                return;
            }
            ReadMicrophone();
            float now = Time.unscaledTime;
            switch (_state)
            {
                case State.Waiting when now - _sessionStart > Plugin.InitialSilenceSeconds.Value:
                    Plugin.Log.LogInfo("Whisper: no speech heard.");
                    _save.CloseDictationEngine(_doesDispose: false);
                    break;
                case State.Speaking when now - _lastVoice >= Plugin.EndSilenceSeconds.Value || now - _speechStart >= Plugin.MaxUtteranceSeconds.Value:
                    _state = State.Finishing;
                    _speechEnd = now;
                    Microphone.End(null); // nothing more to hear in this session
                    if (_busy)
                    {
                        _finalPending = true;
                    }
                    else
                    {
                        Recognise(isFinal: true);
                    }
                    break;
                case State.Speaking when !_busy && Plugin.PartialIntervalSeconds.Value > 0f
                    && now - _lastPartial >= Plugin.PartialIntervalSeconds.Value && now - _speechStart > 0.3f:
                    _lastPartial = now;
                    Recognise(isFinal: false);
                    break;
            }
        }

        private void ReadMicrophone()
        {
            if (_clip == null || _state == State.Finishing)
            {
                return;
            }
            int position = Microphone.GetPosition(null);
            if (position == _readPosition)
            {
                return;
            }
            int count = position > _readPosition ? position - _readPosition : _clip.samples - _readPosition + position;
            var buffer = new float[count];
            if (position > _readPosition)
            {
                _clip.GetData(buffer, _readPosition);
            }
            else
            {
                var tail = new float[_clip.samples - _readPosition];
                _clip.GetData(tail, _readPosition);
                tail.CopyTo(buffer, 0);
                if (position > 0)
                {
                    var head = new float[position];
                    _clip.GetData(head, 0);
                    head.CopyTo(buffer, tail.Length);
                }
            }
            _readPosition = position;
            _pending.AddRange(buffer);

            int frameLength = Mathf.RoundToInt(_frequency * FrameSeconds);
            while (_pending.Count >= frameLength && _state != State.Finishing)
            {
                float[] frame = _pending.GetRange(0, frameLength).ToArray();
                _pending.RemoveRange(0, frameLength);
                ProcessFrame(frame);
            }
        }

        private void ProcessFrame(float[] frame)
        {
            float sum = 0f;
            foreach (float s in frame)
            {
                sum += s * s;
            }
            float rms = Mathf.Sqrt(sum / frame.Length);
            bool voiced = rms > Mathf.Max(_noiseFloor * Plugin.VoiceThreshold.Value, 0.01f);
            float now = Time.unscaledTime;
            if (!voiced)
            {
                // Follow the background noise slowly, so speech doesn't raise it.
                _noiseFloor = Mathf.Lerp(_noiseFloor, rms, 0.05f);
            }

            if (_state == State.Speaking)
            {
                _utterance.AddRange(frame);
                if (voiced)
                {
                    _lastVoice = now;
                    SetEarColour(1f);
                    _save.speechLastEndTime = now + Plugin.EndSilenceSeconds.Value + 0.5f;
                }
                return;
            }
            if (voiced)
            {
                _state = State.Speaking;
                _speechStart = _lastVoice = _lastPartial = now;
                _utterance.Clear();
                foreach (float[] f in _preRoll)
                {
                    _utterance.AddRange(f);
                }
                _utterance.AddRange(frame);
                SetEarColour(1f);
                return;
            }
            _preRoll.Enqueue(frame);
            while (_preRoll.Count > PreRollSeconds / FrameSeconds)
            {
                _preRoll.Dequeue();
            }
        }

        private void Recognise(bool isFinal)
        {
            float[] audio = _utterance.ToArray();
            int frequency = _frequency, generation = _generation;
            string language = _language, prompt = _prompt;
            _busy = true;
            Task.Run(() =>
            {
                WhisperEngine.Result result = null;
                try
                {
                    result = WhisperEngine.Transcribe(audio, frequency, language, prompt, isFinal);
                }
                catch (Exception e)
                {
                    Plugin.Log.LogError($"Whisper: recognition failed: {e}");
                }
                _results.Enqueue((generation, result ?? new WhisperEngine.Result { Text = "", IsFinal = isFinal }));
            });
        }

        private void DeliverResults()
        {
            while (_results.TryDequeue(out var item))
            {
                if (item.generation != _generation || !IsActive)
                {
                    continue; // from an earlier session
                }
                _busy = false;
                WhisperEngine.Result result = item.result;
                string text = Vocabulary.Clean(result.Text, _save);
                if (Plugin.CompareLog.Value)
                {
                    string latency = result.IsFinal ? $", {(Time.unscaledTime - _speechEnd) * 1000f:0} ms after speech ended" : "";
                    Plugin.Log.LogInfo($"[voice] Whisper {(result.IsFinal ? "final" : "partial")}: '{result.Text.Trim()}' -> '{text}' ({result.AudioSeconds:0.0} s audio, {result.InferenceMs} ms inference{latency}, {_language})");
                }
                if (text != "")
                {
                    SetEarColour(1f);
                    _save.TranslateSpeechText(text, result.IsFinal);
                }
                if (result.IsFinal)
                {
                    _save.CloseDictationEngine(_doesDispose: false);
                }
                else if (_finalPending)
                {
                    _finalPending = false;
                    Recognise(isFinal: true);
                }
            }
        }

        private void OnApplicationQuit() => End();
    }
}
