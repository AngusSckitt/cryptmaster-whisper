using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace CryptmasterWhisper
{
    /// <summary>
    /// What the player is likely to say, for Whisper's prompt, and clean-up of Whisper's output before the
    /// game sees it. The game itself then maps known mishearings ([SPEECHLOOKUP]) and types the letters.
    /// </summary>
    internal static class Vocabulary
    {
        // Whisper (tiny especially) "hears" these in silence or noise; only accepted if the game knows the word.
        private static readonly HashSet<string> Hallucinations = new()
        {
            "you", "thank you", "thanks", "thank you very much", "thanks for watching", "thank you for watching",
            "bye", "okay", "oh", "uh", "um", "hmm", "so", "the", "music", "applause", "silence", "blank audio",
            "obrigado", "obrigada", "tchau", "gracias", "adios",
        };

        /// <summary>Party names and their current skill words, in the game's current language.</summary>
        internal static string BuildPrompt(GameManager game)
        {
            if (!Plugin.VocabularyPrompt.Value || !game)
            {
                return null;
            }
            var words = new List<string>();
            foreach (CharacterHUD hud in game.allCharacterUI)
            {
                if (!hud)
                {
                    continue;
                }
                words.AddRange(hud.allCurrentSpellNames);
            }
            words = words.Where(w => !string.IsNullOrWhiteSpace(w)).Select(w => w.Trim().ToLowerInvariant()).Distinct().Take(60).ToList();
            return words.Count == 0 ? null : string.Join(", ", words) + ".";
        }

        /// <summary>Letters and spaces only, lower case; empty if it looks like a hallucination.</summary>
        internal static string Clean(string text, SaveManager save)
        {
            var b = new StringBuilder();
            foreach (char c in text.ToLowerInvariant())
            {
                if (char.IsLetter(c))
                {
                    b.Append(c);
                }
                else if ((char.IsWhiteSpace(c) || c == '-') && b.Length > 0 && b[b.Length - 1] != ' ')
                {
                    b.Append(' ');
                }
            }
            string cleaned = CollapseRepeats(b.ToString().Trim());
            if (cleaned.Length == 0)
            {
                return "";
            }
            if (Hallucinations.Contains(cleaned) && !IsKnownWord(cleaned.Replace(" ", ""), save))
            {
                Plugin.Log.LogInfo($"Whisper: ignored '{text.Trim()}' (likely heard in silence).");
                return "";
            }
            return cleaned;
        }

        /// <summary>
        /// On short clips Whisper often repeats what it heard until it runs out of tokens ("right. right.
        /// right..."), sometimes cutting the last repeat short. Keeps one copy: of a repeated block of words
        /// if the whole text is that block over and over, otherwise of each run of the same word.
        /// </summary>
        internal static string CollapseRepeats(string text)
        {
            string[] words = text.Split(new[] { ' ' }, System.StringSplitOptions.RemoveEmptyEntries);
            int n = words.Length;
            for (int block = 1; block <= n / 2; block++)
            {
                bool repeats = true;
                for (int i = block; i < n && repeats; i++)
                {
                    string expected = words[i % block];
                    // The final copy may be truncated ("honour honour hon").
                    repeats = i == n - 1 ? expected.StartsWith(words[i]) : words[i] == expected;
                }
                if (repeats)
                {
                    return string.Join(" ", words, 0, block);
                }
            }
            var kept = new List<string>();
            foreach (string word in words)
            {
                if (kept.Count == 0 || kept[kept.Count - 1] != word)
                {
                    kept.Add(word);
                }
            }
            return string.Join(" ", kept);
        }

        private static bool IsKnownWord(string word, SaveManager save)
        {
            if (!save)
            {
                return false;
            }
            foreach (SaveManager.NameList list in save.allSpeechLists)
            {
                if (list.enemyName.ToLowerInvariant() == word || list.allEnemyNames.Any(n => n.ToLowerInvariant() == word))
                {
                    return true;
                }
            }
            return save.myGameManager && save.myGameManager.allCharacterUI.Any(h => h && h.allCurrentSpellNames.Contains(word));
        }
    }
}
