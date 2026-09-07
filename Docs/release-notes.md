# Release notes

The "What's New in This Version" text for each App Store release, newest first.

Paste the fenced block into App Store Connect verbatim: the field is plain text, so `#` and `-`
appear literally — that is the convention these notes use, not Markdown. App Store Connect shows
the version number itself, so it is never repeated in the text.

The rest of the store listing (description, keywords, review information) lives in
`app_store_listing.md`, which is gitignored because it stages the reviewer's demo credentials.

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
