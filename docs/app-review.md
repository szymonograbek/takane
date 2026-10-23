# App Review

How to submit Takane to the App Store with the best chance of approval, and why. Sideloading stays the fallback, because no approach guarantees an app stays listed.

## What happened to similar apps

Apple has published no reason for any of these removals. The record as of October 2026:

- **Stremio Lite** reached iOS, then tvOS on 29 October 2025, without the streaming server, torrents or the community add-on list, which Stremio left out "due to app review requirements". Apple removed it in January 2026 after an update. Stremio now ships a sideload-only IPA.
- **Stremio on other stores.** Amazon listed it in December 2025 and removed it within weeks. Google Play suspended it for 19 days.
- **Fusion Media Center** and **Omni**, both Stremio add-on clients, are no longer in the App Store. **Nuvio** withdrew its Apple apps.
- **Still listed.** All The Media leads with IPTV, Google Drive and WebDAV and lists Stremio support as one feature. It says it "does not provide any media content". Infuse is a generic player.

The likely reading: Apple judges the app by the ecosystem it serves, not only by the binary. Approval is possible, and a later removal, often after a rights holder complains, is the larger risk.

## Guidelines that apply

| Guideline | Rule | How Takane meets it |
|---|---|---|
| 2.1 | A reviewer must reach the app's features, with a demo account if it has a login | Everything works signed out. Open Movies plays on first launch |
| 4.2.3 | The app works on its own | Open Movies, Cinemeta and the other default add-ons need no setup. Jellyfin and WebDAV sources play the user's own media without any add-on |
| 5.1.1(v) | No forced login. Account creation requires in-app deletion | Sign-in is optional. Takane creates no accounts |
| 5.2.1 | No third-party trademarks without permission | The name, bundle id and executable are Takane. "Stremio" appears only where it names the account |
| 5.2.2 | Permission to use a third-party service, shown on request | Needs Stremio's consent for its API. See below |
| 5.2.3 | The app must not facilitate illegal file sharing | No torrent engine, no add-on directory, no torrent or debrid wording |

## Before the first submission

- [ ] Ask Stremio (Smart Code) for written consent to use its account API and to name Stremio in the app. Keep the reply to attach in App Store Connect.
- [ ] Use only Open Movies titles in screenshots and previews.
- [ ] Keep the description, keywords, release notes and review notes free of: torrent, magnet, debrid, Real-Debrid, Torrentio, piracy terms, and catalogs or brands of paid services.
- [ ] Describe Takane as a player for the user's own media: their Jellyfin server and WebDAV folders first, add-ons second. Do not call it a Stremio client.
- [ ] Host a small demo WebDAV folder of Creative Commons films (the Open Movies titles), reachable from the internet, and put its address and login in the review notes. A reviewer has no server of their own, and guideline 2.1 needs them to reach every feature.
- [ ] Take one screenshot of Settings › Sources and one of a source's folders, both showing the demo folder.
- [ ] Never ship an add-on directory or suggest add-ons in the app.

## Review notes

Paste into App Review Information, Notes, and update it when the app changes (guideline 2.3.1):

> Takane is a video player for the user's own media. It plays films and shows from the user's Jellyfin server or WebDAV folder (NAS, Nextcloud, rclone), which they add in Settings › Sources; logins stay in this device's Keychain. To try it, add the demo WebDAV folder: Settings › Sources › Add WebDAV Folder, address <demo address>, username <demo username>, password <demo password>. Its films then show on Home and play, and Library › <demo name> browses its folders. Takane also ships with Open Movies, a built-in source of Creative Commons and public-domain films (Blender Foundation open movies and Internet Archive silent classics), so it works on first launch without any setup: choose Continue Without Account, then play any title in the Free Movies row. Signing in to an existing Stremio account is optional and only syncs the user's library and watch progress. Takane hosts no content, creates no accounts and does not support peer-to-peer downloads.
