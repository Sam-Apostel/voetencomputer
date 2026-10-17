# Voetencomputer — direction

Redesign, 17 October 2026. Everything here lives in `design/` and is not committed: it is for Sam to review.

**Files:** `before.html` → `shots/before/` · `explore.html` → `shots/explore/` · `mockup.html` → `shots/r4/` (final) and `shots/r4-se/` (375×667), earlier rounds in `shots/r1`–`r3` · `before-after.html` → `shots/before-after/` · `CRITIQUE.md` (four rounds).

## Brief (self-authored)

Sam asked for this run with "no questions, just go", so the six brief questions are answered here by the designer, not by Sam. No paid image generation was used; all imagery is drawn SVG.

1. **What and who.** An iPhone app that takes readings from a Medisana BS 650 connect scale over Bluetooth and writes them to Apple Health, with no account, no VitaDock and no cloud. For Sam's household first, then for anyone who owns a BS 4xx/6xx scale and is tired of Medisana's app, and for tinkerers building the DIY ESP32 scale in `docs/esp32-scale-spec.md`.
2. **The core action.** Step on, step off, done. The phone may be in another room; iOS wakes the app when the scale powers up. The first ten seconds *in* the app are a glance: did it land, and is the number where I expect it.
3. **Three words:** wry, physical, unjudging. **References from outside apps:** a child's crayon drawing taped to a fridge; the drawn instructions on a Dutch train ticket machine; a bathroom scale's LCD hunting for a number before it locks.
4. **What exists:** the name Voetencomputer and its story (a nephew calling the grandparents' scale "a computer you work with your feet"), an AppIcon.png (rendered slate scale, LCD reading "64.2 kg", a red heartbeat line), the `MetricColor` VitaDock-style palette, a `ScaleGlyph` drawing, a working BLE and HealthKit stack, Belgian comma decimals.
5. **What is needed:** a redesign of the three screens plus the moments around them (first run, an unrecognised weigh-in, the confirmation after stepping off), the icon, a before/after. No SwiftUI in this pass.
6. **Image generation:** not used. Nothing was spent.

## Current app

### Audit

Rebuilt from `DashboardView`, `TrendsView` and `SettingsView` (including Sam's uncommitted changes) in `before.html`, shot to `shots/before/`.

It is close to slop.md's **"dashboard reflex"** in a system skin: a large title that is the app name, a hero weight card with a big number and a green ▼ delta, a donut, a 2x2 grid of tinted stat tiles. Trends is a stack of three identical tinted chart cards. Settings is a stock form. Nothing on any screen says *feet*, *scale* or *Voetencomputer* except the title.

Scan FAILs on the rebuild:

```
before-now       FAIL  Contrast below WCAG: 2.08:1 54px "78,4 kg"; 2.08:1 13px "▼ 0,5 kg since last"; 3.35:1 "17 Oct 2026 at 07:12"
                 FAIL  7 saturated hue families (144°, 0°, 24°, 168°, 192°, 216°, 240°). This is confetti.
before-trends    FAIL  Contrast below WCAG: 2.11:1 "Weight"; 2.10:1 "Body fat"; 2.01:1 "Muscle"
before-settings  FAIL  Contrast below WCAG: 2.22:1 "Connected to Apple Health" (system green on white)
App-wide: 8 text sizes [54, 34, 20, 17, 15, 13, 12, 11]
```

What it does well, and the redesign keeps: the sentence-like delta ("0,5 kg since last"), the honest note when composition is older than the weight, the "Who weighed in?" card with the fix-it steps, the composition model (fat, muscle and bone are disjoint; water overlaps muscle so it is not a slice), and the Health-history footnote on Trends.

### Inventory: keep / lose / unknown

The keep column is a contract. Each item is checked against the final screens.

| Item | Verdict | Where it lives now |
|---|---|---|
| Background BLE sync, all stored readings pulled on each connection | keep | first run, signature, Household › scales |
| Weight, body fat, lean mass, BMI written to Apple Health | keep | Now ("In Apple Health"), Body ("goes to Health" marks) |
| Water %, muscle %, bone mass, daily energy kept in-app | keep | Now (bar + legend), Body |
| Sync status in the toolbar (idle, scanning, syncing, done, Bluetooth off) | keep, restyled | Now toolbar pill: "Synced 07:12" |
| Delta since the previous reading | keep, as a sentence | Now: "Half a kilo lighter than Thursday." |
| Body composition from an older reading, labelled | keep | Body: "Composition from Thursday" variant (in Content) |
| Composition as parts of a whole (fat, muscle, bone, rest) | keep the model, lose the donut | Now and Body: one crayon bar with three fills |
| BMI with WHO bands | keep, as words | Body: "24,2 · in the healthy band (18,5–25)" |
| Unrecognised weigh-in: assign to a profile, or "Not one of us" | keep | Who sheet |
| Weight matching (`ProfileMatcher`, ±3 kg, unique match) | keep, made visible | Who sheet: "Closest: nobody within 3 kg" |
| Recognition help (the SET steps on the scale) | keep | Who sheet, "Teach the scale" row; full sheet not redrawn |
| Notification for an unrecognised weigh-in | keep | signature frame 4 variant (Content) |
| Empty states (no readings; nothing for this profile) | keep | First run; "nothing for this profile" copy in Content |
| Trends: 30d / 90d / 1y / All, one chart per metric, delta phrase | keep | Trends |
| Trends merge full Apple Health history for Health types | keep | Trends footnote |
| Allow Health access, re-sync with its result messages | keep | Household › Apple Health |
| My profile (P1–P8 or all users), profile names, height | keep | Household › people |
| Paired scale row, tap to forget | keep | Household › scales |
| Advanced, revealed by shaking: clock epoch, VitaDock CSV import, BLE log, sample data | keep, still hidden | Household, bottom row only after a shake |
| Units follow region; comma decimals | keep | every screen ("78,4") |
| `MetricColor` per-metric palette (green, orange, blue, mint, teal, indigo, pink) | **lose** (decision 2) | one crayon colour; fills tell metrics apart |
| Donut chart | **lose** (decision 3) | crayon bar |
| Green ▼ / orange ▲ on the delta | **lose** (decision 6) | words, no colour |
| Heart rate | unknown | not in the reverse-engineered protocol yet |
| Confirmation notification after a normal weigh-in | new, imagined | signature frame 4 |
| Live Activity / Dynamic Island while syncing | unknown | an app woken by BLE in the background cannot start a Live Activity without push-to-start; the notification is the honest version |
| Second scale: DIY ESP32 on the 0x181D Weight Scale Service | new, imagined | Household › scales ("not supported yet" in the spec) |
| Guests (a visiting nephew) | new, imagined | Who sheet, Household |

### Assets harvested

- The name and its story (README). The nephew's word is the concept.
- `ScaleGlyph` (2x2 ITO electrodes, display bar): its top view of the platform becomes the icon's scale.
- The current icon's LCD reading is replaced, but its idea (the scale seen from above) survives.
- Real data shape from `ScaleMeasurement`: weight, fat %, water %, muscle %, bone kg, kcal, user slot, source, healthSynced. The values in the mockups are invented (the repo is public; no real measurements).

## Rediscovery

- **The core moment happens with the phone shut.** So the app's real first screen is the notification, and the in-app Now screen is a receipt you glance at. It should answer two questions in one look: *did it land* and *how does it compare*.
- **A household shares one scale.** The scale already knows P1–P8, and `ProfileMatcher` already guesses by weight. The redesign makes that visible: everyone is a pair of feet, and other people's numbers stay on their own phones.
- **The nephew is right.** The scale *is* a computer you work with your feet. That is the only concept no competitor can copy, and it is warm, which a weight app badly needs.
- **Trends should read in a sentence.** "Down 1,9 kg since the end of July" is what people actually want; the chart is evidence.
- **The DIY scale** is a real path for the project (the spec is detailed). The Household screen shows it as a second scale so the design has room for it.

## Decisions for Sam

Every product-changing call in this redesign. None is built; each is a yes/no for you.

1. **Name.** *Decided by Sam: Voetencomputer everywhere, including the home screen.* App Store subtitle "Your scale, straight to Apple Health". The drawing direction depends on the name's story. (The home-screen label may truncate on some phones; that is accepted.) ScaleSync stays the internal target name only.
2. **Drop the VitaDock palette.** `MetricColor` (picked after household feedback that the app felt flat) is replaced by one crayon colour, with metrics told apart by fill: solid, hatched, washed, empty. The app gets *more* colourful in feel (the drawings) while using one hue. This reverses a choice someone in the household asked for; worth showing them the before/after first.
3. **Donut → one bar.** Same data and the same disjoint-compartment model, drawn as a single crayon bar that reads left to right.
4. **Tabs: Now · Trends · Household** (was Now · Trends · Settings). People and scales lead; Apple Health and the advanced rows live under them.
5. **Other people's numbers stay private by default.** On Sam's phone, Lien's weigh-in shows as "Lien stepped on at 06:48. Her numbers went to her phone." Requires each person to run the app on their own phone; "Show everyone's numbers" stays as a switch (today's "All users").
6. **No green/red on weight change.** Direction is a sentence ("Half a kilo lighter than Thursday"), never a colour. Gaining weight is not an error state.
7. **BMI loses the traffic-light gauge.** It becomes a number and a band in words on the Body screen.
8. **New: a confirmation notification after every weigh-in** (today only unrecognised ones notify). Time-sensitive off; it is a receipt, not an alert.
9. **New: guests.** An unrecognised 23,8 kg reading can be kept as "Mats (guest)" instead of only assigned or deleted. Guests never go to anyone's Health.
10. **New: a second scale type**, the DIY ESP32 scale on the standard Weight Scale Service. Shown in Household; needs the 0x181D parser from the spec.
11. **Dark mode is blue paper**, not black: deep ink-blue ground with the crayon lightened.
12. **New icon**: two cobalt footprints on a drawn scale platform, replacing the rendered scale with the heartbeat.

## The default refused

The category is Withings Health Mate, Renpho, Eufy Life, Fitbit and Apple Health's own body measurements. They share: a white or near-black ground with medical teal or blue; a ring or arc gauge around the weight; a grid of 10 to 13 metric tiles, each with its own colour and icon chip; green-down / red-up arrows that grade every reading; a BMI rainbow or traffic-light bar; a grey human silhouette for "body"; a "body score" out of 100.

Refused here, all of it: no rings or arcs, no tile grid, no per-metric colours, no judgement colours, no traffic-light BMI, no human silhouette, no score. The category's colour cliché (clinical teal/cyan) is refused too: the one colour is a wax-crayon cobalt, deeper and warmer than medical blue, and it never means "good" or "bad", only "drawn".

Also refused: this skill's own overcorrection (grey paper, mono, one red, ruled rows) and the current app's confetti.

## Exploration

`explore.html` → `shots/explore/sheet.png`. Three concepts, three source families, three grounds, three type designs, three accent hues, three richness sources.

| | A · the LCD | B · the nephew's drawing | C · the 1974 bathroom floor |
|---|---|---|---|
| Concept | Voetencomputer is the scale's own LCD at 7 a.m. | Voetencomputer is a nephew's crayon drawing of a computer you work with your feet. | Voetencomputer is a glazed tile floor, one tile per morning. |
| Family | object | play | place |
| Ground | dark | light | colour-field |
| Type | custom-display (drawn seven-segment) + SF Pro | rounded (SF Pro Rounded) | expanded (SF Pro Expanded Black) |
| Accent | teal backlight | blue (crayon cobalt) | pink (salmon tile, oxblood glaze) |
| Richness | shape | illustration | colour-material |

**B won.** It is the only one that is *this* app: the name made visible. It is warm where the category is clinical, and its drawn feet give every screen something to look at without a photo. It also makes the household legible (a pair of feet per person) and gives the signature an obvious object.

- **A lost** because it repeats the scale: the BS 650 already shows a seven-segment number, and the app's job is everything the scale cannot do. Its four electrode pads are the 2x2 dashboard grid in costume, and dark-plus-glowing-teal drifts toward fintech dark.
- **C lost** because a tile per day turns missed days into visible gaps (guilt, for a weight app), and a salmon 1970s floor is a costume that would date fast. Its idea of reading a week at a glance moved into B's Trends.

**Merged in from A:** the LCD "hunting" before it locks became part of B's signature (the number settles the way the scale's display does).

**History check** (`~/.app-designer/history.md`): B is play / light / rounded / blue / illustration. Against Reizo (nature/colour-field/serif/orange/colour-material): differs on 5. Reizo v2 (place/image/expanded/yellow/photo): 5. Mise (place/colour-field/condensed/red/photo): 5. The current app (object/light/grotesque/neutral/none): 4 (family, type, hue, richness).

## Direction

**Voetencomputer is a nephew's crayon drawing of a computer you work with your feet.** One cobalt crayon on drawing paper. Everything drawn is drawn by the same hand: feet, the scale, a wobbly line, a tick. Everything typed is SF Pro Rounded, big and calm.

### Tokens

| Role | Light ("drawing paper") | Dark ("blue paper at night") |
|---|---|---|
| ground | `#F6F7F2` cool paper, not cream | `#0F1233` |
| raised | `#FFFFFF` | `#1A1E4A` |
| ink | `#191B2C` | `#EEF0FA` |
| ink-2 | `#4A4D63` | `#B5BAD8` |
| ink-3 | `#6A6D82` | `#8D93B8` |
| rule | `rgba(25,27,44,.12)` | `rgba(238,240,250,.14)` |
| accent (crayon) | `#2A39C4` fills, lines and text (8.1:1 on ground) | `#9AA6FF` |
| crayon-wash | `rgba(42,57,196,.10)` | `rgba(154,166,255,.16)` |
| on-accent | `#FFFFFF` | `#0F1233` |
| positive / negative | none. Weight change is never coloured. | none |

- **Accent role:** *the drawn mark.* Feet, lines, hatching, the tick next to "In Apple Health", and the selected tab. Because its role is drawing and selection, the system tint is the crayon (`.tint(crayon)`).
- **Type:** SF Pro Rounded only (`.fontDesign(.rounded)`). One family.

| Step | Size / line | Weight | Tracking | Use |
|---|---|---|---|---|
| hero | 104 / 94 | Heavy (800) | −4 | the weight on Now; one per screen |
| title | 34 / 38 | Bold | −0.6 | screen titles, Trends' sentence |
| say | 20 / 26 | Medium | −0.2 | the sentence under the hero |
| body | 17 / 22 | Regular / Semibold | −0.2 | rows |
| sec | 15 / 20 | Medium | 0 | secondary |
| meta | 13 / 17 | Medium | 0 | legends, dates |

  Tab labels use the system 10pt. Figures are tabular everywhere.
- **Margin:** 20. **Radius:** 10 (chips), 22 (containers and sheets' inner groups), capsule (buttons). **Spacing:** 4, 8, 12, 16, 24, 32, 48.
- **Crayon line:** 4.5pt at 1x on the hero drawing, 2.5pt on small drawings, round caps and joins, hand-drawn paths (no perfect geometry except toes).

### The richness source: one crayon, one hand

Illustration, drawn in one hand everywhere. A child's view, executed by an adult designer: confident single strokes, slight wobble, no outlines doubled, no faces, no bodies. The vocabulary is small on purpose:

- **Feet**: each person is a pair. Size follows the person (Mats's are small). Filled with the 10% wash.
- **The scale**: a rounded square seen from above, with its little display. Used on first run, Household and the icon.
- **The line**: trends are drawn as a crayon line that wobbles slightly; points are not dots but small crayon dashes.
- **Fills as meaning**: solid crayon = fat, 45° hatching = muscle, wash = bone, empty = the rest. These are the only three fills.
- **The tick**: drawn, never a system checkmark, and only for "in Apple Health".

No photography. No textures or paper grain (clean shapes; imagery.md §2).

### The crayon in SwiftUI

The mockups get the hand-drawn wobble from one SVG displacement filter. In SwiftUI, draw the shapes as `Path`s whose points get a fixed, seeded jitter (1–2pt) once, so the wobble is stable and never animates; vary the stroke by drawing a second, thinner offset pass at 45% opacity. No noise textures.

### The signature: footprints

Storyboard (shown in `mockup.html` as four frames):

| t | Frame | Motion | Haptic |
|---|---|---|---|
| 0 ms | Paper with two dotted foot outlines; "Listening for the scale". The reading arrives (BLE indication, or the app opens after a background sync). | — | — |
| 80–340 ms | The feet press in: left at 80, right at 160. Each scales 1.04 → 1.0 (smooth spring, 0.26 s) while the wash fills heel to toe (clip-path). | — | `.impact(weight: .light)` per foot |
| 200–650 ms | The number hunts like the scale's LCD, drawn as crayon seven-segment digits with unlit segments in the wash: 77,8 → 78,9 → 78,2, then it locks and becomes the rounded 78,4. | — | `.selection` on lock |
| 700–920 ms | The crayon tick draws beside "In Apple Health" (stroke draw, 0.22 s). | — | `.success` |
| background | No animation. A notification: "78,4 kg · in Apple Health. Half a kilo lighter than Thursday." | — | system |

Reduced motion: the feet, number and tick cross-fade in together over 0.2 s; one `.success` haptic. No information is lost.

## Content

All values invented (public repo). Comma decimals, Belgian locale. Household: Sam (P1, this phone, height 180 cm), Lien (P2, her own phone), Mats (guest, a visiting nephew).

### 1. Now (core, mid-use) — Saturday 17 October, 07:14
- Toolbar: "S · Sam" person capsule (left); "Synced 07:12" pill (right).
- Date: "Saturday, 07:12".
- Drawing: Sam's two feet, pressed.
- Hero: "78,4 kg".
- Sentence: "Half a kilo lighter than Thursday."
- Mark: tick + "In Apple Health".
- Composition bar: fat 18,4% (solid), muscle 40,1% (hatched), bone 3,4 kg ≈ 4,3% (wash), rest (empty). Legend: "18,4% fat · 40,1% muscle · 3,4 kg bone · 57,9% water". A "Body" chevron leads to 2.
- Household line: "Lien stepped on at 06:48. Her numbers went to her phone."
- Tabs: Now (selected) · Trends · Household.

### 2. Body (detail, pushed from Now)
- Back: "Now". Title: "Saturday's body". Meta: "07:12 · BS 650 · P1".
- Hero: a vertical crayon column, 78,4 kg tall, split into the fills: fat 14,4 kg, muscle 31,4 kg, bone 3,4 kg, rest 29,2 kg, with labels beside each band.
- Rows: Body fat 18,4% (goes to Health) · Lean mass 64,0 kg (goes to Health) · BMI 24,2, "in the healthy band, 18,5 to 25" (goes to Health), with a drawn band strip: four outline segments split at 18,5, 25 and 30, only the healthy band washed, a marker at 24,2, never borrowing the fat or muscle fills · Water 57,9%, "overlaps muscle, so it's not in the column" · Daily energy 2 637 kcal, "what the scale estimates you burn". (Muscle and bone are labelled on the column itself.)
- Footnote: "Body fat, lean mass and BMI go to Apple Health. The rest has no place there, so it stays here."
- Variant (not drawn): when the latest weigh-in had no composition, the meta line reads "Composition from Thursday, 07:31".

### 3. Trends
- Title: "Trends". Range control: 30 days · **90 days** · 1 year · All.
- Hero sentence: "Down 1,9 kg since the end of July." Sub: "Steady for the last two weeks."
- Drawing: the 90-day weight line in crayon, 41 weigh-ins, a dash per reading, today circled. Axis words only: "Jul", "Aug", "Sep", "Oct"; values "80" and "78" at the edge.
- Rows, each with a small crayon line: Body fat 18,4%, "−0,8 in 90 days" · Muscle 40,1%, "+0,4" · Water 57,9%, "+0,2" · Bone 3,4 kg, "no change".
- Footnote (directly under the chart): "Weight, body fat, lean mass and BMI include your whole Apple Health history, from every app."

### 4. Signature storyboard (four frames)
Frame 1 "0 ms", dotted feet, "––,–". Frame 2 "300 ms", feet pressed, "78,9" hunting in crayon seven-segment digits. Frame 3 "800 ms", "78,4" locked, the tick mid-draw (with a magnified inset). Frame 4 lock screen notification: "Voetencomputer · now — 78,4 kg, in Apple Health. Half a kilo lighter than Thursday."
Unrecognised variant (copy only): "Who just weighed in? Someone weighed 23,8 kg at 16:40. Open to say who it was."

### 5. Now, dark
The same Saturday reading, opened at 21:03 with dark mode on. Toolbar "Synced 07:12". This frame also shows the older-composition variant: the composition header reads "Composition from Thursday, 06:58".

### 6. Who was that? (sheet over Now)
- Grabber. Title: "Who was that?" with the visitor drawn beside it as small dotted feet. Sub: "Someone weighed 23,8 kg yesterday at 16:40. The scale didn't know them, and nobody here is within 3 kg."
- Choices, each a pair of feet drawn to size: "Sam · last 78,4 kg" · "Lien · last 61,7 kg" · "A guest…" (selected, field "Mats").
- Primary: "Keep as Mats (guest)". Secondary: "Not one of us" (deletes). Footnote: "Guests never go to Apple Health."

### 7. First run (empty state)
- Drawing: the scale from above, two dotted feet on it.
- Title: "Step on the scale."
- Body: "Barefoot, phone nearby. It pairs by itself and brings every reading it has kept."
- Check row: "Scale in Bluetooth mode" with "How" link; "Apple Health: allow" button ("Allow Apple Health").
- Status: "Listening for a BS 410, 444 or 650".

### 8. Household
- Title: "Household", with a drawn bath mat beside it: Sam's, Lien's and Mats's feet lined up by size, Mats dotted (a guest).
- People: Sam, "This phone · P1", with an editable "Height 180 cm" row under him · Lien, "Her phone · P2" · Mats, "Guest · 2 readings, not in Health". "Show everyone's numbers" switch, off.
- Scales: "BS 650 · bathroom", "Paired · last seen 07:12" (drawn scale) · "Workbench scale", "DIY ESP32 · battery 81%" (drawn bare board, chip and wires) · "Scale forgot you? Teach it again" (opens the recognition-help steps) · "Forget the BS 650".
- Apple Health: "Connected" · "Re-sync all readings" · footer: "Re-sync writes your readings to Apple Health again and replaces what's there."
- Footnote: "Re-sync writes your readings to Apple Health again and replaces what's there. Shake the phone for the scale clock, VitaDock import and the Bluetooth log."

### 9. Icon
Cobalt rounded-square platform seen from above with a little display, two paper-white footprints on it, on a paper ground. Two colours.

### Not designed this round
Recognition-help sheet (the SET steps; copy kept as is), profile names editor, VitaDock import result, Bluetooth log, the Lock Screen widget, onboarding for a second phone, Trends for one metric full screen.
