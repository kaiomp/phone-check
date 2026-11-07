# phone-check

**Is someone spying on my Android phone? Why is it so slow?**

phone-check answers both from your computer, in about two minutes. It reads your phone over a
USB cable and gives you a plain report: red flags, things to check, and how to free up space.

It only reads. It never installs, removes or changes anything on the phone.

```
phone-check: Pixel 8, Android 15, scanned 2026-01-01
To fix: 2. To check: 4.

# OK Phone system is not tampered with
# FIX Security updates are behind
# CHECK 2 installed apps have strong access
# CHECK 3 apps are not from the Play Store
# OK Internet traffic goes the normal way
# FIX Storage is almost full (0% free)
...
```

A full HTML report opens in your browser when the scan is done.

## What it checks

| Question | What it looks at |
|---|---|
| Is the phone system tampered with? | Verified boot, bootloader lock, root (`su`) |
| Is it up to date? | Security patch age, a waiting system update |
| Can an app spy on me? | Apps with accessibility, notification access, device admin, or a custom keyboard. This is the access that stalkerware needs. |
| Where did my apps come from? | Apps that did not come from the Play Store, with install dates |
| Who used my camera, mic, photos and location? | Every app that used them in the last 30 days |
| Is my traffic redirected? | Proxy, private DNS, VPN |
| Are there unknown accounts? | All accounts on the phone |
| Why is it slow? | Free storage, biggest folders, exact duplicate files, big apps you have not opened in 60 days, memory, battery health, heat |

Some things only you can check (for example, user certificates). The report lists them with
the exact place to tap.

## Run it

You need a Mac or Linux computer, a USB cable, and
[Android platform-tools](https://developer.android.com/tools/releases/platform-tools) (`adb`).
On a Mac: `brew install --cask android-platform-tools`.

1. On the phone, turn on USB debugging:
   - Settings → About phone → tap **Build number** 7 times.
   - Settings → System → Developer options → turn on **USB debugging**.
2. Plug the phone in. On the phone, tick **Always allow** and tap **Allow**.
3. On the computer:

   ```bash
   git clone https://github.com/kaiomp/phone-check.git
   cd phone-check
   ./scan.sh
   ```

4. Read the report. Then turn USB debugging off again.

The scan saves everything to `reports/<date-time>/`. To build the report again from an old scan,
run `./analyze.sh reports/<date-time>`.

## What the colours mean

- **FIX**: act on this.
- **CHECK**: look at the list and decide. Most items are normal apps you chose yourself.
- **INFO**: worth one look.
- **OK**: nothing to do.

A CHECK is not proof of spyware. Security apps, app blockers and launchers need strong access
too. The report tells you where to look; you decide what belongs on your phone.

## Your data

The report holds personal data: your apps, accounts and file names. It stays on your computer.
Nothing is uploaded. `reports/` is git-ignored, so it is never committed. Do not share a report
in public.

## How it works

Three small bash scripts and no other dependencies:

- `scan.sh` asks the phone for read-only system dumps over `adb shell` (`dumpsys`, `pm`,
  `settings`, `getprop`) and saves them as text files.
- `analyze.sh` turns those files into `summary.txt`.
- `render-html.sh` turns `summary.txt` into `report.html`.

Tested on a Pixel with Android 16. Other Android phones should work; a check that cannot read its
data shows "unknown".

## Development

```bash
shellcheck scan.sh analyze.sh render-html.sh tests/run.sh
tests/run.sh   # runs the analyser on fake phone data in tests/fixture/
```

## License

[MIT](LICENSE)
