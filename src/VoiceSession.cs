using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Threading.Tasks;
using UnityEngine;

namespace CryptmasterWhisper
{
    /// <summary>
    /// One press of the game's Ear button. In Whisper mode: records the microphone, finds the utterance
    /// (Automatic: energy against an adaptive noise floor; PushToTalk: while the button is held), shows
    /// provisional results while the player speaks, and hands the final text to the game exactly as Windows
    /// Speech Recognition does (SaveManager.TranslateSpeechText), then ends the session. In Windows mode with
    /// Testing.RecordSessions on, only records alongside the Windows recogniser, for replaying tests.
    /// </summary>
    internal sealed class VoiceSession : MonoBehaviour
    {
        private enum State { Off, Waiting, Speaking, Finishing, RecordOnly }

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
        private readonly List<float> _sessionAudio = new();
        private readonly Queue<float[]> _preRoll = new();
        private float _noiseFloor;
        private float _sessionStart, _speechStart, _lastVoice, _lastPartial, _speechEnd;
        private bool _busy;          // a recognition is running
        private bool _finalPending;  // speech ended while a preview was running
        private bool _pushToTalk;
        private string _language;
        private string _model;
        private string _prompt;
        private int _generation;
        private readonly ConcurrentQueue<(int generation, WhisperEngine.Result result)> _results = new();
        private SessionRecorder.Entry _record;

        private void Awake() => Instance = this;

        /// <summary>Starts a Whisper session; false if there is no microphone.</summary>
        internal bool Begin(SaveManager save) => Start(save, recordOnly: false);

        /// <summary>Records alongside a Windows Speech Recognition session (testing only).</summary>
        internal void BeginRecordOnly(SaveManager save) => Start(save, recordOnly: true);

        private bool Start(SaveManager save, bool recordOnly)
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
            int bufferSeconds = Mathf.CeilToInt(Mathf.Max(Plugin.MaxHoldSeconds.Value, Plugin.MaxUtteranceSeconds.Value, Plugin.InitialSilenceSeconds.Value)) + 5;
            _clip = Microphone.Start(null, true, Mathf.Clamp(bufferSeconds, 10, 60), _frequency);
            _save = save;
            _generation++;
            _readPosition = 0;
            _pending.Clear();
            _utterance.Clear();
            _sessionAudio.Clear();
            _preRoll.Clear();
            _noiseFloor = 0.002f;
            _busy = _finalPending = false;
            _sessionStart = _speechStart = _lastVoice = _lastPartial = Time.unscaledTime;
            _language = GameLanguages.ToWhisper(save.language);
            _model = WhisperEngine.ModelFor(save.language, _language);
            _record = Plugin.RecordSessions.Value ? new SessionRecorder.Entry
            {
                Engine = recordOnly ? Plugin.EngineWindows : Plugin.EngineWhisper,
                Mode = recordOnly ? "" : Plugin.Listening.Value,
                GameLanguage = save.language,
                Started = DateTime.Now,
            } : null;
            if (recordOnly)
            {
                _state = State.RecordOnly;
                return true;
            }
            _pushToTalk = Plugin.PushToTalk;
            _prompt = Vocabulary.BuildPrompt(save.myGameManager);
            // Push to talk: everything while the button is held is the utterance.
            _state = _pushToTalk ? State.Speaking : State.Waiting;
            SetEar(true, _pushToTalk ? Plugin.MaxHoldSeconds.Value : Plugin.InitialSilenceSeconds.Value);
            // Load the model in the background now, so the first utterance doesn't wait for it.
            string model = _model;
            Task.Run(() => WhisperEngine.Get(model));
            return true;
        }

        internal void End()
        {
            if (!IsActive)
            {
                return;
            }
            bool recordOnly = _state == State.RecordOnly;
            if (recordOnly)
            {
                ReadMicrophone(); // the last few frames
            }
            Microphone.End(null);
            if (_record != null)
            {
                _record.Seconds = (Time.unscaledTime - _sessionStart);
                SessionRecorder.Save(_record, _sessionAudio.ToArray(), _frequency);
                _record = null;
            }
            if (!recordOnly)
            {
                SetEar(false, 0f);
            }
            _state = State.Off;
            _save = null;
            _clip = null;
            _generation++; // results still being computed are dropped
        }

