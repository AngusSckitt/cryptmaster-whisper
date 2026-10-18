using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using HarmonyLib;

namespace CryptmasterWhisper
{
    /// <summary>
    /// This mod's texts (textos\{CODE}.txt, the game's line format), added to the game's lookups after it
    /// loads a language. The game rewrites its own language files on every launch, so they are injected in
    /// memory, never written to disk. Lines that replace an existing game text (e.g. the voice warning) are
    /// used only when this mod has that language; otherwise the language keeps its own text. New texts (e.g.
    /// the recogniser option) fall back to English.
    /// </summary>
    internal static class Texts
    {
        private static readonly Dictionary<string, List<string[]>> ByLanguage = new(StringComparer.OrdinalIgnoreCase);

        internal static void Load(string folder)
        {
            if (!Directory.Exists(folder))
            {
                Plugin.Log.LogWarning($"Texts folder not found: {folder}");
                return;
            }
            foreach (string file in Directory.GetFiles(folder, "*.txt"))
            {
                var lines = File.ReadAllLines(file, new UTF8Encoding(false))
                    .Where(l => l.StartsWith("["))
                    .Select(l => l.Split('/'))
                    .Where(f => f.Length >= 3)
                    .ToList();
                ByLanguage[Path.GetFileNameWithoutExtension(file)] = lines;
            }
        }

        internal static void Apply(SaveManager save)
        {
            bool ownLanguage = ByLanguage.TryGetValue(save.language ?? "", out List<string[]> lines);
            if (!ownLanguage && !ByLanguage.TryGetValue("ENG", out lines))
            {
                return;
            }
            int added = 0, replaced = 0;
            foreach (string[] f in lines)
            {
                switch (f[0])
                {
                    case "[SENTENCELOOKUP]":
                        Set(save.allSentenceLookup, f[1], f[2], ownLanguage, ref added, ref replaced);
                        break;
                    case "[TOOLTIPWORDLOOKUP]":
                        Set(save.allWordTooltipLookup, f[1], f[2], ownLanguage, ref added, ref replaced);
                        break;
                    case "[MENUOPTION]" when f.Length >= 4:
                        SetOption(save, f, ownLanguage, ref added, ref replaced);
                        break;
                }
            }
            Plugin.Log.LogInfo($"Texts for {save.language}{(ownLanguage ? "" : " (English fallback)")}: {added} added, {replaced} replaced.");
        }

        private static void Set(List<SaveManager.WordLookup> lookup, string key, string value, bool mayReplace, ref int added, ref int replaced)
        {
            List<SaveManager.WordLookup> existing = lookup.Where(w => w.ENGWord == key).ToList();
            if (existing.Count == 0)
            {
                lookup.Add(new SaveManager.WordLookup { ENGWord = key, nativeWord = value });
                added++;
            }
            else if (mayReplace)
            {
                existing.ForEach(w => w.nativeWord = value);
                replaced++;
            }
        }

        private static void SetOption(SaveManager save, string[] f, bool mayReplace, ref int added, ref int replaced)
        {
            SaveManager.OptionsLookup existing = save.allOptionsLookup.FirstOrDefault(o => o.baseName == f[1]);
            if (existing != null && !mayReplace)
            {
                return;
            }
            if (existing == null)
            {
                existing = new SaveManager.OptionsLookup { baseName = f[1] };
                save.allOptionsLookup.Add(existing);
                added++;
            }
            else
            {
                replaced++;
            }
            existing.description = f[2];
            existing.allOptionsWords.Clear();
            existing.allOptionsWords.AddRange(f[3].Split(','));
        }
    }

    [HarmonyPatch(typeof(SaveManager), nameof(SaveManager.LoadExternalLang))]
    internal static class TextsPatch
    {
        // Runs after any other mod's postfixes that might set the language (they patch with default priority).
        [HarmonyPriority(Priority.Low)]
        private static void Postfix(SaveManager __instance, bool _isUni, string loadType)
        {
            if (!_isUni && loadType == "core")
            {
                Texts.Apply(__instance);
            }
        }
    }
}
