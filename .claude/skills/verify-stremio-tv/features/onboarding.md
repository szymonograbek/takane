# Onboarding and sign-in

On first launch Takane shows Welcome with two choices: Sign In with Stremio, or Continue Without Account. Sign-in shows a link code and QR code from Stremio's API, with email and password as the alternative. Continuing lands on Home and is remembered.

## Sub-features

- `welcome` shows the logo, the two buttons and focuses Sign In.
- `link-code` shows a 4-character code from core's `link` model and a QR code for link.stremio.com.
- `password-error` shows Stremio's refusal for wrong credentials and keeps the password out of the log.
- `continue` opens the tabs: Home, Settings, Search.

## How to get to it (user POV)

- Launch the app on a device that has not finished onboarding.

## Driving it with tv.sh

Preconditions:

- `$T launch` just ran (it clears the onboarding flag).

- **Welcome.** `$T focused` prints `welcome.signIn`. Run `$T evidence onboarding-welcome`.
- **Link code.** `$T select`, wait 4 s, `$T text signIn.code` prints a 4-character code. The log shows `dispatch → link` and repeated `ReadData` every 3 s.
- **Password error.** `$T select` (focus starts on Use Email and Password Instead), `$T type signIn.email up nobody-takane-test@example.com`, `$T type signIn.passwordField down wrong-password-123`, `$T focus signIn.submit down`, `$T select`, wait 6 s. `$T text signIn.error` prints `User not found`. `grep -c wrong-password-123 "$log"` prints `0`.
- **Continue.** From a fresh launch, `$T focus welcome.continue right`, `$T select`. Within 8 s `$T focused` prints `house` and Home shows the hero and rows.

## Gotchas

- After the email keyboard's done, tvOS opens the password keyboard straight away (the fields are a username/password pair), so `$T type signIn.passwordField …` finds no focused field. Fill the open keyboard's field from a raw snapshot instead, or type the password first.

- A real sign-in needs a Stremio account confirming the code on another device; this recipe stops at the code.
- Core's auth error event echoes the request; the adapter redacts `password`, `token` and `authKey` before logging. A non-zero password grep is a regression.
