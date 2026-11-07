# phone-check

Read-only health and spyware check for an Android phone, run from a Mac or Linux PC over USB.

It saves a snapshot: installed apps and where they came from, apps with strong access
(accessibility, notification access, device admin, keyboards), camera/mic/location use,
VPN, proxy and certificates, and CPU, memory, storage, battery and heat.

It changes nothing on the phone.

## Use

1. On the phone: Settings → About phone → tap Build number 7 times.
2. Settings → System → Developer options → turn on USB debugging.
3. Plug in. Tap Allow on the phone.
4. Run `./scan.sh`.

Output goes to `reports/<timestamp>/`. It holds personal data and is git-ignored. Do not share it.

Turn USB debugging off when done.

Needs `adb` (Android platform-tools).
