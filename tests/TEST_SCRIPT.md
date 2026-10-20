# Voice recognition test script

Each session is one game run. Start the game, do the session, quit the game. With recording on, each run
gets its own folder in `BepInEx\plugins\CryptmasterWhisper\recordings\`, so sessions don't mix. Afterwards,
`tools\replay` runs every recording through the other Whisper models and settings and scores them against
this script, so each session only needs to be played once.

## Before every session

- Set the config (`BepInEx\config\cryptmaster.whisper.cfg`) as the session header says: `Engine`, `Mode`, and
  `RecordSessions = true`.
- Options: Voice Input **on**, and the language the session says.
- Stand somewhere safe and quiet in the game (an explored corridor, no enemies). Words will be typed and
  submitted, so the party may move or swing at nothing. That's fine.
- Use your usual microphone at its usual distance, unless a line says otherwise.
- One line = one press of the Ear button. Say only the **Say** word(s), as the **Emulate** column describes,
  then wait until the ear bar ends before the next line.
- If a line goes wrong, carry on with the next one. The replay tool aligns recordings to lines and copes with
  skipped or repeated lines. If you remember, note the line ID.

Emulate tags: `normal` is your natural voice and pace. `fast`/`slow` is the pace, with `slow` drawing the
word out. `soft` is quiet but voiced; `whisper` means actually whispering. `loud` is near-shouting. `instant`
means start speaking the moment you press. `delay2` means wait about 2 s after pressing, then speak.
`mumble` means lazy articulation. `filler` means say "um..." then the word. `high`/`low` means raise or lower
your pitch. `far` means about 1 m from the mic. `silent`/`cough`/`laugh`/`clap`: no word, just that (the
right result is nothing). Noise tags say what should be playing.

## Other testers

Different voices matter: pitch (low and high voices), accents (non-native English speakers), and age (a
teenager's or child's voice, if someone is willing) all change results. Session S8 is a short version for
extra people. Tell them the recordings stay on your computer, are used only to tune the mod and get deleted
afterwards, and only record people who agree. Note each tester's profile (e.g. "low voice, native PT,
speaks some English") at the top of your notes for that run.

---

## S1 — Baseline, English (Engine = Windows, RecordSessions = true; game in English)

Windows recognises live, and the same audio is replayed through Whisper later. Quiet room, normal voice.

| ID | Say | Accept | Emulate |
|---|---|---|---|
| S1-01 | Joro | joro | normal |
| S1-02 | Syn | syn | normal |
| S1-03 | Maz | maz | normal |
| S1-04 | Nix | nix | normal |
| S1-05 | hit | hit | normal |
| S1-06 | boot | boot | normal |
| S1-07 | guard | guard | normal |
| S1-08 | jab | jab | normal |
| S1-09 | trap | trap | normal |
| S1-10 | yell | yell | normal |
| S1-11 | zap | zap | normal |
| S1-12 | roll | roll | normal |
| S1-13 | berserk | berserk | normal |
| S1-14 | dismember | dismember | normal |
| S1-15 | annihilate | annihilate | normal |
| S1-16 | archipelago | archipelago | normal |
| S1-17 | peninsula | peninsula | normal |
| S1-18 | resuscitate | resuscitate | normal |
| S1-19 | incantation | incantation | normal |
| S1-20 | akupara | akupara | normal |
| S1-21 | paradiddle | paradiddle | normal |
| S1-22 | whirlwind | whirlwind | normal |
| S1-23 | yes | yes | normal |
| S1-24 | no | no | normal |
| S1-25 | open | open | normal |
| S1-26 | left | left | normal |
| S1-27 | forward | forward | normal |
| S1-28 | three | three\|3 | normal |
| S1-29 | seven | seven\|7 | normal |
| S1-30 | ten | ten\|10 | normal |

## S2 — Near-misses, English (Engine = Windows, RecordSessions = true; game in English)

Words the game already lists as commonly misheard, plus other close-sounding commands. Say only the word
in **Say**; the note in brackets is what it tends to be misheard as.

| ID | Say | Accept | Emulate |
|---|---|---|---|
| S2-01 | guard | guard | normal (god, card) |
| S2-02 | jab | jab | normal (job, chat) |
| S2-03 | hit | hit | normal (pit, his) |
| S2-04 | sweep | sweep | normal (sweet) |
| S2-05 | grin | grin | normal (green) |
| S2-06 | foil | foil | normal (fuel) |
| S2-07 | cleave | cleave | normal (clive, clay) |
| S2-08 | lithe | lithe | normal (live, lies) |
| S2-09 | rouse | rouse | normal (rows) |
| S2-10 | meddle | meddle | normal (medal) |
| S2-11 | nibble | nibble | normal (neville) |
| S2-12 | throw | throw | normal (through) |
| S2-13 | tease | tease | normal (ts) |
| S2-14 | soothe | soothe | normal (sue) |
| S2-15 | dodder | dodder | normal (daughter) |
| S2-16 | lather | lather | normal (leather) |
| S2-17 | totter | totter | normal |
| S2-18 | martyr | martyr | normal |
| S2-19 | catarrh | catarrh | normal (qatar) |
| S2-20 | plinth | plinth | normal (clint) |
| S2-21 | quartz | quartz | normal (quotes) |
| S2-22 | eldritch | eldritch | normal (eldridge) |
| S2-23 | isthmus | isthmus | normal (christmas) |
| S2-24 | fjord | fjord | normal (field) |
| S2-25 | ooze | ooze | normal (booze) |
| S2-26 | onyx | onyx | normal |
| S2-27 | purloin | purloin | normal (powerline) |
| S2-28 | ensnare | ensnare | normal |
| S2-29 | gristle | gristle | normal (crystal) |
| S2-30 | Syn | syn | normal (sin, sign) |

## S3 — Delivery, English (Engine = Windows, RecordSessions = true; game in English)

The same few words, said differently. Quiet room.

| ID | Say | Accept | Emulate |
|---|---|---|---|
| S3-01 | guard | guard | fast |
| S3-02 | berserk | berserk | fast |
| S3-03 | akupara | akupara | fast |
| S3-04 | guard | guard | slow |
| S3-05 | berserk | berserk | slow |
| S3-06 | akupara | akupara | slow |
| S3-07 | hit | hit | soft |
| S3-08 | dismember | dismember | soft |
| S3-09 | hit | hit | whisper |
| S3-10 | dismember | dismember | whisper |
| S3-11 | jab | jab | loud |
| S3-12 | annihilate | annihilate | loud |
| S3-13 | Joro | joro | instant |
| S3-14 | sweep | sweep | instant |
| S3-15 | Joro | joro | delay2 |
| S3-16 | sweep | sweep | delay2 |
| S3-17 | peninsula | peninsula | mumble |
| S3-18 | foil | foil | mumble |
| S3-19 | trap | trap | filler |
| S3-20 | whirlwind | whirlwind | filler |
| S3-21 | Nix | nix | high |
| S3-22 | incantation | incantation | high |
| S3-23 | Nix | nix | low |
| S3-24 | incantation | incantation | low |
| S3-25 | guard | guard | far |
| S3-26 | archipelago | archipelago | far |

## S4 — Noise, English (Engine = Windows, RecordSessions = true; game in English)

Lines marked *nothing* are for false activations: press the Ear button, then do only what Emulate says. The
right result is no word typed.

| ID | Say | Accept | Emulate |
|---|---|---|---|
| S4-01 | guard | guard | game-loud: game music and effects at 100%, from speakers |
| S4-02 | berserk | berserk | game-loud |
| S4-03 | akupara | akupara | game-loud |
| S4-04 | (nothing) | | game-loud, silent |
| S4-05 | hit | hit | music-lyrics: a song with vocals playing in the room |
| S4-06 | peninsula | peninsula | music-lyrics |
| S4-07 | (nothing) | | music-lyrics, silent |
| S4-08 | jab | jab | talker: someone talking nearby (TV or a person) |
| S4-09 | dismember | dismember | talker |
| S4-10 | (nothing) | | talker, silent |
| S4-11 | sweep | sweep | typing: type on the keyboard while saying it |
| S4-12 | whirlwind | whirlwind | typing |
| S4-13 | Joro | joro | fan: fan or air conditioner near the mic |
| S4-14 | incantation | incantation | fan |
| S4-15 | (nothing) | | quiet, silent |
| S4-16 | (nothing) | | quiet, cough |
| S4-17 | (nothing) | | quiet, laugh |
| S4-18 | (nothing) | | quiet, clap |
| S4-19 | (nothing) | | other-voice: someone else (not you) says "guard" |

## S5 — Whisper live, English (Engine = Whisper, Mode = Automatic, RecordSessions = true; game in English)

The live experience: how quickly words appear, whether the end of speech is detected, and the provisional
results while speaking.

| ID | Say | Accept | Emulate |
|---|---|---|---|
| S5-01 | Joro | joro | normal |
| S5-02 | guard | guard | normal |
| S5-03 | berserk | berserk | normal |
| S5-04 | akupara | akupara | normal |
| S5-05 | paradiddle | paradiddle | normal |
| S5-06 | annihilate | annihilate | normal |
| S5-07 | archipelago | archipelago | normal |
| S5-08 | jab | jab | normal |
| S5-09 | sweep | sweep | instant |
| S5-10 | guard | guard | delay2 |
| S5-11 | dismember | dismember | slow |
| S5-12 | hit | hit | soft |
| S5-13 | guard | guard | game-loud |
| S5-14 | (nothing) | | game-loud, silent |
| S5-15 | (nothing) | | quiet, cough |
| S5-16 | yes | yes | normal |

## S6 — Whisper push to talk, English (Engine = Whisper, Mode = PushToTalk, RecordSessions = true; game in English)

Hold the Ear button while speaking and let go when done. Most of these are noisy on purpose.

| ID | Say | Accept | Emulate |
|---|---|---|---|
| S6-01 | guard | guard | normal |
| S6-02 | berserk | berserk | normal |
| S6-03 | akupara | akupara | game-loud |
| S6-04 | dismember | dismember | music-lyrics |
| S6-05 | jab | jab | talker |
| S6-06 | (nothing) | | talker, silent: hold the button for 2 s and say nothing |
| S6-07 | whirlwind | whirlwind | typing |
| S6-08 | hit | hit | release-early: let go just before the word ends |
| S6-09 | peninsula | peninsula | release-late: hold 1 s after the word |
| S6-10 | Joro | joro | hold-delay: hold 1 s, then speak |
| S6-11 | sweep | sweep | quick tap: press and speak very briefly |
| S6-12 | (nothing) | | other-voice: someone else says "guard" while you hold the button |

## S6b — Whisper voice activation, English (Engine = Whisper, Mode = VoiceActivation, RecordSessions = true; game in English)

No button: just speak. Most lines test what it should *not* pick up.

| ID | Say | Accept | Emulate |
|---|---|---|---|
| S6b-01 | guard | guard | normal |
| S6b-02 | berserk | berserk | normal |
| S6b-03 | akupara | akupara | normal |
| S6b-04 | jab | jab | soft |
| S6b-05 | dismember | dismember | far |
| S6b-06 | (nothing) | | game-talking: let the Cryptmaster speak a line through your speakers, say nothing |
| S6b-07 | hit | hit | game-talking: say it right after the Cryptmaster finishes a line |
| S6b-08 | (nothing) | | quiet, cough |
| S6b-09 | (nothing) | | quiet, laugh |
| S6b-10 | (nothing) | | talker: someone talking nearby for a few seconds |
| S6b-11 | (nothing) | | typing: type on the keyboard for a few seconds |
| S6b-12 | sweep | sweep | music-lyrics |
| S6b-13 | Joro | joro | headphones: repeat S6b-06 and S6b-07 with headphones on |

## S7 — Portuguese (Engine = Windows, RecordSessions = true; game in Português)

Windows recognises in Windows' own speech language. If that isn't Portuguese, Windows will do badly here.
That's expected; the recordings are mostly for replaying through Whisper in Portuguese. Say the words with
their accents, naturally.

| ID | Say | Accept | Emulate |
|---|---|---|---|
| S7-01 | Joro | joro | normal |
| S7-02 | Syn | syn | normal |
| S7-03 | soco | soco | normal |
| S7-04 | bico | bico | normal |
| S7-05 | guarda | guarda | normal |
| S7-06 | racha | racha | normal |
| S7-07 | troco | troco | normal (tronco) |
| S7-08 | foco | foco | normal (fogo) |
| S7-09 | corte | corte | normal (forte) |
| S7-10 | brisa | brisa | normal |
| S7-11 | talho | talho | normal (talo) |
| S7-12 | crime | crime | normal (creme) |
| S7-13 | giro | giro | normal |
| S7-14 | glutão | glutao | normal |
| S7-15 | pontapé | pontape | normal |
| S7-16 | iniciação | iniciacao | normal |
| S7-17 | vingança | vinganca | normal |
| S7-18 | matança | matanca | normal |
| S7-19 | represália | represalia | normal |
| S7-20 | extermínio | exterminio | normal |
| S7-21 | arquipélago | arquipelago | normal |
| S7-22 | península | peninsula | normal |
| S7-23 | alívio | alivio | normal |
| S7-24 | ânimo | animo | normal |
| S7-25 | saudade | saudade | normal |
| S7-26 | salmão | salmao | normal |
| S7-27 | ouriços | ouricos | normal |
| S7-28 | crepúsculo | crepusculo | normal |
| S7-29 | quebra-pau | quebrapau | normal |
| S7-30 | algaravia | algaravia | normal |
| S7-31 | akupara | akupara | normal |
| S7-32 | paradiddle | paradiddle | normal |
| S7-33 | sim | sim | normal |
| S7-34 | não | nao | normal |
| S7-35 | matança | matanca | fast |
| S7-36 | arquipélago | arquipelago | slow |
| S7-37 | guarda | guarda | game-loud |
| S7-38 | vingança | vinganca | soft |

## S8 — Other testers (Engine = Windows, RecordSessions = true)

A short version for each extra person. Do it twice per person: first with the game in English (S8-E), then
with the game in Português (S8-P).

| ID | Say | Accept | Emulate |
|---|---|---|---|
| S8-E01 | Joro | joro | normal |
| S8-E02 | guard | guard | normal |
| S8-E03 | hit | hit | normal |
| S8-E04 | jab | jab | normal |
| S8-E05 | berserk | berserk | normal |
| S8-E06 | akupara | akupara | normal |
| S8-E07 | dismember | dismember | normal |
| S8-E08 | archipelago | archipelago | normal |
| S8-E09 | sweep | sweep | normal |
| S8-E10 | foil | foil | normal |
| S8-E11 | yes | yes | normal |
| S8-E12 | guard | guard | fast |
| S8-P01 | Joro | joro | normal |
| S8-P02 | guarda | guarda | normal |
| S8-P03 | soco | soco | normal |
| S8-P04 | talho | talho | normal |
| S8-P05 | furioso | furioso | normal |
| S8-P06 | akupara | akupara | normal |
| S8-P07 | machadada | machadada | normal |
| S8-P08 | arquipélago | arquipelago | normal |
| S8-P09 | vingança | vinganca | normal |
| S8-P10 | troco | troco | normal |
| S8-P11 | sim | sim | normal |
| S8-P12 | guarda | guarda | fast |

## Afterwards

Tell me which recordings folder belongs to which session (and tester). Run `tools\replay` (see its README)
or ask me to. It scores each recogniser and model per session and per Emulate tag.
