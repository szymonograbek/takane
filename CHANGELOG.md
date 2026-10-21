# Changelog

## [1.3.0](https://github.com/szymonograbek/takane/compare/v1.2.0...v1.3.0) (2026-10-21)


### Features

* **aether:** mute playback with STREMIO_MUTE for smoke runs ([c6b3dec](https://github.com/szymonograbek/takane/commit/c6b3dec8c70d2c49e2d5d2f852d4df550438bbfa))


### Bug Fixes

* **features:** start install add-on screen without stale status ([0e88397](https://github.com/szymonograbek/takane/commit/0e88397ac315b31edc2485f10d91e75185ce715c))
* **scripts:** fix verify harness and resync its feature map ([fa3814e](https://github.com/szymonograbek/takane/commit/fa3814e041e9d398b1bf47680baca882f14dc63b))
* **ui:** focus an add-on's subtitle page once its rows are drawn ([a73f92e](https://github.com/szymonograbek/takane/commit/a73f92e9cb8f5fe43afdbf1285440140050e7a5f))

## [1.2.0](https://github.com/szymonograbek/takane/compare/v1.1.3...v1.2.0) (2026-10-20)


### Features

* **features:** play live tv channels from add-ons ([b9d948b](https://github.com/szymonograbek/takane/commit/b9d948b309dd5c571a11b22071b07e7ad7a4ab4a))
* **ui:** share redacted logs over the local network ([12c8759](https://github.com/szymonograbek/takane/commit/12c8759c8b500eeb76bd8f4452ea9ca98f2b3616))
* **ui:** shorten the log key and hide it until shown ([86308ef](https://github.com/szymonograbek/takane/commit/86308ef5de29bc8908b931702fbb4407b2f18d48))


### Bug Fixes

* **ui:** let focus move up from the log key to the time range ([67fda09](https://github.com/szymonograbek/takane/commit/67fda094dfe5dea414c263a5f17cd149e374394d))

## [1.1.3](https://github.com/szymonograbek/takane/compare/v1.1.2...v1.1.3) (2026-10-20)


### Bug Fixes

* **features:** use a plain deinit in featurestore to avoid a swift 6.3 crash ([356202d](https://github.com/szymonograbek/takane/commit/356202d7912c847f3dab9756ab1d6dcbffbc3ba6))

## [1.1.2](https://github.com/szymonograbek/takane/compare/v1.1.1...v1.1.2) (2026-10-20)


### Bug Fixes

* **core:** require a sendable metatype in observe for xcode 26 ([203f948](https://github.com/szymonograbek/takane/commit/203f9484216cd27737ab1f95925d1dc347462d29))

## [1.1.1](https://github.com/szymonograbek/takane/compare/v1.1.0...v1.1.1) (2026-10-19)


### Bug Fixes

* **ui:** bring the tab bar back on library after a scrolled push ([7bdecd1](https://github.com/szymonograbek/takane/commit/7bdecd1eb9a4c2f0f0408e8217adb28a46a925d2))

## [1.1.0](https://github.com/szymonograbek/takane/compare/v1.0.0...v1.1.0) (2026-10-19)


### Features

* **features:** jump one seek step per tap and add up the streak ([1317a44](https://github.com/szymonograbek/takane/commit/1317a44a483ceee5f25fecc9e4a10020a2f6988d))
* **ui:** offer choices as system list rows ([1dd3100](https://github.com/szymonograbek/takane/commit/1dd31003a094216c0d7c045cf1c1cc8284072397))
* **ui:** open library filters in a popup below their button ([3f4ce30](https://github.com/szymonograbek/takane/commit/3f4ce308f77f4f84ee03ca61baa58a12a511a149))
* **ui:** pick library filters in place ([73cacbe](https://github.com/szymonograbek/takane/commit/73cacbef08c36349d85988875bbd32702b0d7e21))
* **ui:** show the controls and the jump total while seeking ([6dc486f](https://github.com/szymonograbek/takane/commit/6dc486fd56f419f00b884ce15c9e7045028f664c))


### Bug Fixes

* **ci:** build the ipa on a clean runner ([7683a72](https://github.com/szymonograbek/takane/commit/7683a72a0de6e5457350e10ac0a886d426e4421c))
* **scripts:** build the bridge before packaging the ipa ([1ecac9c](https://github.com/szymonograbek/takane/commit/1ecac9cf2461a98529347930cccd2874ccbbde10))
* **ui:** draw screen titles in the content ([2fa0a18](https://github.com/szymonograbek/takane/commit/2fa0a1843a3acbc855b44095168c55bce0f78b8a))
* **ui:** return to the search field on menu from results ([25ebd2f](https://github.com/szymonograbek/takane/commit/25ebd2f53fc1ec92edefe1407da0cef70be45c86))
* **ui:** tvOS seeking, choice pickers, screen titles and search focus ([54d5a33](https://github.com/szymonograbek/takane/commit/54d5a33aad841df21e579288349f37846e7207f7))

## 1.0.0 (2026-10-19)


### ⚠ BREAKING CHANGES

* **aether:** replace mpv with AetherEngine

### Features

* add add-on catalog and skipdb skip segment services ([26771eb](https://github.com/szymonograbek/takane/commit/26771eb5b028aa312db3c0dcbf9ebe7792a5a611))
* **aether:** replace mpv with AetherEngine ([c875e64](https://github.com/szymonograbek/takane/commit/c875e64be11dd04d3504d91b8f0dd39e48a62d3e))
* **bridge:** expose board and search catalogs models ([0795629](https://github.com/szymonograbek/takane/commit/0795629ca24994db48862206311a25580d624289))
* **bridge:** expose core's link model for sign-in by code ([ff495af](https://github.com/szymonograbek/takane/commit/ff495af53844335ce15a80cc8f1f8afbfb38e12f))
* **bridge:** expose library and calendar models ([69f21ab](https://github.com/szymonograbek/takane/commit/69f21ab41988b9f78c901a1f43a00b84c9b2a6c2))
* **core:** serve catalogs and details from add-ons through core ([71860a8](https://github.com/szymonograbek/takane/commit/71860a88dfa07ff418065bf0f50b1ed81b284083))
* **core:** serve the library and upcoming episodes ([63a8612](https://github.com/szymonograbek/takane/commit/63a8612d2b48caa425f9b90e16ba9b0992082542))
* **core:** sync with the account and check for new episodes ([0fdc153](https://github.com/szymonograbek/takane/commit/0fdc153d1d49aadfd79c4cb5cd0d7620d886b559))
* **domain:** add catalog port with board, search and details ([150f2a7](https://github.com/szymonograbek/takane/commit/150f2a744a9fb6a6e00edf91521641039e191611))
* **domain:** add skip segment port ([97690b9](https://github.com/szymonograbek/takane/commit/97690b9071a4b9a5ba5845b41c3b63dff6da8c87))
* **features:** add the date to release days months away ([8c7cc88](https://github.com/szymonograbek/takane/commit/8c7cc88c797f54054bd107bf1b1d6dff74b2bde8))
* **features:** browse genres from search before anything is typed ([7c3cb98](https://github.com/szymonograbek/takane/commit/7c3cb98785b505eeb120e1fd1c0357fb94da2cdc))
* **features:** jump and scan the timeline from the remote ([f65703f](https://github.com/szymonograbek/takane/commit/f65703f11a41b6cf553f313e715e6dbc2ec7cb5c))
* **features:** list the library and group upcoming episodes by day ([d12c45c](https://github.com/szymonograbek/takane/commit/d12c45c8dc887dbe390e2b95da47b058943a2e46))
* **features:** offer recent searches before anything is typed ([60d0039](https://github.com/szymonograbek/takane/commit/60d0039d87dd0e1eccf1257125cc5f4d1deb28d6))
* **features:** play add-on subtitles beside the stream's own ([28d9cb8](https://github.com/szymonograbek/takane/commit/28d9cb8211c7e34c30566b29f6246db30da61e89))
* **features:** remember track and speed choices through core ([3e378cd](https://github.com/szymonograbek/takane/commit/3e378cdb27401fe05e4a4d599c43f0a5ae8e652b))
* **scripts:** install on a paired apple tv picked interactively ([523f663](https://github.com/szymonograbek/takane/commit/523f66347f063f034467ee6d484ec8cf777ed66d))
* **skipdb:** add skipdb skip segment adapter and wire it into services ([2eaceea](https://github.com/szymonograbek/takane/commit/2eaceea294082e8cd59e6042aa31e5aeb67445fc))
* **ui:** add library and calendar tabs ([5c24c57](https://github.com/szymonograbek/takane/commit/5c24c57029065f59bbb55ddccab9c6b246fdaac4))
* **ui:** add second audio language and skip interval settings ([688d747](https://github.com/szymonograbek/takane/commit/688d747adcd2bdb90d54da14b65d908bd4e02865))
* **ui:** add subtitle settings with a live style preview ([273d5ad](https://github.com/szymonograbek/takane/commit/273d5ad5ecb5f1954a30413b1bb8e5ba004567ee))
* **ui:** float the player's options panel on liquid glass ([a958434](https://github.com/szymonograbek/takane/commit/a958434031f47cb29f8f900172546599e9793716))
* **ui:** focus resume or play on details and open the full description ([ccc1dbf](https://github.com/szymonograbek/takane/commit/ccc1dbf175c5cdb90d6899c2d84c50362533afd6))
* **ui:** focusable progress bar with tap and hold seeking ([9f8134c](https://github.com/szymonograbek/takane/commit/9f8134cca748e58a54148a27a5154b316c108fdc))
* **ui:** follow apple's tvos guidelines across screens and search ([d26855f](https://github.com/szymonograbek/takane/commit/d26855f6bb809aca54e9fabed0fa3e9676513c2a))
* **ui:** give large text fewer lockups, wrapping labels and room ([7fcedc0](https://github.com/szymonograbek/takane/commit/7fcedc0b5d50df8d49a796f5e7916234e484e474))
* **ui:** hide spoilers of unwatched episodes ([ff142c0](https://github.com/szymonograbek/takane/commit/ff142c0dc52df4baf0fc250d773ef406e65d53f5))
* **ui:** jump and scan the timeline from the progress bar ([5caf5d6](https://github.com/szymonograbek/takane/commit/5caf5d6b09a531e67ae4ff361969feb92ba76a65))
* **ui:** keep subtitle file styling and add its setting ([3aa377a](https://github.com/szymonograbek/takane/commit/3aa377a76d325ab1808ee5233d969d6ffacc54a7))
* **ui:** keep the streams loading state focusable with a cancel button ([34b1fcc](https://github.com/szymonograbek/takane/commit/34b1fcc5620d8afaa79bc5fa452b0720a86175ce))
* **ui:** lift posters with the borderless lockup style ([fd0c252](https://github.com/szymonograbek/takane/commit/fd0c252fd2fb27cab8cc24090921c49dd98f0c31))
* **ui:** make sign in the welcome screen's primary, focused action ([c636df0](https://github.com/szymonograbek/takane/commit/c636df093550f3fb7299c54a37017543ed1386e1))
* **ui:** mark titles and episodes watched from a context menu ([6d8526f](https://github.com/szymonograbek/takane/commit/6d8526ff25f21f43f163ca7acbb7c5f3063d4d50))
* **ui:** offer the next episode with an up next card ([d9c4aec](https://github.com/szymonograbek/takane/commit/d9c4aec9930cee27922f93dd7290ef1f64afad90))
* **ui:** redesign the app as Takane ([4242ecf](https://github.com/szymonograbek/takane/commit/4242ecfbebd9fd8e228cd7f8fde6124d60b31764))
* **ui:** size shelf lockups to the tvos grid columns ([1e47c24](https://github.com/szymonograbek/takane/commit/1e47c24748e8019707082e69affceed982baf759))
* **ui:** strengthen text and surfaces under increase contrast ([89e29c9](https://github.com/szymonograbek/takane/commit/89e29c968542255fac89b6e3951505182294aa42))
* **ui:** suggest recent searches that continue the query ([e299b97](https://github.com/szymonograbek/takane/commit/e299b9749814c1c2dfabf4cc5034da1c89f86c78))
* **ui:** tidy settings spacing, labels and notes ([581690e](https://github.com/szymonograbek/takane/commit/581690e26355df255051510a5532edf566f6526a))


### Bug Fixes

* **aether:** drop stale positions while a seek is in flight ([a68753e](https://github.com/szymonograbek/takane/commit/a68753e160fd4ac0d219b3bbeadd98ef151664f6))
* **bridge:** run storage writes in the order core queues them ([680d1c8](https://github.com/szymonograbek/takane/commit/680d1c8581363b7544619c048042852ea53d8ab8))
* **core:** report seeks to core so skipped time is not watched ([bc16689](https://github.com/szymonograbek/takane/commit/bc166898c370ed2442b807b5ff4d7948898e1f12))
* **core:** track early stream picks and list embedded streams ([8f22414](https://github.com/szymonograbek/takane/commit/8f224141ec6a754b1fb0c7d4672583335d4e3bb9))
* **scripts:** ignore saved window state in the macOS smoke run ([282d316](https://github.com/szymonograbek/takane/commit/282d3160bda0595d79fd9dfe36068e4b19e7904f))
* **ui:** confirm chosen destructive actions with a plain button ([e738ea7](https://github.com/szymonograbek/takane/commit/e738ea7977d399c40a664e22986ddc5ba0a61f48))
* **ui:** keep loading rows in place in search and streams ([731fbbb](https://github.com/szymonograbek/takane/commit/731fbbb9bf7ac1a080aa1159ce6dcea5e10b1783))
* **ui:** keep search shelves on the safe-area margins ([7e94f04](https://github.com/szymonograbek/takane/commit/7e94f04462ab46ca5fd610fd03d57727d3cc4e93))
* **ui:** keep settings rows focusable and below the title ([91840ec](https://github.com/szymonograbek/takane/commit/91840ec62f4a0ecf4b352c133de43b4af751113c))
* **ui:** land on details when playback stops ([6f01396](https://github.com/szymonograbek/takane/commit/6f01396a300431b2d2df897bfc69eda8df39833c))
* **ui:** open player choices in a panel that keeps focus ([71d6f01](https://github.com/szymonograbek/takane/commit/71d6f0171da34be5e32a28e93cd32ab797dbc0dc))
* **ui:** put the settings tab after search ([39ae2ab](https://github.com/szymonograbek/takane/commit/39ae2abb5d8496515ed953a66a140e75b16b2199))
* **ui:** search, streams, settings and player focus issues ([2b96232](https://github.com/szymonograbek/takane/commit/2b96232791b44bee5f7267a814bb1c5f00f28a23))
* **ui:** seek on clickpad presses only while the controls are hidden ([04a4e65](https://github.com/szymonograbek/takane/commit/04a4e652ed82b8f205fe51b92518ced2a4c4fc63))
* **ui:** start playback with the controls hidden and delay the spinner ([6f05ba4](https://github.com/szymonograbek/takane/commit/6f05ba4fab2ca4648afdc4bb171b3ae7dbaf7de6))
