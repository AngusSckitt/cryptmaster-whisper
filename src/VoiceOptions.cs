using System.Collections.Generic;
using System.Linq;
using HarmonyLib;
using TMPro;
using UnityEngine;

namespace CryptmasterWhisper
{
    /// <summary>
    /// Options > Voice rows, cloned from the game's own: the recogniser (Windows Speech Recognition, the
    /// default, or Whisper), and while Whisper is selected the hardware/API (with measured times per word and a
    /// GPU/CPU note under it) and the listening mode. Values live in this mod's config, never in the game's
    /// options file. Texts come from textos\ ([MENUOPTION] lines and the whisperhint* sentences).
    /// </summary>
    internal static class VoiceOptions
    {
        internal const string EngineRow = "[SPEECHENGINE]";
        internal const string BackendRow = "[SPEECHBACKEND]";
        internal const string ListenRow = "[SPEECHLISTEN]";

        private static GameOption _engine, _backend, _listen;
        private static TextMeshProUGUI _hint, _listenHint;
        private static readonly List<string> BackendKeys = new();

        internal static bool IsOurs(GameOption option) => option && (option.optionName == EngineRow || option.optionName == BackendRow || option.optionName == ListenRow);

        // ---- Building the rows ----

        private static MenuManager.OptionsList VoiceList(MenuManager menu)
        {
            return menu.allOptionsLists.FirstOrDefault(l => l.allMenuOptions.Any(o => o && o.optionName == "[SPEECHON]"));
        }

        /// <summary>Clones the rows once, next to the game's Voice Input row.</summary>
        internal static void Build(MenuManager menu)
        {
            if (_engine || !menu)
            {
                return;
            }
            MenuManager.OptionsList list = VoiceList(menu);
            if (list == null)
            {
                Plugin.Log.LogWarning("Options: the Voice tab wasn't found; recogniser options stay in the config only.");
                return;
            }
            GameOption speechOn = list.allMenuOptions.First(o => o.optionName == "[SPEECHON]");
            GameOption template = list.allMenuOptions.FirstOrDefault(o => o.optionName == "[SPEECHAUTO]" && o.mySlider) ?? speechOn;
            // The hardware row needs a line of fine print: clone a row that has a warning text, if any.
            GameOption withNote = list.allMenuOptions.FirstOrDefault(o => o.myWarningText && o.mySlider) ?? template;
            int at = list.allMenuOptions.IndexOf(speechOn);
            _engine = Clone(template, EngineRow, list, at + 1);
            _backend = Clone(withNote, BackendRow, list, at + 2);
            _listen = Clone(withNote, ListenRow, list, at + 3);
            _hint = _backend.myWarningText;
            _listenHint = _listen.myWarningText;
            if (Plugin.CompareLog.Value)
            {
                Plugin.Log.LogInfo($"Options: added recogniser rows to the Voice tab (templates {template.optionName}, {withNote.optionName}; fine print: {(_hint ? "yes" : "no")}).");
            }
        }

        private static GameOption Clone(GameOption template, string name, MenuManager.OptionsList list, int index)
        {
            GameObject copy = Object.Instantiate(template.gameObject, template.transform.parent);
            copy.name = name;
            GameOption option = copy.GetComponent<GameOption>();
            option.optionName = name;
            option.warningText = "";
            option.hasProcessed = true; // the slider is built by SetValues below, not by the game
            if (option.myWarningText)
            {
                option.myWarningText.text = "";
            }
            list.allMenuOptions.Insert(Mathf.Min(index, list.allMenuOptions.Count), option);
            return option;
        }

        /// <summary>Rebuilds a cloned row's value list (the clone still holds the template's value nodes).</summary>
        private static void SetValues(GameOption option, List<string> keys, List<string> labels)
        {
            OptionsSlider slider = option ? option.mySlider : null;
            if (!slider)
            {
                return;
            }
            string prefab = slider.sliderPrefab ? slider.sliderPrefab.name : null;
            foreach (Transform child in slider.transform.Cast<Transform>().ToList())
            {
                if (prefab == null || child.name.StartsWith(prefab))
                {
                    child.gameObject.SetActive(false);
                    Object.Destroy(child.gameObject);
                }
            }
            slider.allOptionsNodes.Clear();
            slider.allSliderOptions = new List<string>(keys);
            slider.allTranslatedOptions = new List<string>(labels);
            slider.myOptions = option;
            slider.Process();
            option.currentlySelectedOption = Mathf.Clamp(option.currentlySelectedOption, 0, keys.Count - 1);
            option.Select();
        }