        /// <summary>Windows Speech Recognition's text for the session being recorded.</summary>
        internal void NoteWindowsText(string text, bool isFinal)
        {
            if (_record == null)
            {
                return;
            }
            if (isFinal)
            {
                _record.Final = string.IsNullOrEmpty(_record.Final) ? text : _record.Final + " | " + text;
                _record.LatencyMs = (int)((Time.unscaledTime - _sessionStart) * 1000f);
            }
            else
            {
                _record.Partials.Add(text);
            }
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

        private bool EarButtonHeld()
        {
            GameManager game = _save ? _save.myGameManager : null;
            if (!game)
            {
                return false;
            }
            if (game.myTestBot && game.myTestBot.useRewired && game.rewiredControl != null)
            {
                return game.rewiredControl.GetButton("hear");
            }
            return Input.GetKey(KeyCode.LeftControl) || Input.GetKey(KeyCode.RightControl);
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
                case State.Speaking when _pushToTalk ? !EarButtonHeld() || now - _speechStart >= Plugin.MaxHoldSeconds.Value
                                                     : now - _lastVoice >= Plugin.EndSilenceSeconds.Value || now - _speechStart >= Plugin.MaxUtteranceSeconds.Value:
                    FinishUtterance(now);
                    break;
                case State.Speaking when !_busy && Plugin.PartialIntervalSeconds.Value > 0f
                    && now - _lastPartial >= Plugin.PartialIntervalSeconds.Value && now - _speechStart > 0.3f:
                    _lastPartial = now;
                    Recognise(isFinal: false);
                    break;
            }
        }

        private void FinishUtterance(float now)
        {
            _state = State.Finishing;
            _speechEnd = now;
            Microphone.End(null); // nothing more to hear in this session
            if (_utterance.Count < _frequency * 0.15f)
            {
                Plugin.Log.LogInfo("Whisper: too short to recognise.");
                _save.CloseDictationEngine(_doesDispose: false);
            }
            else if (_busy)
            {
                _finalPending = true;
            }
            else
            {
                Recognise(isFinal: true);
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
            if (_record != null)
            {
                _sessionAudio.AddRange(buffer);
            }
            if (_state == State.RecordOnly)
            {
                return;
            }
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
                    if (!_pushToTalk)
                    {
                        _save.speechLastEndTime = now + Plugin.EndSilenceSeconds.Value + 0.5f;
                    }
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
            string language = _language, prompt = _prompt, model = _model;
            _busy = true;
            Task.Run(() =>
            {
                WhisperEngine.Result result = null;
                try
                {
                    result = WhisperEngine.Transcribe(audio, frequency, model, language, prompt, isFinal);
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
                int latency = (int)((Time.unscaledTime - _speechEnd) * 1000f);
                if (Plugin.CompareLog.Value)
                {
                    string after = result.IsFinal ? $", {latency} ms after speech ended" : "";
                    Plugin.Log.LogInfo($"[voice] Whisper {(result.IsFinal ? "final" : "partial")}: '{result.Text.Trim()}' -> '{text}' ({result.AudioSeconds:0.0} s audio, {result.InferenceMs} ms inference{after}, {_language}, {WhisperEngine.BackendName}{(result.NoSpeech > 0 ? $", no-speech {result.NoSpeech:0.00}" : "")})");
                }
                if (_record != null)
                {
                    if (result.IsFinal)
                    {
                        _record.Final = text;
                        _record.Raw = result.Text.Trim();
                        _record.LatencyMs = latency;
                        _record.InferenceMs = (int)result.InferenceMs;
                    }
                    else
                    {
                        _record.Partials.Add(text);
                    }
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
