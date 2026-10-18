using System;
using System.Collections.Generic;

namespace CryptmasterWhisper
{
    /// <summary>Maps the game's three-letter language codes (SaveManager.language) to Whisper's language codes.</summary>
    internal static class GameLanguages
    {
        private static readonly Dictionary<string, string> Builtin = new(StringComparer.OrdinalIgnoreCase)
        {
            ["ENG"] = "en", ["SPA"] = "es", ["POR"] = "pt", ["FRA"] = "fr", ["FRE"] = "fr", ["DEU"] = "de", ["GER"] = "de",
            ["ITA"] = "it", ["NLD"] = "nl", ["DUT"] = "nl", ["POL"] = "pl", ["RUS"] = "ru", ["UKR"] = "uk", ["TUR"] = "tr",
            ["JPN"] = "ja", ["KOR"] = "ko", ["ZHO"] = "zh", ["CHI"] = "zh", ["CAT"] = "ca", ["SWE"] = "sv", ["NOR"] = "no",
            ["DAN"] = "da", ["FIN"] = "fi", ["CES"] = "cs", ["CZE"] = "cs", ["HUN"] = "hu", ["ROU"] = "ro", ["RON"] = "ro",
            ["ELL"] = "el", ["GRE"] = "el", ["ARA"] = "ar", ["HEB"] = "he", ["IND"] = "id", ["VIE"] = "vi", ["THA"] = "th",
        };

        internal static string ToWhisper(string gameCode)
        {
            foreach (string pair in Plugin.LanguageMap.Value.Split(';'))
            {
                string[] kv = pair.Split('=');
                if (kv.Length == 2 && string.Equals(kv[0].Trim(), gameCode, StringComparison.OrdinalIgnoreCase))
                {
                    return kv[1].Trim().ToLowerInvariant();
                }
            }
            if (gameCode != null && Builtin.TryGetValue(gameCode, out string code))
            {
                return code;
            }
            // Short commands are too little audio for reliable detection, but it beats a wrong language.
            return "auto";
        }
    }
}