        // ---- Labels and values ----

        private static SaveManager.OptionsLookup Lookup(SaveManager save, string row) =>
            save.allOptionsLookup.FirstOrDefault(o => o.baseName == row);

        private static string Word(SaveManager.OptionsLookup lookup, int index, string fallback) =>
            lookup != null && index < lookup.allOptionsWords.Count && lookup.allOptionsWords[index].Trim() != "" ? lookup.allOptionsWords[index].Trim() : fallback;

        private static string WithTime(string label, int ms) =>
            ms > 0 && label.EndsWith(")") ? label.Substring(0, label.Length - 1) + ": " + ms + " ms)" : label;

        /// <summary>Labels (in the current language) and selections, from the config. Called after every language load.</summary>
        internal static void Refresh(MenuManager menu)
        {
            Build(menu);
            if (!_engine)
            {
                return;
            }
            SaveManager save = menu.myGameManager.mySaveManager;
            SaveManager.OptionsLookup engine = Lookup(save, EngineRow), backend = Lookup(save, BackendRow), listen = Lookup(save, ListenRow);
            SetDescription(_engine, engine);
            SetDescription(_backend, backend);
            SetDescription(_listen, listen);

            _engine.currentlySelectedOption = Plugin.UseWhisper ? 1 : 0;
            SetValues(_engine, new List<string> { Plugin.EngineWindows, Plugin.EngineWhisper },
                new List<string> { Word(engine, 0, "Windows (default; vanilla)"), Word(engine, 1, "Whisper") });

            // Hardware: only what's installed. Index in the [SPEECHBACKEND] words: Auto, GPU (Vulkan), GPU (CUDA), CPU (Vulkan).
            BackendKeys.Clear();
            var labels = new List<string>();
            BackendKeys.Add(Plugin.BackendAuto);
            labels.Add(Word(backend, 0, "Auto (Default)"));
            if (NativeBackend.IsInstalled("vulkan"))
            {
                BackendKeys.Add(Plugin.BackendVulkan);
                labels.Add(WithTime(Word(backend, 1, "GPU (Vulkan)"), Plugin.VulkanGpuMs.Value));
            }
            if (NativeBackend.IsInstalled("cuda"))
            {
                BackendKeys.Add(Plugin.BackendCuda);
                labels.Add(WithTime(Word(backend, 2, "GPU (CUDA)"), Plugin.CudaGpuMs.Value));
            }
            if (NativeBackend.IsInstalled("vulkan"))
            {
                BackendKeys.Add(Plugin.BackendCpu);
                labels.Add(WithTime(Word(backend, 3, "CPU (Vulkan)"), Plugin.CpuMs.Value));
            }
            _backend.currentlySelectedOption = Mathf.Max(0, BackendKeys.IndexOf(Plugin.Backend.Value));
            SetValues(_backend, BackendKeys, labels);

            _listen.currentlySelectedOption = Plugin.VoiceActivation ? 2 : Plugin.PushToTalk ? 1 : 0;
            SetValues(_listen, new List<string> { Plugin.ListenAutomatic, Plugin.ListenPushToTalk, Plugin.ListenVoiceActivation },
                new List<string> { Word(listen, 0, "Tap to Toggle"), Word(listen, 1, "Push to Talk"), Word(listen, 2, "Voice Activation") });
            UpdateHint(save, restart: false);
            UpdateListenHint(save);
        }

        private static void SetDescription(GameOption option, SaveManager.OptionsLookup lookup)
        {
            if (option && option.myOptionText && lookup != null)
            {
                option.myOptionText.text = lookup.description;
            }
        }

        /// <summary>The fine print under the hardware row: what GPU or CPU means, and whether it needs a restart.</summary>
        private static void UpdateHint(SaveManager save, bool restart)
        {
            if (!_hint || !_backend || _backend.currentlySelectedOption >= BackendKeys.Count)
            {
                return;
            }
            string key = BackendKeys[_backend.currentlySelectedOption];
            bool gpu = key == Plugin.BackendVulkan || key == Plugin.BackendCuda || (key == Plugin.BackendAuto && Plugin.VulkanGpuMs.Value > 0);
            string text = save.ReturnLookup("sentence", gpu ? "whisperhintgpu" : "whisperhintcpu");
            if (restart)
            {
                text += " " + save.ReturnLookup("sentence", "whisperhintrestart");
            }
            _hint.text = text;
        }

