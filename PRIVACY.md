# Privacy Policy — Baby Buddy Companion

Last updated September 12, 2026

**Baby Buddy Companion** ("the app") is an unofficial, open-source native client for the self-hosted [Baby Buddy](https://github.com/babybuddy/babybuddy) server. It is built and published by Kurtis Guy ("we", "us"). This policy explains what the app does — and does not — do with your information.

The short version: **your baby's data lives on the Baby Buddy server you run, not with us.** The App Store build does include limited app telemetry. TelemetryDeck records generic feature use and coarse error categories, while RevenueCat processes and records optional tip purchases. Neither service receives your baby or tracking records, server address, or credentials. We do not sell data.

## Your tracking data stays on your server

The app is a client for a Baby Buddy server that **you** host and control. Every record you create — feedings, sleep, diaper changes, tummy time, pumping, notes, photos, your children's names and details — is stored on **your** server. The app sends that data only between your device and the server address you configure.

To work offline, the app keeps a local copy of your data in its own on-device storage. That copy never leaves your device except to sync with your own server.

We never receive, store, or have any access to your tracking data.

## Your server address and credentials

When you connect the app to your Baby Buddy server, the server URL and your login credentials (such as your API token) are stored securely in the iOS **Keychain** on your device. They are used only to authenticate with your server and are never transmitted to us or to any third party.

## Optional biometric lock

If you enable the optional Face ID / Touch ID / passcode lock, authentication is performed entirely by iOS on your device. We never see your biometric data — iOS only tells the app whether authentication succeeded.

## App telemetry and error reporting (App Store build only)

The App Store build **does contain telemetry**. It uses [TelemetryDeck](https://telemetrydeck.com/privacy/) to understand how the app is used and to diagnose problems. This is operational analytics, not advertising or cross-app tracking.

The app sends:

* **Generic feature-use signals** — for example, that onboarding completed, a timer started or stopped, a type of activity was logged, a widget action ran, a search returned results, or a sync completed. It never sends the contents of a record.
* **Coarse error signals** — for example, offline, unauthorised, decoding, conflict, or an HTTP status category. Error logging never includes your server URL, request contents, server response text, credentials, or baby data.
* **Basic technical context** supplied by the SDK — such as app and iOS version, device type, and a timestamp rounded to the nearest hour.

TelemetryDeck adds an **app-scoped, salted anonymous hash** so aggregate events can be counted without a name or account. This is a technical identifier, but it is not your name, email address, Apple ID, Baby Buddy account, or advertising identifier. We do not use it to identify, profile, contact, or single out a person. TelemetryDeck does not store IP addresses.

These limits follow TelemetryDeck's [privacy documentation](https://telemetrydeck.com/docs/guides/privacy-faq) and [error-reporting guidance](https://telemetrydeck.com/docs/articles/preset-errors). Telemetry is disabled in the app's **demo mode**. Builds compiled from the open-source repository ship without our TelemetryDeck App ID and send nothing to our analytics account.

## Purchases and receipt tracking

The app is free, and every feature in it is free. It includes optional **consumable support purchases**, or tips — Kind, Generous and Amazing — offered under **Settings → Baby Buddy App Supporter**. They can be made more than once, are not subscriptions, and do not unlock or change any features. Payment is handled by **Apple** through the App Store — we never see your payment details.

[RevenueCat](https://www.revenuecat.com/privacy/) is used to process and track these purchases. It receives the anonymous purchase/customer identifier and the App Store receipt or transaction information needed to validate purchases and refunds. It does not receive your baby data, tracking records, server address, or credentials. We use it strictly for optional purchase and receipt tracking.

The app supplies RevenueCat with the TelemetryDeck App ID and anonymous hashed user value so anonymous receipt events can be matched with purchase-flow signals. This follows TelemetryDeck's [RevenueCat integration documentation](https://telemetrydeck.com/docs/integrations/revenuecat). The value is not used to identify or isolate a person.

## Who your data is shared with

Putting the above together, the parties involved are:

* **Your own Baby Buddy server** — receives and stores your tracking data (you control it).
* **Apple** — processes in-app purchases, per [Apple's Privacy Policy](https://www.apple.com/legal/privacy/).
* **RevenueCat** — processes optional tip purchases and tracks their receipts (App Store build).
* **TelemetryDeck** — receives limited feature-use and coarse error telemetry (App Store build).

We do not sell your data, and we do not share it beyond what is described here.

## Children's privacy

The app is a tool for parents and caregivers. Any information about a child is entered by you and stored on your own server; we do not collect it. The app is not directed at children and is not intended for use by children.

## Changes to this policy

We may update this policy as the app evolves. Material changes will be reflected on this page with a new "last updated" date.

## Contact

Questions about privacy? Email [hello@babybuddy.app](mailto:hello@babybuddy.app) or open an issue on [GitHub](https://github.com/kguy18/babybuddyios/issues).
