# Release notes

The "What's New in This Version" text for each App Store release, newest first.

Paste the fenced block into App Store Connect verbatim: the field is plain text, so `#` and `-`
appear literally — that is the convention these notes use, not Markdown. App Store Connect shows
the version number itself, so it is never repeated in the text.

The rest of the store listing (description, keywords, review information) lives in
`app_store_listing.md`, which is gitignored because it stages the reviewer's demo credentials.

## 1.0.3

```
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

## 1.0.2

```
#New
- Sync and sign-in failures now report more detail, so I can find problems that only happen on certain Baby Buddy server versions. Still anonymous.
- If a sync fails for you, please let me know roughly when — these reports should make it findable.

#Fixed
- Connection problems now say what actually failed. A wrong address, a server that is not on your network, and a certificate your iPhone does not trust used to all show the same "no connection" message.
```

## 1.0.1

```
#New
- Performance improvements for older devices.
- Scrolling the Timeline, switching tabs, and searching should all feel noticeably smoother.
- Please try it on your device and let me know if you still see any lag — and where.

#Fixed
- When signing out the local cache now clears, this fixes the issue with persisted data from prior servers which would make no sense.
- Widgets clear on logout and do not hold stale data.
- Sign out popup now appears with the option to cancel.
```

## 1.0

```
The first release of Baby Buddy Companion. Track feedings, sleep, diapers, pumping, and growth on your self-hosted Baby Buddy server — offline-first, with live timers and Home Screen widgets. Thanks for trying it!
```
