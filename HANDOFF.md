# Handoff: AccountLocation Google Maps Suggested Coordinates

## What this is

A **Suggest Location (Google)** quick action button on `ogg__Location__c` starts a background job. The job sends the customer's single-field address (`Account.Address__c`) to Google Maps. It writes Google's coordinates to `Suggested_Latitude__c` / `Suggested_Longtitude__c`, and the distance in meters from UPWARD's pin to `Different_Distance__c`. The search is tuned for Thai addresses: it removes room and floor details, expands abbreviations, and checks the postcode. Nothing runs automatically; an earlier version used a trigger, which this replaces.

How it works: [docs/HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md) · Deployment: [docs/DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md) · Testing: [docs/TESTING_GUIDE.md](docs/TESTING_GUIDE.md)

## Current status (2026-11-17)

| Item | Status |
|---|---|
| Code | On `main` in `Chaipitch/tter`. The latest change replaces the trigger with the quick action button |
| Sandbox `tterakit-sb` | The **trigger version** is deployed (validated: metadata 27/27, Apex tests 32/32). The **button version is not deployed yet**. Until it is, the old trigger keeps running on every new oggLocation |
| Button version | **Not compiled or run in an org yet.** The LWC and quick action are new |
| Google API key / custom setting | **Not confirmed.** Nothing happens until the org default of `Google_Maps_Settings__c` has *Enabled* checked and an API key |
| Tests against real Google | **Not done yet.** All Apex tests use an HTTP mock |
| Production | Not deployed |

## Next steps

