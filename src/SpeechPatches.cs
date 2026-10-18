using HarmonyLib;
using UnityEngine;
using UnityEngine.Windows.Speech;

namespace CryptmasterWhisper
{
    // The game's voice input (SaveManager): the Ear button calls StartSpeech -> StartDictationEngine, which
    // starts a Windows DictationRecognizer; its hypotheses and results go to TranslateSpeechText (known
    // mishearings -> TextManager.UpdateSpeechPrediction, which types the letters and submits).
    // CloseDictationEngine ends it. In Whisper mode both are replaced by VoiceSession; everything after
    // TranslateSpeechText stays the game's own.

    [HarmonyPatch(typeof(SaveManager), "Start")]
    internal static class SpeechSupportPatch
    {
        // The game turns voice input off where WSR isn't available; Whisper runs anywhere with a microphone.
        private static void Postfix(SaveManager __instance) => Refresh(__instance);

        internal static void Refresh(SaveManager save)
        {
            if (save)
            {
                save.doesSystemSupportSpeech = Plugin.UseWhisper ? Microphone.devices.Length > 0 : PhraseRecognitionSystem.isSupported;
            }
        }
    }

    [HarmonyPatch(typeof(SaveManager), nameof(SaveManager.StartDictationEngine))]
    internal static class StartDictationPatch
    {
        private static bool Prefix(SaveManager __instance)
        {
            if (!Plugin.UseWhisper)
            {
                SpeechCompare.SessionStarted();
                return true;
            }
            if (!VoiceSession.Instance.Begin(__instance))
            {
                __instance.isDictationActive = false;
            }
            return false;
        }
    }

    [HarmonyPatch(typeof(SaveManager), nameof(SaveManager.CloseDictationEngine))]
    internal static class CloseDictationPatch
    {
        private static bool Prefix(SaveManager __instance)
        {
            VoiceSession.Instance.End();
            // Let the original close a Windows recogniser left from before switching recognisers.
            if (__instance.dictationRecognizer != null)
            {
                return true;
            }
            __instance.isDictationActive = false;
            __instance.isHighlightingEar = false;
            if (__instance.myGameManager && __instance.myGameManager.myMenuManager)
            {
                __instance.myGameManager.myMenuManager.speechBarColor = 0.5f;
            }
            return false;
        }
    }

    // ---- Comparison log for Windows Speech Recognition (same format as Whisper's) ----

    internal static class SpeechCompare
    {
        private static float _start;

        internal static void SessionStarted() => _start = Time.unscaledTime;

        internal static void Log(string kind, string text)
        {
            if (Plugin.CompareLog.Value)
            {
                Plugin.Log.LogInfo($"[voice] Windows {kind}: '{text}' ({(Time.unscaledTime - _start) * 1000f:0} ms after the Ear button)");
            }
        }
    }

    [HarmonyPatch(typeof(SaveManager), nameof(SaveManager.DictationRecognizer_OnDictationHypothesis))]
    internal static class WindowsHypothesisLog
    {
        private static void Prefix(string _text) => SpeechCompare.Log("partial", _text);
    }

    [HarmonyPatch(typeof(SaveManager), nameof(SaveManager.DictationRecognizer_OnDictationResult))]
    internal static class WindowsResultLog
    {
        private static void Prefix(string _text) => SpeechCompare.Log("final", _text);
    }
}
