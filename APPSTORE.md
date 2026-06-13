# App Store Connect — Palkie Talkie

Apple ID: `6776366891`. Team: `129df326-897e-414d-acda-0e89b6b4f653`. Developer account number: `94389266`.

---

## App Information

URL: `https://appstoreconnect.apple.com/apps/6776366891/distribution/info`

### Localizable Information (English U.S.)

Name + Subtitle are code SSoT in `backend/app/asc/metadata/en-US/{name,subtitle}.txt`; push with `backend/scripts/asc/set_app_metadata.py`. Do NOT copy the strings here — that copy drifts.

### General Information

- Bundle ID: `XC com palkietalkie app - com.palkietalkie.app`
- SKU: `palkietalkie`
- Apple ID: `6776366891`
- Primary Language: English (U.S.)
- Category — Primary: Education
- Category — Secondary: Lifestyle
- Content Rights: No, this app does not contain, show, or access third-party content.
- License Agreement: Apple's Standard License Agreement (no custom EULA URL — revisit after incorporation if we want a custom EULA covering IP assignment and liability more explicitly).

### Age Ratings

Click "Set Up Age Ratings" — answer ALL of the following with the leftmost option (None / No / Infrequent or Never as applicable):

- In-App Controls: Parental Controls = No, Age Assurance = No
- Capabilities:
  - Unrestricted Web Access = No (we have no in-app browser; AsyncImage loads from controlled news/article URLs only)
  - User-Generated Content = YES — community personas. Users can publish a custom persona (`is_public=true`) visible to all other users with display name, description, character fields, and like counts. This is UGC by Apple's definition. Moderation: flag-on-card report flow is in `/CLAUDE.md` as a TODO; until shipped, we manually moderate via DB inspection of `personas` table rows. Apple will likely insist on a real report mechanism before approving — treat as a hard launch blocker.
  - Messaging and Chat = No (no user-to-user; the only conversational partner is the AI)
  - Advertising = No
- Mature Themes: Profanity or Crude Humor = None, Horror/Fear Themes = None, Alcohol/Tobacco/Drug Use or References = None
- Medical or Wellness: Medical/Treatment Information = No, Health/Wellness Topics = No
- Sexuality or Nudity: Mature/Suggestive Themes = None, Sexual Content or Nudity = None, Graphic Sexual Content/Nudity = None
- Violence: Cartoon/Fantasy Violence = None, Realistic Violence = None, Prolonged Graphic or Sadistic Realistic Violence = None
- Chance-Based Activities: Gambling = None, Simulated Gambling = None, Contests = None, Loot Boxes = None
- Made for Kids: No (audience is adults learning languages)

Expected result: 12+ age rating (the UGC declaration alone bumps the minimum from 4+ to 12+). If we want 4+, the path is to flip community personas to private-only at launch (drop the `is_public` flag from the launch build) and declare UGC = No — but that costs a designed discovery-loop feature.

### App Encryption Documentation

`ITSAppUsesNonExemptEncryption: false` in `ios/project.yml` (xcodegen writes it to Info.plist). Declares export-compliance EXEMPT — only standard OS encryption (TLS via URLSession / WebSocket), no custom crypto. No ASC UI action: at submission Apple reads the flag and skips the encryption-documentation prompt.

### App Store Regulations & Permits

#### Digital Services Act (EU)

Required to sell in the EU (EU Digital Services Act). Lives on the account-wide Business → Agreements page (same page as the Paid Apps Agreement below).

Legal entity Apple has on file (read-only): Hiroshi Nishio, 1619 Laguna St, San Francisco, CA 94115-3213, US. Account number 94389266. 175 of 175 territories.

##### DSA Trader Declaration — APPROVED

Declared "I'm a trader under the DSA" (Hiroshi acts in the course of business). On file:

- Trader name: Hiroshi Nishio
- Address: `717 Market St, San Francisco, CA 94103, US`
- Phone: +1-415-815-3853
- Email: `hello@palkietalkie.com`
- Proof: Japanese passport (name) + SS-5 (address).

Post-incorporation: re-declare with Palkie Talkie, Inc.'s registered agent address.