        /// <summary>The fine print under the listening row: what the selected mode does.</summary>
        private static void UpdateListenHint(SaveManager save)
        {
            if (!_listenHint || !_listen)
            {
                return;
            }
            string[] keys = { "whisperhinttap", "whisperhintpush", "whisperhintvoice" };
            _listenHint.text = save.ReturnLookup("sentence", keys[Mathf.Clamp(_listen.currentlySelectedOption, 0, 2)]);
        }

        // ---- Applying ----

        /// <summary>SaveManager.UpdateOptions for our rows (left/right in the menu). Returns true if handled.</summary>
        internal static bool Apply(SaveManager save, GameOption option)
        {
            if (!IsOurs(option))
            {
                return false;
            }
            MenuManager menu = save.myGameManager.myMenuManager;
            switch (option.optionName)
            {
                case EngineRow:
                    Plugin.Engine.Value = option.currentlySelectedOption == 1 ? Plugin.EngineWhisper : Plugin.EngineWindows;
                    if (save.isDictationActive)
                    {
                        save.CloseDictationEngine(_doesDispose: false);
                    }
                    SpeechSupportPatch.Refresh(save);
                    // Show or hide the Whisper rows straight away.
                    menu.SetupBannedOptionsLists();
                    menu.LoadOptionsSelector(menu.currOptionsList, _doesResetPos: false);
                    Plugin.Log.LogInfo($"Options: recogniser {Plugin.Engine.Value}.");
                    break;
                case BackendRow:
                    if (option.currentlySelectedOption < BackendKeys.Count)
                    {
                        Plugin.Backend.Value = BackendKeys[option.currentlySelectedOption];
                        bool restart = WhisperEngine.BackendChanged();
                        UpdateHint(save, restart);
                        Plugin.Log.LogInfo($"Options: Whisper hardware {Plugin.Backend.Value}{(restart ? " (after restarting the game)" : "")}.");
                    }
                    break;
                case ListenRow:
                    Plugin.Listening.Value = option.currentlySelectedOption == 2 ? Plugin.ListenVoiceActivation : option.currentlySelectedOption == 1 ? Plugin.ListenPushToTalk : Plugin.ListenAutomatic;
                    // Leaving Voice Activation: stop listening now (a running session ends on its own).
                    if (!Plugin.VoiceActivation && VoiceSession.Instance.IsActive && !save.isDictationActive)
                    {
                        VoiceSession.Instance.End();
                    }
                    UpdateListenHint(save);
                    Plugin.Log.LogInfo($"Options: Whisper listening {Plugin.Listening.Value}.");
                    break;
            }
            return true;
        }

        /// <summary>Hides the Whisper-only rows while Windows Speech Recognition is selected.</summary>
        internal static void Ban(MenuManager menu)
        {
            if (!Plugin.UseWhisper)
            {
                menu.currentBannedList.Add(BackendRow.ToLower());
                menu.currentBannedList.Add(ListenRow.ToLower());
            }
        }
    }

    [HarmonyPatch(typeof(MenuManager), nameof(MenuManager.LoadNamesAndLinks))]
    internal static class VoiceOptionsNamesPatch
    {
        // After the game sets every row's texts from the current language.
        private static void Postfix(MenuManager __instance) => VoiceOptions.Refresh(__instance);
    }

    [HarmonyPatch(typeof(MenuManager), nameof(MenuManager.SetupBannedOptionsLists))]
    internal static class VoiceOptionsBanPatch
    {
        private static void Postfix(MenuManager __instance) => VoiceOptions.Ban(__instance);
    }

    [HarmonyPatch(typeof(SaveManager), nameof(SaveManager.UpdateOptions))]
    internal static class VoiceOptionsApplyPatch
    {
        // Our rows are handled here and never reach the game's options file.
        private static bool Prefix(SaveManager __instance, GameOption _gameOption) => !VoiceOptions.Apply(__instance, _gameOption);
    }
}
