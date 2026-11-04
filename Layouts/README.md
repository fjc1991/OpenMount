# Language layouts

The Light Mount's keycaps only show English (US) legends. The **Layouts** section of OpenMount
draws the keyboard with the characters of another typing language, for example Korean 2-Set, so
you can keep it open as a reference while you type. It can follow the input source you switch to
in macOS and float above other windows.

Each language is one JSON file in this folder. **Anyone can add one with a pull request.**

## Add a layout (about 15 minutes)

1. **Copy the template:** duplicate [`TEMPLATE.json`](TEMPLATE.json) and name the copy after
   your layout id, for example `ja-kana.json`, `ru-jcuken.json` or `el-greek.json`.
2. **Fill in the header**

   | Field | What to put |
   |---|---|
   | `id` | Lowercase, starting with the language code: `ru-jcuken`. It **must match the file name**. |
   | `name` | Shown in the app: `Russian – ЙЦУКЕН`. Include the native name if it helps. |
   | `language` | [BCP 47](https://www.w3.org/International/articles/language-tags/) code: `ru`, `pt-BR`, `zh-Hant`. |
   | `authors` | Your GitHub username(s). |
   | `macInputSources` | The macOS input source id(s), so OpenMount can switch to your layout automatically. Switch to the input source and run `defaults read com.apple.HIToolbox AppleSelectedInputSources`, then use the `Input Mode` value if there is one, otherwise the `KeyboardLayout Name` id (`com.apple.keylayout.…`). |
   | `physicalLayout` | `ANSI` (US shape) or `ISO` (UK/EU shape, with an extra key left of Z). |

3. **Fill in `keys`:** one entry per key whose character differs from the US legend:

   ```json
   "Q": { "base": "й", "shift": "Й" }
   ```

   * `base` is what the key types on its own; `shift` is what it types with Shift. Leave
     `shift` out when it's the same as `base`.
   * Keep each legend to 1–3 characters.
   * Keys you leave out keep their normal printed legend, so you only need the keys that change.
4. **Check it:** run `swift test`. The `testCommunityLayouts` test validates every file and says
   exactly what's wrong. GitHub runs the same check on your pull request.
5. **Try it in the app (optional):** run `./scripts/build-app.sh`, open `dist/OpenMount.app`, and go
   to **Layouts**.
6. **Open a pull request.** The PR template has a short checklist. A screenshot of the Layouts
   page showing your language is very welcome.

## Key names

Use these names (they match the physical keys, wherever they are on your layout):

```
Row 1:  GraveAccentAndTilde 1 2 3 4 5 6 7 8 9 0 MinusAndUnderscore EqualsAndPlus
Row 2:  Q W E R T Y U I O P BracketLeft BracketRight Backslash
Row 3:  A S D F G H J K L SemicolonAndColon ApostropheAndDoubleQuote NonUsTilde(ISO)
Row 4:  NonUsBackslash(ISO) Z X C V B N M CommaAndLessThan PeriodAndBiggerThan SlashAndQuestionMark
Numpad: Numpad0 … Numpad9 NumpadSlash NumpadAsterisk NumpadMinus NumpadPlus NumpadPeriodAndDelete
```

Other keys (`Space`, `Enter`, `Tab`, `Escape`, `F1`–`F12`, arrows and so on) can be relabelled too,
but usually don't need to be.

## Rules

* One layout per file, and one file per pull request where possible.
* Describe what macOS actually types with that input source, not a different keyboard's printing.
* Don't copy artwork or fonts. Characters only.
* By submitting, you agree your layout file is released under the project's MIT licence.