1. **Deploy the button version to `tterakit-sb` and remove the old trigger in the same deployment** (`--post-destroy manifest/destructiveChanges.xml`). Validate first. The commands are in [DEPLOYMENT_GUIDE §3](docs/DEPLOYMENT_GUIDE.md#3-deploy).
2. **Google Cloud:** enable billing, then the **Geocoding API** and **Places API (New)**. Create an API key restricted to those two APIs, and set daily quotas. ([DEPLOYMENT_GUIDE §2](docs/DEPLOYMENT_GUIDE.md#2-google-maps-platform-setup))
3. **Turn it on:** paste the key into `scripts/apex/configure-settings.apex`, then run:

   ```bash
   sf apex run --file scripts/apex/configure-settings.apex --target-org tterakit-sb
   ```

   Afterwards run `git checkout` on the file so the key is never committed.
4. **Access and button:**

   ```bash
   sf org assign permset --name AccountLocation_Geocoding --target-org tterakit-sb
   ```

   Then add **Suggest Location (Google)** and the three fields to the oggLocation page ([DEPLOYMENT_GUIDE §3.5](docs/DEPLOYMENT_GUIDE.md#35-put-the-button-on-the-record-page)).
5. **Check one address** against real Google (creates no records):

   ```bash
   sf apex run --file scripts/apex/test-geocode-address.apex --target-org tterakit-sb
   ```

   Expect `postcodeMatch=true`.
6. **Test with real data:** run TC-01 – TC-12 in [TESTING_GUIDE](docs/TESTING_GUIDE.md). The most important is TC-03: 10–20 real customer addresses where UPWARD's pin is known to be wrong, checked in Google Maps. Agree with the business what distance counts as wrong. The guide suggests over 50 m needs review and over 500 m is probably wrong.
7. **Many records at once** (optional): run `scripts/apex/regeocode-existing.apex`.
8. **Production:** the same deploy command **without** `--post-destroy`, a production API key and quota, then steps 3–4 and 7.

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
| `force-app/main/default/quickActions/ogg__Location__c.Suggest_Google_Location.quickAction-meta.xml` | The **Suggest Location (Google)** button |
| `force-app/main/default/lwc/suggestGoogleLocation/` | Headless action: start job → poll status → refresh record → toast |
| `force-app/main/default/classes/` | `AccountLocationGeocodeAction` (Apex behind the button), `AccountLocationGeocodeQueueable`, `GoogleGeocodingService`, `ThaiAddressNormalizer`, `GeoDistanceUtil`, `GoogleMapsSettings`, plus tests, `GoogleMapsCalloutMock` and `TestRecordFactory` |
| `force-app/main/default/objects/Google_Maps_Settings__c/` | Custom setting: key, on/off switch, country/region/language, Places fallback, field names, batch size, timeout |
| `force-app/main/default/remoteSiteSettings/` | `maps.googleapis.com`, `places.googleapis.com` |
| `force-app/main/default/permissionsets/AccountLocation_Geocoding` | Access to the button's Apex class + read access to the three target fields |
| `manifest/package.xml` | What gets deployed (target fields excluded on purpose) |
| `manifest/destructiveChanges.xml` | Removes the old trigger + handler (only for orgs that had them, i.e. `tterakit-sb`) |
| `scripts/apex/` | `configure-settings`, `test-geocode-address`, `regeocode-existing` |

Deploy and test commands are in [DEPLOYMENT_GUIDE §3](docs/DEPLOYMENT_GUIDE.md#3-deploy) (four test classes: `AccountLocationGeocodingTest`, `GoogleGeocodingServiceTest`, `GeoDistanceUtilTest`, `ThaiAddressNormalizerTest`).

## Operating it

| Need | How |
|---|---|
| Switch off immediately | Uncheck *Enabled* in Setup → Custom Settings → Google Maps Settings (the button then says it's turned off), or remove the button from the page |
| See whether it ran | Setup → Apex Jobs → `AccountLocationGeocodeQueueable` |
| See why a record has no suggestion | Debug log of the **user who clicked**. Typical messages: `No Google Maps result`, `Geocoding API status REQUEST_DENIED` / `OVER_QUERY_LIMIT` |
| See what was sent to Google for an address | `scripts/apex/test-geocode-address.apex` (prints the cleaned variants, source, `postcodeMatch`) |
| Fill in many records at once | `scripts/apex/regeocode-existing.apex` |
| Change the API key or options | Edit the custom setting; no deployment needed |

## Known limitations / possible follow-ups

1. **Manual only.** New or changed addresses get a suggestion only when someone clicks the button (or the back-fill script runs). A possible follow-up: a list view button for several selected records.
2. **Address cleaning uses fixed rules.** New ways of writing room, floor or building can slip through. Add the pattern to `ROOM_PATTERN` / `FLOOR_PATTERN` / `BUILDING_PATTERN` in `ThaiAddressNormalizer`, with a case in `ThaiAddressNormalizerTest`. The patterns were checked in Java, which uses the same regex engine as Apex.
3. **No audit fields.** The source used (Geocoding or Places), the query and the postcode match only go to the debug log. Fields for these would make reviewing easier.
4. **40-second wait in the browser.** If the job queue is slow, the toast says *Still running*; the values appear after a refresh.
5. **Cost.** Each click makes 1–3 Google requests: Geocoding first, Places only as a fallback. Keep quotas set in Google Cloud, and check current Google Maps Platform pricing against the expected volume.

## History

| PR | Change |
|---|---|
| [#1](https://github.com/Chaipitch/tter/pull/1) | Initial implementation, Thai address handling, guides |
| [#2](https://github.com/Chaipitch/tter/pull/2) | Object renamed to `ogg__Location__c` |
| [#3](https://github.com/Chaipitch/tter/pull/3) | Account lookup detected at run time (later replaced); cast fix in a test |
| [#4](https://github.com/Chaipitch/tter/pull/4) | Account linked through `ogg__ObjectId__c`; existing org fields used; tests fixed (settings in memory, `TestRecordFactory`) |
| [#5](https://github.com/Chaipitch/tter/pull/5) | Fallback test fixed (`ogg__ObjectId__c` is required) |
| [#6](https://github.com/Chaipitch/tter/pull/6) | HOW_IT_WORKS.md and HANDOFF.md |
| next | Trigger replaced by the **Suggest Location (Google)** quick action button; old trigger removed with `destructiveChanges.xml` |
