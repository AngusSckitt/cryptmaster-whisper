using System.IO;
using BepInEx;
using BepInEx.Configuration;
using BepInEx.Logging;
using HarmonyLib;
using UnityEngine;

namespace CryptmasterWhisper
{
    /// <summary>
    /// Lets Cryptmaster's voice input use Whisper, the speech recogniser that ships with the game but was
    /// never wired in, as an alternative to Windows Speech Recognition (WSR, the game's native recogniser and
    /// the default). Independent of any localisation mod: the game's language code picks Whisper's language.
    /// </summary>
    [BepInPlugin(PluginGuid, PluginName, PluginVersion)]
    public class Plugin : BaseUnityPlugin
    {
        public const string PluginGuid = "cryptmaster.whisper";
        public const string PluginName = "Cryptmaster Whisper";
        public const string PluginVersion = "0.1.0";

        internal static ManualLogSource Log;
        internal static string Folder;

        internal static ConfigEntry<string> Engine;
        internal static ConfigEntry<string> ModelEnglish;
        internal static ConfigEntry<string> ModelMultilingual;
        internal static ConfigEntry<string> LanguageMap;
        internal static ConfigEntry<string> ModelPerLanguage;
        internal static ConfigEntry<int> Threads;
        internal static ConfigEntry<float> InitialSilenceSeconds;
        internal static ConfigEntry<float> EndSilenceSeconds;
        internal static ConfigEntry<float> MaxUtteranceSeconds;
        internal static ConfigEntry<float> PartialIntervalSeconds;
        internal static ConfigEntry<float> VoiceThreshold;
        internal static ConfigEntry<int> MinAudioContext;
        internal static ConfigEntry<bool> VocabularyPrompt;
        internal static ConfigEntry<bool> CompareLog;
        internal static ConfigEntry<string> Listening;
        internal static ConfigEntry<float> MaxHoldSeconds;
        internal static ConfigEntry<bool> RecordSessions;

        internal static bool UseWhisper => Engine.Value == EngineWhisper;
        internal static bool PushToTalk => Listening.Value == ListenPushToTalk;
        internal const string EngineWindows = "Windows";
        internal const string EngineWhisper = "Whisper";
        internal const string ListenAutomatic = "Automatic";
        internal const string ListenPushToTalk = "PushToTalk";

        private void Awake()
        {
            if (Log != null)
            {
                return; // the game can create the BepInEx manager twice
            }
            Log = Logger;
            Folder = Path.GetDirectoryName(Info.Location);

            Engine = Config.Bind("General", "Engine", EngineWindows,
                new ConfigDescription("Voice recogniser: Windows (default; vanilla: the game's own Windows Speech Recognition, the one to go back to if Whisper misbehaves) or Whisper.",
                    new AcceptableValueList<string>(EngineWindows, EngineWhisper)));
            ModelEnglish = Config.Bind("Model", "English", "ggml-model-whisper-tiny.en-q8_0.bin",
                "Model for English. A file name in this plugin's models folder or the game's StreamingAssets\\Whisper folder, or a full path.");
            ModelMultilingual = Config.Bind("Model", "Multilingual", "ggml-tiny.bin",
                "Model for every other language (must be a multilingual model). Larger models (e.g. ggml-base.bin) placed in the models folder are slower but may recognise better.");
            ModelPerLanguage = Config.Bind("Model", "PerLanguage", "",
                "Model per game language code, overriding the two above, e.g. 'POR=ggml-small-q5_1.bin;SPA=ggml-base-q5_1.bin'. Works with the game's own languages and any localisation mod's code.");
            LanguageMap = Config.Bind("Model", "LanguageMap", "",
                "Extra game-language-code=whisper-language pairs, e.g. 'DEU=de;FRA=fr'. Common codes are built in.");
            Threads = Config.Bind("Performance", "Threads", 0, "CPU threads for recognition (0 = automatic: one less than the number of cores, at most 4).");
            InitialSilenceSeconds = Config.Bind("Listening", "InitialSilenceSeconds", 4f, "How long to wait for speech after pressing the Ear button.");
            EndSilenceSeconds = Config.Bind("Listening", "EndSilenceSeconds", 0.6f, "Silence that ends an utterance.");
            MaxUtteranceSeconds = Config.Bind("Listening", "MaxUtteranceSeconds", 6f, "Longest utterance; recognition starts when it is reached.");
            PartialIntervalSeconds = Config.Bind("Listening", "PartialIntervalSeconds", 0.4f, "How often to show a provisional result while speaking (0 = never).");
            VoiceThreshold = Config.Bind("Listening", "VoiceThreshold", 3f, "How much louder than the background noise counts as speech.");
            MinAudioContext = Config.Bind("Advanced", "MinAudioContext", 256,
                "Smallest encoder window (50 per second of audio; Whisper's default is 1500 = 30 s). Smaller is faster; too small can hurt recognition.");
            VocabularyPrompt = Config.Bind("Advanced", "VocabularyPrompt", true, "Hint Whisper with the party's names and current skill words.");
            CompareLog = Config.Bind("Advanced", "CompareLog", true, "Log every recognised utterance with timings, for both recognisers, to compare them.");
            Listening = Config.Bind("Listening", "Mode", ListenAutomatic,
                new ConfigDescription("Whisper only. Automatic: press the Ear button, speak, and the end of speech is detected. PushToTalk: hold the Ear button while speaking; nothing is heard otherwise (useful in noisy rooms).",
                    new AcceptableValueList<string>(ListenAutomatic, ListenPushToTalk)));
            MaxHoldSeconds = Config.Bind("Listening", "MaxHoldSeconds", 10f, "Push to talk: longest recording while the button is held.");
            RecordSessions = Config.Bind("Testing", "RecordSessions", false,
                "Saves every Ear-button session (either recogniser) as a WAV plus what was recognised, in this plugin's recordings folder, so tests can be replayed through other models (tools\\replay). Recordings stay on this computer.");

            Texts.Load(Path.Combine(Folder, "textos"));
            new Harmony(PluginGuid).PatchAll(typeof(Plugin).Assembly);

            // The game destroys the BepInEx manager object at boot; run on our own persistent object.
            var host = new GameObject(PluginGuid) { hideFlags = HideFlags.HideAndDontSave };
            DontDestroyOnLoad(host);
            host.AddComponent<VoiceSession>();

            Log.LogInfo($"{PluginName} {PluginVersion} loaded; recogniser: {Engine.Value}. {WhisperEngine.SystemInfo()}");
        }
    }
}
