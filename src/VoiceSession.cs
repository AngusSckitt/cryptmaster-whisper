using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Threading.Tasks;
using UnityEngine;

namespace CryptmasterWhisper
{
    /// <summary>
    /// Whisper listening, in three modes (Listening.Mode):
    /// - Tap to Toggle ("Automatic", like the original game): the Ear button starts a session; speech is found
    ///   by energy against an adaptive noise floor and the session ends when the player stops talking.
    /// - Push to Talk: the utterance is whatever is said while the Ear button is held.
    /// - Voice Activation: always listening while playing (in game, window focused, no menu open, voice input
    ///   on); each detected utterance is recognised on its own. It ignores the microphone while the game's own
    ///   voice is playing (speakers would otherwise feed it back), is stricter about short or uncertain
    ///   results, and the Ear button still starts a normal session at once.
    /// Provisional results feed the game's live preview, and the final text goes to the game exactly where
    /// Windows Speech Recognition's would (SaveManager.TranslateSpeechText). In Windows mode with
    /// Testing.RecordSessions on, this only records alongside the Windows recogniser, for replaying tests.
    /// </summary>
    internal sealed class VoiceSession : MonoBehaviour
    {
        private enum State { Off, Waiting, Speaking, Finishing, RecordOnly }

        internal static VoiceSession Instance { get; private set; }
        internal bool IsActive => _state != State.Off;

        private const int PreferredFrequency = 16000;
        private const float FrameSeconds = 0.02f;
        private const float PreRollSeconds = 0.25f;
        // Voice Activation only: shortest speech worth recognising, and quiet time after the game's own voice.
        private const float MinActivatedSpeech = 0.3f;
        private const float GameVoiceTail = 0.5f;

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
        private float _sessionStart, _speechStart, _lastVoice, _lastPartial, _speechEnd, _gameVoiceUntil;
        private bool _busy;          // a recognition is running
        private bool _finalPending;  // speech ended while a preview was running
        private bool _pushToTalk;
        private bool _continuous;    // a Voice Activation session (stays open between utterances)
        private string _language;
        private string _gameLanguage;
        private string _prompt;
        private int _generation;
        private readonly ConcurrentQueue<(int generation, WhisperEngine.Result result)> _results = new();
        private SessionRecorder.Entry _record;
        private SaveManager _cachedSave;
        private float _nextActivationCheck;

        private void Awake() => Instance = this;

        /// <summary>The Ear button in Whisper mode: a session now (in Voice Activation, the next utterance is
        /// handled as a normal one, with the Ear bar).</summary>
        internal bool Begin(SaveManager save)
        {
            if (IsActive && _continuous && _state == State.Waiting)
            {
                _continuous = false;
                _sessionStart = Time.unscaledTime;
                SetEar(true, Plugin.InitialSilenceSeconds.Value);
                return true;
            }
            return Start(save, recordOnly: false, continuous: false);
        }

        /// <summary>Records alongside a Windows Speech Recognition session (testing only).</summary>
        internal void BeginRecordOnly(SaveManager save) => Start(save, recordOnly: true, continuous: false);

        private bool Start(SaveManager save, bool recordOnly, bool continuous)
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
            _continuous = continuous;
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
            _gameLanguage = save.language;
            // Voice Activation records per utterance (from its onset), the others per session.
            _record = Plugin.RecordSessions.Value && !continuous ? NewRecord(recordOnly) : null;
            if (recordOnly)
            {
                _state = State.RecordOnly;
                return true;
            }
            _pushToTalk = Plugin.PushToTalk && !continuous;
            _prompt = Vocabulary.BuildPrompt(save.myGameManager);
            // Push to talk: everything while the button is held is the utterance.
            _state = _pushToTalk ? State.Speaking : State.Waiting;
            if (!continuous)
            {
                SetEar(true, _pushToTalk ? Plugin.MaxHoldSeconds.Value : Plugin.InitialSilenceSeconds.Value);
            }
            else
            {
                Plugin.Log.LogInfo("Whisper: voice activation listening.");
            }
            // Load the model in the background now, so the first utterance doesn't wait for it.
            string gameLanguage = _gameLanguage, whisperLanguage = _language;
            Task.Run(() => WhisperEngine.Get(WhisperEngine.ModelFor(gameLanguage, whisperLanguage)));
            return true;
        }

