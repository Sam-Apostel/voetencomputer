# Voetencomputer

[![CI](https://github.com/Sam-Apostel/voetencomputer/actions/workflows/ci.yml/badge.svg)](https://github.com/Sam-Apostel/voetencomputer/actions/workflows/ci.yml)

> *"voetencomputer"* — what my nephew called the scale at his grandparents' house. A computer you operate with your feet. He was right.

A minimal iOS app that syncs your **Medisana BS 650 connect** scale straight to **Apple Health** — no VitaDock, no Medisana account, no cloud.

**How it works:** the app talks to the scale directly over Bluetooth using the reverse-engineered Medisana/Transtek protocol ([openScale wiki](https://github.com/oliexdev/openScale/wiki/Medisana-BS444)). The scale stores every measurement internally and transmits *all* stored readings on each connection, so nothing is lost if your phone wasn't nearby when you weighed in. After the first pairing, iOS wakes the app in the background whenever the scale powers up — step on, done.

**Synced to Apple Health:** weight, body fat %, lean body mass, BMI (once you enter your height).
**Tracked and graphed in-app** (no HealthKit types exist for these): body water %, muscle %, bone mass, calorie requirement.

---

## Requirements

- **Xcode 26** or newer
- An iPhone on **iOS 26.5** or newer
- An Apple ID. A free one works, but the app then has to be reinstalled from Xcode every 7 days; a paid Apple Developer account removes that limit.

## Building

1. Open `ScaleSync.xcodeproj`.
2. Target → *Signing & Capabilities*: choose your own **Team** and change the **Bundle Identifier** to one under your own name — the committed one belongs to the maintainer's developer account.
3. Select your iPhone as the run destination and press ⌘R. The first time, trust your developer certificate on the phone: Settings → General → VPN & Device Management.

Every push and pull request is built by [CI](.github/workflows/ci.yml).

## First sync

1. Open the app, go to **Settings → Grant Health access** and allow all categories.
2. Put the scale into **Bluetooth mode** if it's currently wifi-only (see the BS 650 manual — connection mode is chosen during scale setup). Wifi uploads go only to Medisana's cloud; the app needs the Bluetooth side.
3. With the app open, **step on the scale**. The sync button in the top-right turns orange while syncing and green when done. Every measurement stored on the scale comes over, and new ones land in Apple Health automatically.
4. In **Settings**, set *My profile* to the user number the scale assigned you, so housemates' readings stay out of your dashboard and Apple Health. Name the profiles under *Profile names*, and enter your **height** to get BMI.
5. Optional: export your history from VitaDock (app → profile → export, or [VitaDock Online](https://cloud.vitadock.com) → Export data) and use **Settings → Import VitaDock CSV export** to backfill.

After the first pairing you shouldn't need to open the app at all: iOS relaunches it in the background when the scale wakes up. (iOS can be lazy about this right after a reboot — opening the app once re-arms it.)

## Troubleshooting

| Symptom | Fix |
|---|---|
| Scale never discovered | Scale is in wifi-only mode → switch it to Bluetooth mode. Also make sure the VitaDock+ app is fully closed (it may grab the connection first) — best to uninstall it once Voetencomputer works. |
| Readings have wrong dates (~40 years off) | Settings → *Scale clock epoch* → switch to the other value, then weigh again. |
| Connected but "service 0x78B2 not found" in the debug log | Your BS 650 firmware may deviate from the BS4xx family protocol. Open **Settings → Bluetooth debug log**, tap share, and attach the log to an issue — the frames in it are enough to adapt the parser. |
| Duplicate-looking entries in Health | They're replaced, not duplicated — the app uses HealthKit sync identifiers. Delete old manual/VitaDock-written samples in the Health app if any linger. |
| Heart rate missing | The BS 650's pulse reading isn't part of the reverse-engineered protocol yet. A debug log from a weigh-in attached to an issue would help — it's likely in one of the unknown frame bytes. |

## Privacy

Everything stays on your iPhone: measurements are stored in a local database and written to Apple Health. The app makes no network requests at all.