##### Paid Apps Agreement (also on this page) — REQUIRED before subscriptions can transact

Action: click "View and Agree to Terms" on the Paid Apps Agreement row → review (Apple 30%/15% split, payout schedule, refund handling, EU pricing rules, tax remittance) → Agree. Signing the agreement is just a contract; no revenue flows until subscriptions go live, so signing now does not implicate the O-1 work-authorization concern.

Sub-tasks Apple opens immediately after agreement is signed:

1. Banking Information — account holder name must match Developer Program account holder (Hiroshi Nishio). Use Wes's personal US bank account; provide routing + account numbers + voided check or bank letter.
2. Tax Forms — W-9 (Hiroshi has SSN and US-resident status). Fill in: name `Hiroshi Nishio`, federal tax classification `Individual/sole proprietor`, address `717 Market St, San Francisco, CA 94103` (matches DSA declaration), SSN, sign + date.
3. Tax Treaty Benefits / Country of Residence — declare United States.
4. Contact Information — re-confirms name/email/phone for billing.

Apple flips the Paid Apps row from "New" to "Active" within a few minutes after all four sub-sections submit. That clears the second launch blocker; the four subscription products can then be created in Subscriptions.

Open question to resolve with Wes's immigration attorney BEFORE actually enabling paid subscriptions (not before signing the agreement): receiving Apple revenue personally for Palkie Talkie sales is the same authorized-work concern that blocked the sole-prop DBA route. The agreement signing + banking setup is fine because no revenue moves yet. Going live with paid subs is the trigger event for the O-1 question. Run it past the attorney before that point.

##### Free Apps Agreement (also on this page)

Active, May 28, 2026 - May 27, 2027. Auto-renews yearly. Nothing to do.

#### China Mainland ICP Filing Number

NOT applicable at launch. We have no ICP filing, no in-country hosting, no QQ/WeChat tie-in. Skip the field AND exclude China Mainland from Availability. Revisit only with a concrete demand signal + a registered Chinese entity + filed ICP number.

#### Vietnam Game License

Required only for games. Palkie Talkie is an Education app. Skip / declare Not Applicable.

#### Regulated Medical Devices

Not a regulated medical device in any country/region (no medical claims).

### App Store Server Notifications

- Production Server URL: `https://palkietalkie-api.fly.dev/webhooks/apple/asn`
- Sandbox Server URL: `https://palkietalkie-api-dev.fly.dev/webhooks/apple/asn`
- Version: Version 2 Notifications (Version 1 is deprecated).

### App-Specific Shared Secret

- Value: `1399eb84c39440b8979bcb2620ca00f1`
- Stored in: `backend/.env`, `backend/.env.production`, Fly `palkietalkie-api-dev`, Fly `palkietalkie-api`.

### Additional Information

- View on App Store: (link appears post-launch)
- Edit User Access: leave default (Full Access — see CLAUDE.md team plan)
- Remove App: never use unless killing the listing

---

## App Privacy

URL: `https://appstoreconnect.apple.com/apps/6776366891/distribution/privacy`

### Privacy Policy

- Privacy Policy URL: `https://palkietalkie.com/privacy`
- User Privacy Choices URL (optional): `https://palkietalkie.com/privacy#choices` (anchor section explaining export/delete/opt-out controls)

### Data Collection Questionnaire

Click "Get Started". Answer each category as follows. Apple maps each YES into a chip on your App Store listing's "Data Linked to You" or "Data Not Linked to You" panel.