        private SessionRecorder.Entry NewRecord(bool recordOnly) => new()
        {
            Engine = recordOnly ? Plugin.EngineWindows : Plugin.EngineWhisper,
            Mode = recordOnly ? "" : Plugin.Listening.Value,
            GameLanguage = _save ? _save.language : "",
            Started = DateTime.Now,
        };

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
            SaveRecord();
            if (!recordOnly)
            {
                SetEar(false, 0f);
            }
            if (_continuous)
            {
                Plugin.Log.LogInfo("Whisper: voice activation paused.");
            }
            _state = State.Off;
            _continuous = false;
            _save = null;
            _clip = null;
            _generation++; // results still being computed are dropped
        }

        private void SaveRecord()
        {
            if (_record != null)
            {
                _record.Seconds = Time.unscaledTime - _sessionStart;
                SessionRecorder.Save(_record, _sessionAudio.ToArray(), _frequency);
                _record = null;
            }
            _sessionAudio.Clear();
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

        // ---- Voice Activation: when to listen ----

        private SaveManager FindSave()
        {
            if (!_cachedSave)
            {
                _cachedSave = FindObjectOfType<SaveManager>();
            }
            return _cachedSave;
        }

        /// <summary>Playing (not in a menu), window focused, voice input on, Whisper selected.</summary>
        private static bool CanListenContinuously(SaveManager save)
        {
            GameManager game = save ? save.myGameManager : null;
            return Plugin.UseWhisper && Plugin.VoiceActivation && game && Application.isFocused
                && save.doesUseSpeech && !save.isSystemBlockingSpeech && game.MainGameState == 1
                && game.myMenuManager && !game.myMenuManager.isOptionsActive;
        }

        /// <summary>The game is speaking (its voice lines), or just stopped: its sound mustn't count as the player's.</summary>
        private bool GameVoicePlaying()
        {
            AudioManager audio = _save && _save.myGameManager ? _save.myGameManager.myAudioManager : null;
            if (audio && ((audio.talkingSource && audio.talkingSource.isPlaying) || (audio.talkingSourceActual && audio.talkingSourceActual.isPlaying)))
            {
                _gameVoiceUntil = Time.unscaledTime + GameVoiceTail;
            }
            return Time.unscaledTime < _gameVoiceUntil;
        }

        private void ManageVoiceActivation()
        {
            if (Time.unscaledTime < _nextActivationCheck)
            {
                return;
            }
            _nextActivationCheck = Time.unscaledTime + 0.25f;
            SaveManager save = FindSave();
            bool can = CanListenContinuously(save);
            if (can && !IsActive)
            {
                Start(save, recordOnly: false, continuous: true);
            }
            else if (!can && IsActive && _continuous && _state == State.Waiting)
            {
                End();
            }
        }

        /// <summary>Voice Activation: back to listening for the next utterance, microphone still open.</summary>
        private void ResetToWaiting()
        {
            SaveRecord();
            SetEar(false, 0f);
            _state = State.Waiting;
            _utterance.Clear();
            _pending.Clear();
            _preRoll.Clear();
            _busy = _finalPending = false;
            _generation++;
            _readPosition = _clip ? Microphone.GetPosition(null) : 0; // skip what was heard while recognising
        }

        // ---- Every frame ----

        private void Update()
        {
            DeliverResults();
            ManageVoiceActivation();
            if (!IsActive)
            {
                return;
            }
            ReadMicrophone();
            float now = Time.unscaledTime;
            switch (_state)
            {
                case State.Waiting when !_continuous && now - _sessionStart > Plugin.InitialSilenceSeconds.Value:
                    Plugin.Log.LogInfo("Whisper: no speech heard.");
                    _save.CloseDictationEngine(_doesDispose: false);
                    break;
                case State.Speaking when _pushToTalk ? !EarButtonHeld() || now - _speechStart >= Plugin.MaxHoldSeconds.Value
                                                     : now - _lastVoice >= Plugin.EndSilenceSeconds.Value || now - _speechStart >= Plugin.MaxUtteranceSeconds.Value:
                    FinishUtterance(now);
                    break;
                // Previews; in Voice Activation only once it's clearly speech, so noises don't type anything.
                case State.Speaking when !_busy && Plugin.PartialIntervalSeconds.Value > 0f
                    && now - _lastPartial >= Plugin.PartialIntervalSeconds.Value && now - _speechStart > (_continuous ? 0.5f : 0.3f):
                    _lastPartial = now;
                    Recognise(isFinal: false);
                    break;
            }
        }

        private void FinishUtterance(float now)
        {
            _state = State.Finishing;
            _speechEnd = now;
            if (!_continuous)
            {
                Microphone.End(null); // nothing more to hear in this session
            }
            float minimum = _continuous ? MinActivatedSpeech : 0.15f;
            if (_utterance.Count < _frequency * minimum)
            {
                Plugin.Log.LogInfo("Whisper: too short to recognise.");
                if (_continuous)
                {
                    ResetToWaiting();
                }
                else
                {
                    _save.CloseDictationEngine(_doesDispose: false);
                }
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

            // Voice Activation: while the game itself is talking, nothing counts (and a started utterance is dropped).
            if (_continuous && GameVoicePlaying())
            {
                if (_state == State.Speaking)
                {
                    Plugin.Log.LogInfo("Whisper: dropped what was heard while the game was talking.");
                    ResetToWaiting();
                }
                return;
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
                if (_continuous)
                {
                    // Show the Ear bar for this utterance, like a session started by the button.
                    SetEar(true, Plugin.EndSilenceSeconds.Value + 0.5f);
                    if (Plugin.RecordSessions.Value)
                    {
                        _record = NewRecord(recordOnly: false);
                        _sessionStart = now;
                        _sessionAudio.Clear();
                        _sessionAudio.AddRange(_utterance);
                    }
                }
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
            string language = _language, prompt = _prompt, gameLanguage = _gameLanguage;
            _busy = true;
            Task.Run(() =>
            {
                WhisperEngine.Result result = null;
                try
                {
                    result = WhisperEngine.Transcribe(audio, frequency, gameLanguage, language, prompt, isFinal);
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
                // Voice Activation: nobody pressed anything, so be stricter about what counts as a word.
                if (_continuous && text != "" && (text.Replace(" ", "").Length < 2 || result.NoSpeech > 0.6f))
                {
                    Plugin.Log.LogInfo($"Whisper: voice activation ignored '{result.Text.Trim()}' (too short or likely not speech).");
                    text = "";
                }
                int latency = (int)((Time.unscaledTime - _speechEnd) * 1000f);
                if (Plugin.CompareLog.Value)
                {
                    string after = result.IsFinal ? $", {latency} ms after speech ended" : "";
                    Plugin.Log.LogInfo($"[voice] Whisper {(result.IsFinal ? "final" : "partial")}{(_continuous ? " (voice activation)" : "")}: '{result.Text.Trim()}' -> '{text}' ({result.AudioSeconds:0.0} s audio, {result.InferenceMs} ms inference{after}, {_language}, {WhisperEngine.BackendName}{(result.NoSpeech > 0 ? $", no-speech {result.NoSpeech:0.00}" : "")})");
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
                    WhisperEngine.RecordLatency(result.InferenceMs);
                    if (_continuous)
                    {
                        ResetToWaiting();
                    }
                    else
                    {
                        _save.CloseDictationEngine(_doesDispose: false);
                    }
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
