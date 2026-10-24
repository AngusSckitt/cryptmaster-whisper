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
        public const string PluginVersion = "0.9.1";

        internal static ManualLogSource Log;
        internal static string Folder;

        internal static ConfigEntry<string> Engine;
        internal static ConfigEntry<string> ModelEnglish;
        internal static ConfigEntry<string> ModelMultilingual;
        internal static ConfigEntry<string> ModelEnglishCpu;
        internal static ConfigEntry<string> ModelMultilingualCpu;
        internal static ConfigEntry<string> LanguageMap;
        internal static ConfigEntry<string> ModelPerLanguage;
        internal static ConfigEntry<int> Threads;
        internal static ConfigEntry<string> Backend;
        internal static ConfigEntry<int> VulkanGpuMs, CudaGpuMs, CpuMs;
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
        internal static ConfigEntry<string> FakeMicrophone;
        internal static ConfigEntry<string> SpeechDetector;
        internal static ConfigEntry<float> SpeechThreshold;
        internal static ConfigEntry<bool> SpeechGate;
        internal static ConfigEntry<bool> EchoGate;
        internal static ConfigEntry<float> EchoMargin, FakeEcho, FakeEchoDelay;
        internal static ConfigEntry<string> SimulateGpuFailure;

        internal static bool UseWhisper => Engine.Value == EngineWhisper;
        internal static bool PushToTalk => Listening.Value == ListenPushToTalk;
        internal static bool VoiceActivation => Listening.Value == ListenVoiceActivation;
        internal const string EngineWindows = "Windows";
        internal const string EngineWhisper = "Whisper";
        internal const string BackendAuto = "Auto", BackendVulkan = "Vulkan", BackendCuda = "CUDA", BackendCpu = "CPU", BackendGame = "Game";
        internal const string DetectorSilero = "Silero", DetectorEnergy = "Energy";
        internal const string ListenAutomatic = "Automatic";
        internal const string ListenPushToTalk = "PushToTalk";
        internal const string ListenVoiceActivation = "VoiceActivation";
        internal const string FailureNone = "None", FailureErrors = "Errors", FailureCrash = "Crash";

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
            ModelEnglishCpu = Config.Bind("Model", "EnglishCpu", "", "Model for English when recognition runs on the CPU (no GPU, or the GPU failed). Empty = the same as English.");
            ModelMultilingualCpu = Config.Bind("Model", "MultilingualCpu", "", "Model for other languages when recognition runs on the CPU. Empty = the same as Multilingual. The installer's benchmark fills both.");
            LanguageMap = Config.Bind("Model", "LanguageMap", "",
                "Extra game-language-code=whisper-language pairs, e.g. 'DEU=de;FRA=fr'. Common codes are built in.");
            Backend = Config.Bind("Performance", "Backend", BackendAuto,
                new ConfigDescription("Auto: the GPU-capable whisper.cpp in native\\vulkan if installed (AMD, Intel or NVIDIA GPU; CPU otherwise), else the game's own library. CUDA: native\\cuda (NVIDIA, optional install). CPU: native\\vulkan without the GPU. Game: always the game's own library (CPU).",
                    new AcceptableValueList<string>(BackendAuto, BackendVulkan, BackendCuda, BackendCpu, BackendGame)));
            VulkanGpuMs = Config.Bind("Benchmark", "VulkanGpuMs", -1, "Measured time per word on the GPU with Vulkan (written by the installer, refreshed from real use; -1 = unknown). Shown in the Options menu; Auto uses CUDA only if it's more than 10% faster than this.");
            CudaGpuMs = Config.Bind("Benchmark", "CudaGpuMs", -1, "Measured time per word on the GPU with CUDA (-1 = unknown).");
            CpuMs = Config.Bind("Benchmark", "CpuMs", -1, "Measured time per word on the CPU (-1 = unknown).");
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
                new ConfigDescription("Whisper only. Automatic (Tap to Toggle, like the original game): press the Ear button, speak, and the end of speech is detected. PushToTalk: hold the Ear button while speaking; nothing is heard otherwise (useful in noisy rooms). VoiceActivation: always listening while playing, no button needed; ignores the microphone while the game's own voice plays; headphones recommended.",
                    new AcceptableValueList<string>(ListenAutomatic, ListenPushToTalk, ListenVoiceActivation)));
            SpeechDetector = Config.Bind("Listening", "SpeechDetector", DetectorSilero,
                new ConfigDescription("How speech is told apart from silence and noise. Silero: a small speech-detection network (vad folder; needs the native whisper.cpp build), which ignores most noise, music and typing. Energy: loudness against the background (always available; the fallback).",
                    new AcceptableValueList<string>(DetectorSilero, DetectorEnergy)));
            SpeechThreshold = Config.Bind("Listening", "SpeechThreshold", 0.5f, "Silero: speech probability (0-1) that starts an utterance; it continues while above 70% of this. Higher ignores more noise but may miss soft speech.");
            SpeechGate = Config.Bind("Listening", "SpeechGate", true, "Silero: don't send audio to Whisper unless it found at least 0.15 s of speech in it (Whisper otherwise invents words for noise).");
            EchoGate = Config.Bind("Listening", "EchoGate", true, "While the game is loud, speech only starts if the microphone is clearly louder than the game's own sound coming back through it (learnt automatically; does nothing with headphones). Not used in Push to Talk.");
            EchoMargin = Config.Bind("Advanced", "EchoMargin", 2f, "How much louder than the expected echo of the game the microphone must be for speech to start.");
            MaxHoldSeconds = Config.Bind("Listening", "MaxHoldSeconds", 10f, "Push to talk: longest recording while the button is held.");
            RecordSessions = Config.Bind("Testing", "RecordSessions", false,
                "Saves every Ear-button session (either recogniser) as a WAV plus what was recognised, in this plugin's recordings folder, so tests can be replayed through other models (tools\\replay). Recordings stay on this computer.");

            FakeMicrophone = Config.Bind("Testing", "FakeMicrophone", "", "TESTING ONLY. A playlist file (path|expected word per line) of recordings of real people, fed in place of the microphone. Leave empty to use the microphone.");
            FakeEcho = Config.Bind("Testing", "FakeEcho", 0f, "TESTING ONLY, with FakeMicrophone: mixes the game's own output into the fake microphone at this gain, as speakers would (0 = off).");
            FakeEchoDelay = Config.Bind("Testing", "FakeEchoDelay", 0.12f, "TESTING ONLY: delay of the fake echo, in seconds.");
            SimulateGpuFailure = Config.Bind("Testing", "SimulateGpuFailure", FailureNone,
                new ConfigDescription("TESTING ONLY. Makes recognition on the GPU fail, to test the fallbacks. Errors: every GPU recognition fails (after 3 in a row the session moves to the CPU). Crash: the first GPU recognition ends the game the way a GPU driver reset does (the next launch skips that backend once). Set it back to None afterwards.",
                    new AcceptableValueList<string>(FailureNone, FailureErrors, FailureCrash)));
            CryptmasterWhisper.FakeMicrophone.Load();
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
