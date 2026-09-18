# Release notes

Two blocks per release, newest first.

- `appstore` — the "What's New in This Version" text. Paste it into App Store Connect verbatim:
  the field is plain text, so `#` and `-` appear literally — that is the convention these notes
  use, not Markdown. App Store Connect shows the version number itself, so it is never repeated
  in the text.
- `whatsnew` — the short version the app shows on first launch after an update. Written by hand,
  not derived from the block above: the store text is far too long for a card. Kept for every
  release so the app can show any of them, not only the current one.

The `whatsnew` block uses the same `#New` / `#Fixed` headers as the store block, one item per line:

    #New
    - <icon> | <title> | <body>
    #Fixed
    - <one line>

`<icon>` is one of `sync`, `alert`, `photo`, `guard`, `timer`, `widget`, `speed`, `new` — `new`
is the neutral brand glyph, for anything the others do not fit. Keep `<title>` under about 32
characters and `<body>` under about 90, or the row wraps past two lines. `<body>` may be omitted.
`#Fixed` lines are plain text with no icon and render as a green check. Splitting on `|` and
trimming is the whole parser.

The rest of the store listing (description, keywords, review information) lives in
`app_store_listing.md`, which is gitignored because it stages the reviewer's demo credentials.

## 1.0.3

```appstore
#New
- Sync problems are now visible. A record the server refuses stops retrying and shows up in Settings → Pending Changes with the server's reason in plain words, plus Retry and Discard.
- Records that could not sync show a red warning next to the sync icon on the Timeline. Open one and the reason appears at the top; tap it to jump straight to Pending Changes.
- Queued photo uploads now appear in Pending Changes too.
- Logging a pumping session without an amount, or an activity that ends before it starts, runs over 24 hours, or is set in the future, is caught before you save.

#Fixed
- Repeating a feeding from the Timeline no longer leaves the old end time behind, which made the copy fail to sync.
- Child photos now upload correctly to the server.
- Stopping a timer that was already stopped elsewhere no longer retries forever, and never creates a duplicate on its own.
- Tag lists from some server versions now sync instead of failing.
```

```whatsnew
#New
- sync | Sync problems are visible | Rejected records stop retrying and wait in Pending Changes with the reason.
- alert | Flagged on the Timeline | Records that failed to sync show a red warning. Tap it to see why.
- photo | Photo uploads queue too | Queued child photos now appear in Pending Changes as well.
- guard | Caught before you save | Missing amounts and impossible times are flagged as you log them.
#Fixed
- Repeating a feeding keeps the right end time
- Child photos upload to the server correctly
- Stopping a timer twice can't create a duplicate
- Tag lists from older servers sync again
```

## 1.0.2

```appstore
#New
- Sync and sign-in failures now report more detail, so I can find problems that only happen on certain Baby Buddy server versions. Still anonymous.
- If a sync fails for you, please let me know roughly when — these reports should make it findable.

#Fixed
- Connection problems now say what actually failed. A wrong address, a server that is not on your network, and a certificate your iPhone does not trust used to all show the same "no connection" message.
```

```whatsnew
#New
- sync | More detail on failures | Sync and sign-in errors now report what actually went wrong. Still anonymous.
#Fixed
- Connection problems say what failed, not just "no connection"
```

## 1.0.1

```appstore
#New
- Performance improvements for older devices.
- Scrolling the Timeline, switching tabs, and searching should all feel noticeably smoother.
- Please try it on your device and let me know if you still see any lag — and where.

#Fixed
- When signing out the local cache now clears, this fixes the issue with persisted data from prior servers which would make no sense.
- Widgets clear on logout and do not hold stale data.
- Sign out popup now appears with the option to cancel.
```

```whatsnew
#New
- speed | Faster on older devices | Timeline scrolling, switching tabs and searching all feel smoother.
#Fixed
- Signing out clears the local cache
- Widgets clear on logout instead of holding stale data
- Sign out asks first, with a way to cancel
```

## 1.0

```appstore
The first release of Baby Buddy Companion. Track feedings, sleep, diapers, pumping, and growth on your self-hosted Baby Buddy server — offline-first, with live timers and Home Screen widgets. Thanks for trying it!
```

```whatsnew
#New
- new | Welcome to Baby Buddy | Track feedings, sleep, diapers, pumping and growth on your own server.
- timer | Live timers and widgets | Start a timer anywhere and see it on the Home Screen.
- sync | Works offline | Everything you log syncs when the server is reachable again.
```
