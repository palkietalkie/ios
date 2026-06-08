# App Store Connect — Palkie Talkie

Apple ID: `6776366891`. Team: `129df326-897e-414d-acda-0e89b6b4f653`. Developer account number: `94389266`.

---

## App Information

URL: `https://appstoreconnect.apple.com/apps/6776366891/distribution/info`

### Localizable Information (English U.S.)

- Name: `Palkie Talkie`
- Subtitle (30 char max): `AI voice partner for fluency` (28 chars)

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

Already handled. `ITSAppUsesNonExemptEncryption: false` is set in `ios/project.yml` so xcodegen writes it into `Info.plist` on every build. This declares EXEMPT from export-compliance / CCATS documentation — we use only standard encryption provided by Apple's OS (TLS via URLSession / WebSocket; no proprietary or non-standard crypto).

Nothing to do in the App Store Connect UI. At submission time, App Store Connect reads the Info.plist flag and skips the "Encryption documentation is required" prompt.

### App Store Regulations & Permits

#### Digital Services Act (EU)

Required to sell in the EU. Click "Set Up" — Apple opens the account-wide Business → Agreements page, which also surfaces the Paid Apps Agreement (separate launch blocker, see sub-section below).

The legal entity Apple already has on file (read-only):

- Name: Hiroshi Nishio (legal first name on Developer Program enrollment; Wes uses "Wes" elsewhere)
- Address: 1619 Laguna St, San Francisco, CA 94115-3213, United States
- Account number: 94389266
- Territories covered: 175 of 175

##### DSA Trader Declaration (SUBMITTED)

Apple opens a modal with two radio options. Pick "I'm a trader under the DSA". Hiroshi is legally a trader under the DSA definition (acting in the course of business).

Values entered:

- Trader name: Hiroshi Nishio (matches Developer Program enrollment)
- Address: `717 Market St, San Francisco, CA 94103, US` (entered without the `5F` floor prefix or `#100` suite; the SS-5 uploaded as proof shows the full `5F, 717 Market St #100` — substring match should pass Apple's check, but if rejected, re-submit with the full form)
- Phone: +1-415-815-3853
- Email: `hello@palkietalkie.com`

After the values screen, Apple asks for verification documents:

1. Name Identification Document — uploaded Japanese passport.
2. Address Identification Document — uploaded SS-5 (Social Security card application, dated 04/07/2026, signed by Hiroshi, mailing address `5F, 717 Market St #100, San Francisco, CA 94103`). The SS-5 satisfies "business or court documentation that confirms your name" because it's a federal government form with name + matching address.

Apple sends verification email to `hello@palkietalkie.com`; click the link. Banner clears.

Post-incorporation: re-open this modal and swap to Palkie Talkie, Inc.'s registered agent address.

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

Apple's UI already shows: "This app has been declared not a regulated medical device in any country or region." Confirmed correct — we make no medical claims.

### App Store Server Notifications

(Already configured.)

- Production Server URL: `https://palkietalkie-api.fly.dev/webhooks/apple/asn`
- Sandbox Server URL: `https://palkietalkie-api-dev.fly.dev/webhooks/apple/asn`
- Version: Version 2 Notifications (Version 1 is deprecated).

### App-Specific Shared Secret

(Already generated.)

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

### Auto-Renewable Subscriptions (4 products in the group above)

Each one is Type: Auto-Renewable Subscription.

| Product ID | Reference Name | Duration | Price (US) |
|---|---|---|---|
| `com.palkietalkie.app.individual.monthly` | Individual Monthly | 1 Month | $17.99 |
| `com.palkietalkie.app.individual.annual` | Individual Annual | 1 Year | $83.99 |
| `com.palkietalkie.app.family.monthly` | Family Monthly | 1 Month | $19.99 |
| `com.palkietalkie.app.family.annual` | Family Annual | 1 Year | $112.99 |

Per product, set:

- Subscription Group: `Palkie Talkie Premium`
- Subscription Duration: as above
- Availability: All countries (default)
- Price Schedule: tier matching the USD price, let Apple auto-convert other currencies
- Tax Category: inherit from app (App Store software)
- Family Sharing: ENABLED for the two Family products; DISABLED for the two Individual products
- Localization (English U.S.):
  - Display Name (user-visible on paywall): "Individual — Monthly" / "Individual — Annual" / "Family — Monthly (up to 6 users)" / "Family — Annual (up to 6 users)"
  - Description: 1-2 sentence summary. e.g. for Individual Monthly: "Unlimited daily voice practice with your AI partner. Cancel anytime."
- Review Screenshot: a screenshot of the iOS paywall showing this product's card. Required per product even though it's the same paywall.
- Promotional Image: (optional 1024×1024 PNG used in subscription offers)
- Introductory Offer / Promotional Offer / Offer Codes: NONE at launch.

### Billing Grace Period

- Click "Set Up Billing Grace Period" and choose 16 days (Apple's recommended default).
- Rationale: if a renewal fails because the user's card declined, retain premium access for 16 days while Apple retries. Increases recovered MRR vs the equivalent value of giving away free service.

### Streamlined Purchasing

- Already "Turned On" by default. Keep it on.
- This lets Apple offer the subscription via external surfaces (Search, Family Sharing prompts) without bouncing through our paywall.

### Non-Renewing Subscriptions

- None.

---

## 1.0 Prepare for Submission

URL: `https://appstoreconnect.apple.com/apps/6776366891/distribution/ios/version/inflight`

This page holds the actual App Store listing assets, plus App Review handoff info, plus the release-timing choice.

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

### Promotional Text (170 char max — updatable without resubmission)

```text
Practice English out loud — anytime, anywhere. Your AI voice partner remembers what you said last time and never gets tired of helping you get it right.
```

(158 chars)

### Description (4000 char max)

```text
Palkie Talkie is the voice practice partner you wish you had.

Speak English (and more languages soon) out loud, without booking a tutor, turning a camera on, or feeling watched. Walking to work, in the car, in the gym, before bed — open the app and start talking.

WHY PALKIE TALKIE

• REAL CONVERSATION, NOT DRILLS. No fill-in-the-blanks. No multiple choice. You talk, the AI listens, replies in character, and corrects you when something sounds off.

• REMEMBERS YOU. Talk about your tennis serve on Monday — on Friday it asks how the match went. Conversations build on each other instead of resetting.

• PICK A PERSONA. A sharp comedian, a patient mentor, an idiom-loving polyglot, a tennis coach. Each one has a real character and their own way of pulling words out of you.

• CORRECTIONS WITHOUT THE CRINGE. When you slip — wrong word, dropped article, awkward phrasing — the AI echoes back the natural way to say it, with a gentle vocal stress on the fix. No "actually," no teacher voice.

• TIPS, RUMORS, AND HEADLINES. The "Today" screen feeds you fresh news, sports, politics, and quiz prompts so you always have something to talk about.

• REAL PROGRESS. Stats screen shows your day streak, talking minutes, vocabulary breadth, speaking rate, pitch range, CEFR vocab coverage, and a list of the mistakes you keep making.

WHO IT'S FOR

Anyone who can read this — but freezes when it's time to say it out loud. Functional but not fluent. Lives the language abroad but doesn't speak enough at work. Watches the meeting from the side because joining feels too risky.

We're starting with English for non-native speakers, then expanding to every major language pair.

PRIVACY

Your conversations are stored under your account to power the personalization. We never sell them to third parties. You can export everything or delete it any time from More → Privacy & Data.

PRICING

Free tier — 10 minutes of conversation per day, 30 minutes per week. Individual $17.99/month or $83.99/year. Family up to 6 users $19.99/month or $112.99/year. All paid plans auto-renew unless cancelled at least 24 hours before the period ends; manage in Settings → [your Apple ID] → Subscriptions.

Privacy: https://palkietalkie.com/privacy
Terms: https://palkietalkie.com/terms
Support: https://palkietalkie.com/support
```

### Keywords (100 char max, comma-separated, no spaces after commas)

```text
english,speak,fluency,conversation,voice,AI,tutor,toefl,ielts,pronunciation,vocabulary,daily,practice
```

(95 chars)

### Support URL

`https://palkietalkie.com/support`

### Marketing URL (optional)

`https://palkietalkie.com`

### Version

`1.0`

### Copyright

- Pre-incorporation (current): `© 2026 Wes Nishio`
- Post-incorporation: `© 2026 Palkie Talkie, Inc.`

Apple's convention is "© [first publication year] [holder]". Year stays 2026 (the year the app first ships) even in later updates — most teams don't change it annually unless they rewrite copyrightable content top-to-bottom.

### Routing App Coverage File

Skip. We don't provide map-routing.

### App Clip / iMessage App

Skip both. Not building either surface at launch.

### Build

Upload via Xcode → Product → Archive → Organizer → Distribute App → App Store Connect. Or use Transporter app for an already-archived `.ipa`. Pending — build pipeline not yet run end-to-end.

### Game Center

UNCHECKED. Not a game.

### App Review Information

#### Sign-In Information

Check "Sign-in required".

- User Name: `wesnishio+ptreview@gmail.com`
- Password: `PTreview-2026-pcAxYRGzKn`

Notes: Account pre-flagged `premium=true` in PROD so the reviewer sees full feature set without paying. Mailbox is Wes's Gmail with a `+ptreview` alias (verification mail receivable; inbox not shared). Clerk user `user_3Ee4YCP3wQXPL8MGUe1vG7n79DL`; DB row `8ed46497-b345-43fc-9d2c-a10fb911c26b`.

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

The test account in Sign-In Information above is pre-flagged premium so the reviewer sees the full feature set including all personas, Today screen content, Stats history, and unlimited talk time without paying.

Subscription management is delegated to iOS Settings → [Apple ID] → Subscriptions per Apple's standard. The paywall and the More tab both link to that destination and display auto-renew + cancellation terms.

The app does not contain news, religious, book, or magazine content that would require Chinese permits (we exclude China Mainland from Availability anyway).
```

#### Attachment

None.

### App Store Version Release

Select: "Manually release this version"

Rationale: gives us control to align the public release with the marketing push (DM-the-network day, content drop, podcast slot if any). After Apple approves, we click "Release This Version" when ready.

---

## What still needs to be done elsewhere

| Item | Where | Status |
|---|---|---|
| Privacy Policy page | `website/src/app/privacy/page.tsx` | Done |
| Terms page | `website/src/app/terms/page.tsx` | Done |
| Support page | `website/src/app/support/page.tsx` | Done |
| Privacy Policy hosted live | palkietalkie.com/privacy | Pending — needs website deploy |
| Set `ITSAppUsesNonExemptEncryption=false` in iOS Info.plist | `ios/PalkieTalkie/Info.plist` | Pending — verify present |
| Test reviewer Clerk account (PROD) | Clerk + prod Neon DB | Done |
| Screenshots | iOS Simulator → export 5 × 6.9" PNG | Pending |
| App Preview video (optional) | iOS Simulator → screen record + cut | Pending |
| App build (.ipa) | xcodebuild Archive → Transporter upload | Pending |
| Subscription review screenshots | one screenshot per of the 4 products | Pending — paywall screen with each product highlighted |
| Manual "Save" passes in each App Store Connect page | UI clicks | Pending — Wes operates the UI |
