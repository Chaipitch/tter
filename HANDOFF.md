# Handoff: AccountLocation Google Maps Suggested Coordinates

## What this is

When UPWARD creates an `ogg__Location__c` record, Apex sends the customer's single-field address (`Account.Address__c`) to Google Maps. It writes Google's coordinates to `Suggested_Latitude__c` / `Suggested_Longtitude__c`, and the distance in meters from UPWARD's pin to `Different_Distance__c`. The search is tuned for Thai addresses: it removes room and floor details, expands abbreviations, and checks the postcode.

How it works: [docs/HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md) · Deployment: [docs/DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md) · Testing: [docs/TESTING_GUIDE.md](docs/TESTING_GUIDE.md)

## Current status (2026-11-17)

| Item | Status |
|---|---|
| Code | On `main` in `Chaipitch/tter` (PRs #1–#5 merged) |
| Sandbox `tterakit-sb` | **Validated and deployed.** Metadata 27/27; Apex tests 32/32 passing |
| Google API key / custom setting | **Not confirmed.** The feature does nothing until the org default of `Google_Maps_Settings__c` has *Enabled* checked and an API key |
| Tests against real Google | **Not done yet.** All Apex tests use an HTTP mock |
| Back-fill of existing records | Not done |
| Production | Not deployed |

## Next steps

1. **Google Cloud:** enable billing, then the **Geocoding API** and **Places API (New)**. Create an API key restricted to those two APIs, and set daily quotas. ([DEPLOYMENT_GUIDE §2](docs/DEPLOYMENT_GUIDE.md#2-google-maps-platform-setup))
2. **Turn it on:** paste the key into `scripts/apex/configure-settings.apex`, then run:

   ```bash
   sf apex run --file scripts/apex/configure-settings.apex --target-org tterakit-sb
   ```

   Afterwards run `git checkout` on the file so the key is never committed.
3. **Access:**

   ```bash
   sf org assign permset --name AccountLocation_Geocoding --target-org tterakit-sb
   ```

   Then put the three fields on the oggLocation page layout.
4. **Check one address** against real Google (creates no records):

   ```bash
   sf apex run --file scripts/apex/test-geocode-address.apex --target-org tterakit-sb
   ```

   Expect `postcodeMatch=true`.
5. **Test with real data:** run TC-01 – TC-12 in [TESTING_GUIDE](docs/TESTING_GUIDE.md). The most important is TC-03: 10–20 real customer addresses where UPWARD's pin is known to be wrong, checked in Google Maps. Agree with the business what distance counts as wrong. The guide suggests over 50 m needs review and over 500 m is probably wrong.
6. **Back-fill old records** (optional): run `scripts/apex/regeocode-existing.apex`.
7. **Production:** same deploy command, a production API key and quota, then steps 2–3 and 6.

## Org facts the code relies on

| Item | API name | Notes |
|---|---|---|
| AccountLocation object | `ogg__Location__c` | ogg managed package (label "oggLocation") |
| Link to Account | `ogg__ObjectId__c` (Text 18) + `ogg__prefix__c` | **No lookup field.** Both are required. The prefix is `001` for Account |
| Address | `Account.Address__c` | If `ogg__ObjectId__c` isn't an Account Id: `ogg__Location__c.ogg__RawAddress__c` |
| UPWARD's pin | `ogg__Latitude__c`, `ogg__Longitude__c` | Number(4,10) |
| Target fields | `Suggested_Latitude__c`, `Suggested_Longtitude__c`, `Different_Distance__c` | Already in the org and **not** in this project. Note the spelling *Longtitude* |
| Required Account fields | e.g. `Tax_ID__c`, `Customer_Type__c`, `Company__c` | Filled automatically in tests by `TestRecordFactory` |

## Where things are

| Path | What |
|---|---|
| `force-app/main/default/triggers/AccountLocationTrigger.trigger` | after insert → queue job; before update → recalculate distance |
| `force-app/main/default/classes/` | `AccountLocationTriggerHandler`, `AccountLocationGeocodeQueueable`, `GoogleGeocodingService`, `ThaiAddressNormalizer`, `GeoDistanceUtil`, `GoogleMapsSettings`, plus tests, `GoogleMapsCalloutMock` and `TestRecordFactory` |
| `force-app/main/default/objects/Google_Maps_Settings__c/` | Custom setting: key, on/off switch, country/region/language, Places fallback, field names, batch size, timeout |
| `force-app/main/default/remoteSiteSettings/` | `maps.googleapis.com`, `places.googleapis.com` |
| `force-app/main/default/permissionsets/AccountLocation_Geocoding` | Read access to the three target fields |
| `manifest/package.xml` | What gets deployed (target fields excluded on purpose) |
| `scripts/apex/` | `configure-settings`, `test-geocode-address`, `regeocode-existing` |

Deploy and test commands are in [DEPLOYMENT_GUIDE §3](docs/DEPLOYMENT_GUIDE.md#3-deploy) (four test classes: `AccountLocationGeocodingTest`, `GoogleGeocodingServiceTest`, `GeoDistanceUtilTest`, `ThaiAddressNormalizerTest`).

## Operating it

| Need | How |
|---|---|
| Switch off immediately | Uncheck *Enabled* in Setup → Custom Settings → Google Maps Settings |
| Skip it during a data load (Apex) | `AccountLocationTriggerHandler.bypass = true;` |
| See whether it ran | Setup → Apex Jobs → `AccountLocationGeocodeQueueable` |
| See why a record has no suggestion | Debug log of the **Automated Process** user. Typical messages: `No Google Maps result`, `Geocoding API status REQUEST_DENIED` / `OVER_QUERY_LIMIT` |
| See what was sent to Google for an address | `scripts/apex/test-geocode-address.apex` (prints the cleaned variants, source, `postcodeMatch`) |
| Fill in missed or old records | `scripts/apex/regeocode-existing.apex` |
| Change the API key or options | Edit the custom setting; no deployment needed |

## Known limitations / possible follow-ups

1. **Address changes aren't re-checked.** Only *new* `ogg__Location__c` records are looked up. If UPWARD updates an existing location when `Account.Address__c` changes, the suggestion goes stale. A possible follow-up: also queue a lookup on update when `ogg__RawAddress__c` changes.
2. **Address cleaning uses fixed rules.** New ways of writing room, floor or building can slip through. Add the pattern to `ROOM_PATTERN` / `FLOOR_PATTERN` / `BUILDING_PATTERN` in `ThaiAddressNormalizer`, with a case in `ThaiAddressNormalizerTest`. The patterns were checked in Java, which uses the same regex engine as Apex.
3. **No audit fields.** The source used (Geocoding or Places), the query and the postcode match only go to the debug log. Fields for these would make reviewing easier.
4. **Enqueue limit.** Records inserted from asynchronous code that has already used its enqueue slot are skipped with a log message. Run the back-fill script for those.
5. **UPWARD in tests.** Inserting an Account with an address in a test may make UPWARD create its own locations. The tests avoid exact callout counts for that reason.
6. **Cost.** Each new location makes 1–3 Google requests: Geocoding first, Places only as a fallback. Keep quotas set in Google Cloud, and check current Google Maps Platform pricing against the expected volume.

## History

| PR | Change |
|---|---|
| [#1](https://github.com/Chaipitch/tter/pull/1) | Initial implementation, Thai address handling, guides |
| [#2](https://github.com/Chaipitch/tter/pull/2) | Object renamed to `ogg__Location__c` |
| [#3](https://github.com/Chaipitch/tter/pull/3) | Account lookup detected at run time (later replaced); cast fix in a test |
| [#4](https://github.com/Chaipitch/tter/pull/4) | Account linked through `ogg__ObjectId__c`; existing org fields used; tests fixed (settings in memory, `TestRecordFactory`) |
| [#5](https://github.com/Chaipitch/tter/pull/5) | Fallback test fixed (`ogg__ObjectId__c` is required) |