For EVERY data type below that we declare collected: linked to identity = Yes, used for tracking = No. (We do not track users across other companies' apps and websites.)

#### Contact Info

- Email Address: COLLECTED. Purposes: App Functionality, Analytics, Developer's Advertising or Marketing.
- Name: COLLECTED. Purposes: App Functionality.
- Phone Number: COLLECTED (optional Clerk auth). Purposes: App Functionality.
- Physical Address, Other User Contact Info: Not collected.

#### Health & Fitness

Not collected.

#### Financial Info

- Payment Info: Not collected (Apple StoreKit / Stripe handle cards; we never see numbers).
- Credit Info, Other Financial Info: Not collected.
- Purchase History: COLLECTED. Purposes: App Functionality.

#### Location

- Precise Location: Not collected. (Backend does receive lat/lon for weather lookup but stores only the city-resolution result.)
- Coarse Location: COLLECTED. Purposes: App Functionality.

#### Sensitive Info

Not collected.

#### Contacts

Not collected.

#### User Content

- Audio Data: COLLECTED. Purposes: App Functionality, Analytics, Product Personalization. (Mic recordings stream to OpenAI / PersonaPlex; we retain text transcripts.)
- Customer Support: COLLECTED. Purposes: App Functionality.
- Other User Content: COLLECTED. Purposes: App Functionality, Product Personalization. (Profile preferences, goals, knowledge-graph entities the user mentions in conversation.)
- Photos or Videos, Gameplay Content: Not collected.

#### Browsing History, Search History

Not collected.

#### Identifiers

- User ID: COLLECTED (Clerk user ID + internal UUID). Purposes: App Functionality, Analytics.
- Device ID: Not collected.

#### Purchases

(Covered by Financial Info → Purchase History above.)

#### Usage Data

- Product Interaction: COLLECTED. Purposes: App Functionality, Analytics. (Cold-start timings, session counts, mic-tap latency via `/events`.)
- Advertising Data, Other Usage Data: Not collected.

#### Diagnostics

- Crash Data: COLLECTED. Purposes: App Functionality. Linked to identity: No.
- Performance Data: COLLECTED. Purposes: App Functionality.
- Other Diagnostic Data: Not collected.

#### Surveys, Environment Scans, Other Data Types

Not collected.

#### Tracking

NONE of the collected categories are used for tracking across apps and websites owned by other companies. (Apple's "tracking" definition is narrow — analytics within our own products is not tracking.)

---

## Pricing and Availability

URL: `https://appstoreconnect.apple.com/apps/6776366891/distribution/pricing`

### Price Schedule

- Base Country or Region: United States (USD)
- Price tier: Free (Tier 0). All revenue is via in-app subscriptions.
- No price adjustments, no introductory or promotional offers at launch. Revisit after Stripe + IAP funnels have data.
- No pre-orders.

### App Availability

All 175 countries/regions INCLUDED except:

- China Mainland — no ICP filing number. Hard exclusion until we have a Chinese entity + filed ICP.

EU + EEA included via the TRADER declaration above. Everywhere else (US, UK, Japan, rest of APAC, LATAM, Middle East, Africa, Canada, Australia, NZ) is included.

### Tax Category

- App Store software (Apple's default for general iOS apps). Click "Edit" only if Apple later asks us to reclassify (e.g., a regulator dispute about education-app rates in a specific market).

### iPhone and iPad Apps on Apple Silicon Macs

- "Make this app available" = UNCHECKED.
- The app's audio path uses iOS-specific AVAudioEngine quirks (input voice-processing, AVAudioSession voiceChat mode interplay) that we have not validated on macOS. Defer until we have a Mac to test on.

### iPhone and iPad Apps on Apple Vision Pro

- "Make this app available on Apple Vision Pro" = UNCHECKED.
- Voice-first product; no spatial UX advantage. Revisit when Vision Pro has a meaningful install base.

### App Distribution Methods

- Public — Discoverable by anyone on the App Store. SELECTED (default).
- Apple School Manager / Private (custom app for Business Manager) — UNSELECTED.

---

## Subscriptions

URL: `https://appstoreconnect.apple.com/apps/6776366891/distribution/subscriptions`

Note: Apple requires the first subscription to be submitted with a NEW APP VERSION (i.e., during your first 1.0 submission). Create the group + products and attach them to the Version 1.0 submission.

### Subscription Groups

Create ONE group. Apple enforces "one active subscription per group" so users can upgrade/downgrade between tiers without holding two simultaneous.

- Reference Name (internal, not user-facing): `Palkie Talkie Premium`
- Localization (English U.S.):
  - Display Name: `Palkie Talkie Premium`
  - Custom App Name (optional): leave blank

### Auto-Renewable Subscriptions

Products and groups are code SSoT — `backend/app/iap/subscriptions_list.py` (products: ids, durations, prices, localizations, Stripe links) and `backend/app/iap/subscription_groups_list.py` (group display names). Do NOT copy any of it here. Push to ASC with the scripts under `backend/scripts/asc/`: `create_iap_subscriptions.py`, `set_subscription_group_metadata.py`, `equalize_subscription_prices.py`, `localize_iap_subscriptions.py`, `set_iap_availability.py`, `generate_iap_screenshots.py` + `upload_iap_screenshots.py`, `submit_iap_subscriptions.py`.

ASC-only settings (no code source):

- Family Sharing: ENABLED for the two Family products, DISABLED for the two Individual products.
- Tax Category: inherit from app (App Store software).
- Review screenshot: one per product — `generate_iap_screenshots.py` + `upload_iap_screenshots.py`.
- Introductory / Promotional Offers / Offer Codes: NONE at launch.

### Billing Grace Period

- Set Billing Grace Period to 16 days (Apple's recommended default) — retains access while Apple retries a failed renewal.

### Streamlined Purchasing

- Keep "Turned On" (default).

### Non-Renewing Subscriptions

- None.

---

## TestFlight

External group: `Beta Testers`. Public link: https://testflight.apple.com/join/AHFTKrG9 (installable once the build clears Beta App Review).

### Beta App Description (TestFlight Test Information)

```text
Palkie Talkie is a voice-first English conversation app. When you open it, an AI tutor with a real personality starts talking to you out loud and you reply by speaking naturally — it's full-duplex, so it listens while it talks and you can interrupt. It remembers past conversations so it feels like talking to someone who knows you.

To test: sign in (see Sign-In Information), then on the Talk tab the tutor begins speaking on its own — respond out loud and have a back-and-forth. Try the persona picker to switch tutor characters, the "What to talk about today" tab for prompts, and the Stats tab for speaking metrics.

Note: paid subscriptions are not active yet (products pending), so the Subscription screen intentionally shows "Upgrades not available yet." That is expected, not a bug.
```

### What to Test (shown to testers when you add the build to a group)

```text
The AI tutor starts talking on its own when you open the app — reply out loud and have a real back-and-forth (you can interrupt it mid-sentence). Try switching tutor personas and check the Stats tab. Tell us where the voice felt slow or cut out, where a correction sounded wrong, and anything that crashed or felt off.
```

When adding the build, leave "Automatically notify testers" CHECKED — testers are then auto-notified the moment the build clears Beta review.

Sign-In Information, Feedback Email, and Notes for the TestFlight beta are the same as the App Review Information section below — passwordless (Sign in with Apple), feedback `hello@palkietalkie.com`, privacy `https://palkietalkie.com/privacy`.

---

## 1.0 Prepare for Submission

URL: `https://appstoreconnect.apple.com/apps/6776366891/distribution/ios/version/inflight`

### Previews and Screenshots

Apple requires AT LEAST one set. Submit 6.9" iPhone Pro Max as the primary; Apple uses it as the fallback for other sizes.

#### iPhone — 6.5" Display (1242 × 2688 px or 2688 × 1242 px landscape, OR 1284 × 2778 px / 2778 × 1284 px for newer sizes)

Recommend 5 screenshots in this order:

1. Hero — mic screen mid-conversation. Persona name banner top, last AI bubble + user bubble showing, mic active state.
2. Persona picker — grid of personas (Comedian, Mentor, Idioms guide, Coach) with hearts + tags.
3. Today screen — horizontal scroll of Politics / Business / Sports with real images + Quizzes section.
4. Stats — day-streak hero (🔥 X days in a row) + metric grid.
5. Profile — language pair selector (target / native / proficiency / speed).

App Previews (optional, up to 3): single 15–30 sec video showing app open → AI starts talking → user replies → AI corrects with vocal stress.

#### iPad and Apple Watch

Skip. We're iOS-only (iPhone) and not building iPad/Watch presence at launch.

### Listing copy (Promotional Text, Description, Keywords, Support URL, Marketing URL)

Code SSoT in `backend/app/asc/metadata/<locale>/*.txt` (fastlane `deliver` folder layout — one file per field: `name`, `subtitle`, `description`, `keywords`, `promotional_text`, `support_url`, `marketing_url`). Push with `backend/scripts/asc/set_app_metadata.py` (idempotent PATCH of the appStoreVersionLocalization + appInfoLocalization). Do NOT copy the strings here — that copy is exactly what drifts. Edit the `.txt` file, re-run the script.

### Version

`1.0`

### Copyright

- Pre-incorporation (current): `© 2026 Wes Nishio`
- Post-incorporation: `© 2026 Palkie Talkie, Inc.`

### Routing App Coverage File

Skip. We don't provide map-routing.

### App Clip / iMessage App

Skip both. Not building either surface at launch.

### Build

`ios/scripts/release.sh` — archive → export → upload. Build number auto-set from git commit count; creds from `ios/.env`; prod baked via project.yml (`api.palkietalkie.com` + `pk_live` Clerk); team `7P7YY88H3V`.

### Game Center

UNCHECKED. Not a game.

### App Review Information

#### Sign-In Information

- "Sign-in required": CHECKED.
- User Name: `Use "Sign in with Apple" — passwordless app`
- Password: `No password required`

The reviewer signs in by tapping "Sign in with Apple" with their own Apple ID (instant account, no password). The User Name / Password fields are free text Apple doesn't validate, so they carry the instruction.

##### Why (reference, not a field to fill)

- The app is passwordless (Sign in with Apple / Google / email one-time-code only), so a username/password reviewer account can't work, and an email-code account is useless to the reviewer (they can't read its inbox).
- "Sign-in required" must stay CHECKED: the app gates everything behind login, so unchecking it tells Apple no account is needed → reviewer hits the login wall → rejection.
- Verified on prod Clerk (`clerk.palkietalkie.com`, via `/v1/environment`): Apple + Google + email one-time-code all enabled; password not required.
- Launch is free-first (subscriptions not live), so the reviewer lands on the only tier; the Subscription screen showing "Upgrades not available yet" is expected, not a bug.

#### Contact Information

- First name: Wes
- Last name: Nishio
- Phone number: +1-415-815-3853
- Email: `hello@palkietalkie.com`

#### Notes

```text
Palkie Talkie is a voice language learning app. The user holds the mic open, talks to an AI persona, and gets gentle corrections embedded in the AI's reply.

Microphone permission: REQUIRED — the entire product is voice. Audio streams to OpenAI Realtime (paid users) or OpenAI Realtime mini (free users); text transcripts are stored in our backend.

Camera permission: NOT requested. No camera use.

Push notification permission: optional. Used for scheduled-practice reminders if the user opts in via Integrations.

Sign-in is passwordless: please tap "Sign in with Apple" on the launch screen and use your own Apple ID (instant account, no password). The app is free-tier at launch (paid subscriptions are not yet live), so all features — personas, Today content, Stats, full voice conversation — are available; the Subscription screen showing "Upgrades not available yet" is expected, not a bug.

Subscription management is delegated to iOS Settings → [Apple ID] → Subscriptions per Apple's standard. The paywall and the More tab both link to that destination and display auto-renew + cancellation terms.

The app does not contain news, religious, book, or magazine content that would require Chinese permits (we exclude China Mainland from Availability anyway).
```

#### Attachment

None.

### App Store Version Release

Select: "Manually release this version" — we click "Release This Version" after approval to control timing.

---

## Still pending

| Item | Where | Note |
|---|---|---|
| App Store listing screenshots | real-app captures, 5 × 6.9" PNG | Must show the real app (Guideline 2.3) — not the synthetic IAP placeholders |
| App Preview video (optional) | iOS Simulator → screen record + cut | Optional |
| Convert Apple account Individual → Org (Gitauto) | developer.apple.com/contact + D-U-N-S 14-510-0478 | Required before paid subscriptions (see /CLAUDE.md) |
| Manual "Save" passes in each App Store Connect page | UI clicks | Wes operates the UI |
