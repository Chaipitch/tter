# Handoff: AccountLocation Google Maps Suggested Coordinates

## What this is

The customer's single-field address (`Account.Address__c`) of `ogg__Location__c` records is sent to Google Maps. Google's coordinates are written to `Suggested_Latitude__c` / `Suggested_Longtitude__c`, and the distance in meters from UPWARD's pin to `Different_Distance__c`. Four ways it runs:

* **Automatically when an oggLocation is created** (`AccountLocationTrigger`, after insert). It can be switched off with *Disable Lookup On Create* in the custom setting, for example for large data loads.
* **List view button "Suggest Locations (Google)"**: the ticked records, or, with nothing ticked, **all records not processed yet (`isCoordsUpdated__c` unchecked)**. Processed records get `isCoordsUpdated__c` = true and are skipped by later automatic runs.
* **Nightly schedule** (optional) over all records not processed yet.
* **Record button "Suggest Location (Google)"**: one record, with the result in a toast.

The list view button and the schedule handle **large volumes** (Batch Apex): existing records, records the trigger skipped, and re-checks. The search is tuned for Thai addresses: it removes room and floor details, expands abbreviations, and checks the postcode.

How it works: [docs/HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md) · Deployment: [docs/DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md) · Testing: [docs/TESTING_GUIDE.md](docs/TESTING_GUIDE.md)

## Current status (2026-11-18)

| Item | Status |
|---|---|
| Code | On `main` in `Chaipitch/tter` (PRs #1–#12 merged) |
| Sandbox `tterakit-sb` | Record button, list view button + Batch Apex + schedule, `isCoordsUpdated__c` handling and the OpenStreetMap option are **deployed and validated**. The **on-create trigger** (brought back alongside the buttons) **is not deployed yet** |
| Provider | **OpenStreetMap** (temporary, no key) is configured in `tterakit-sb`. The probe script returned the Emporium building (`OSM_RANK_30`) with a postcode match |
| Google API key | **Not available yet** |
| Org setup after the last deploy | **Not confirmed:** permission set re-assigned, list view button added to the List View Button Layout, record button on the page layout, one-off flagging of records processed before `isCoordsUpdated__c` existed |
| Functional tests (TESTING_GUIDE TC-01 – TC-17) | **Not done yet.** All Apex tests use an HTTP mock |
| Nightly schedule | Not scheduled |
| Production | Not deployed |

## Next steps

0. **Deploy the on-create trigger** to `tterakit-sb`: the same validate/deploy commands as before ([DEPLOYMENT_GUIDE §3](docs/DEPLOYMENT_GUIDE.md#3-deploy)), six test classes, no destructive flag. Then add *Disable Lookup On Create* = unchecked to the settings (`configure-openstreetmap.apex` or `configure-settings.apex` does it), and run TC-08.
1. **Finish the org setup in `tterakit-sb`** ([DEPLOYMENT_GUIDE §3.4–3.5](docs/DEPLOYMENT_GUIDE.md#34-assign-the-permission-set)):
   * Re-assign the permission set. It covers both buttons and edit access to `isCoordsUpdated__c`:

     ```bash
     sf org assign permset --name AccountLocation_Geocoding --target-org tterakit-sb
     ```

   * Add **Suggest Locations (Google)** to oggLocation's *List View Button Layout*, and **Suggest Location (Google)** to the page layout.
   * Create a list view "Not processed yet" (*isCoordsUpdated equals False*) to follow progress.
2. **Flag records processed before the flag existed** (one-off, optional). Run this in Developer Console → Execute Anonymous. Without it, the next automatic run looks them up once more:

   ```apex
   List<ogg__Location__c> done = [SELECT Id FROM ogg__Location__c WHERE Suggested_Latitude__c != null AND isCoordsUpdated__c = false LIMIT 10000];
   for (ogg__Location__c l : done) { l.isCoordsUpdated__c = true; }
   update done;
   ```

3. **Test the flow with OpenStreetMap:** TC-01, TC-02, TC-04 – TC-06, TC-08 – TC-13, TC-16 and TC-17 in [TESTING_GUIDE](docs/TESTING_GUIDE.md). OpenStreetMap is fine for testing the flow, not for judging accuracy, and a bulk run is capped at 200 records.
4. **When the Google key arrives:** enable the **Geocoding API** and **Places API (New)**, restrict the key and set quotas ([DEPLOYMENT_GUIDE §2](docs/DEPLOYMENT_GUIDE.md#2-google-maps-platform-setup)). Then paste the key into `scripts/apex/configure-settings.apex` (it sets *Provider* = `Google`) and run:

   ```bash
   sf apex run --file scripts/apex/configure-settings.apex --target-org tterakit-sb
   ```

   Afterwards run `git checkout` on the file so the key is never committed.
5. **Accuracy and volume with Google:** run TC-03 (10–20 real customer addresses where UPWARD's pin is known to be wrong, checked in Google Maps), TC-07 and TC-14 (1,000+ records). Agree with the business what distance counts as wrong. The guide suggests over 50 m needs review and over 500 m is probably wrong. Records that were processed with OpenStreetMap are flagged and won't be picked up again automatically. To redo them with Google, untick their `isCoordsUpdated__c` (or tick them in a list view).
6. **Bulk-fill existing records:** list view button with nothing ticked, or `scripts/apex/regeocode-existing.apex`.
7. **Nightly run** (optional, Google only): `scripts/apex/schedule-nightly.apex` (TC-15).
8. **Production:** deploy with the six test classes, make sure `isCoordsUpdated__c` and the three target fields exist there, and use Google as the provider with a production API key and quota. Then do steps 1, 4, 6 and 7. **Check *Disable Lookup On Create* before bulk-filling existing records**, so a data migration doesn't also start the trigger, and uncheck it afterwards.
9. **Remove the OpenStreetMap option** once Google is in use (see limitation 6 below).

## Org facts the code relies on

| Item | API name | Notes |
|---|---|---|
| AccountLocation object | `ogg__Location__c` | ogg managed package (label "oggLocation") |
| Link to Account | `ogg__ObjectId__c` (Text 18) + `ogg__prefix__c` | **No lookup field.** Both are required. The prefix is `001` for Account |
| Address | `Account.Address__c` | If `ogg__ObjectId__c` isn't an Account Id: `ogg__Location__c.ogg__RawAddress__c` |
| How UPWARD creates oggLocations | From the Account's **Billing Address** (standard fields) | The lookup uses `Address__c`. Keep both filled with the same address; if they differ, `Different_Distance__c` compares two different addresses. The test-data script fills both |
| UPWARD's pin | `ogg__Latitude__c`, `ogg__Longitude__c` | Number(4,10) |
| Target fields | `Suggested_Latitude__c`, `Suggested_Longtitude__c`, `Different_Distance__c`, `isCoordsUpdated__c` (checkbox) | Already in the org and **not** in this project. Note the spelling *Longtitude* |
| Required Account fields | e.g. `Tax_ID__c`, `Customer_Type__c`, `Company__c` | Filled automatically in tests by `TestRecordFactory` |

## Where things are

| Path | What |
|---|---|
| `force-app/main/default/objects/ogg__Location__c/webLinks/Suggest_Locations_Google.webLink-meta.xml` | The **Suggest Locations (Google)** list view button (bulk) |
| `force-app/main/default/pages/AccountLocationGeocodeList.page` | Confirmation page behind the list view button |
| `force-app/main/default/quickActions/ogg__Location__c.Suggest_Google_Location.quickAction-meta.xml` | The **Suggest Location (Google)** record button |
| `force-app/main/default/lwc/suggestGoogleLocation/` | Headless action: start job → poll status → refresh record → toast |
| `force-app/main/default/classes/` | `AccountLocationGeocodeBatch` (bulk, Schedulable), `AccountLocationGeocodeListController` (list view button), `AccountLocationGeocodeProcessor` (shared per-record work), `AccountLocationGeocodeAction` + `AccountLocationGeocodeQueueable` (record button), `GoogleGeocodingService`, `ThaiAddressNormalizer`, `GeoDistanceUtil`, `GoogleMapsSettings`, plus tests, `GoogleMapsCalloutMock` and `TestRecordFactory` |
| `force-app/main/default/objects/Google_Maps_Settings__c/` | Custom setting: key, on/off switch, country/region/language, Places fallback, field names, batch size, timeout |
| `force-app/main/default/remoteSiteSettings/` | `maps.googleapis.com`, `places.googleapis.com`, `nominatim.openstreetmap.org` (temporary) |
| `force-app/main/default/permissionsets/AccountLocation_Geocoding` | Access to both buttons (Apex classes + Visualforce page) + read access to the three target fields |
| `manifest/package.xml` | What gets deployed (target fields excluded on purpose) |
| `force-app/main/default/triggers/AccountLocationTrigger.trigger` | After insert on `ogg__Location__c`: queues the lookup for new records (`AccountLocationTriggerHandler`) |
| `scripts/apex/` | `configure-settings` (Google), `configure-openstreetmap` (temporary, no key), `test-geocode-address`, `regeocode-existing` (bulk: all not processed yet), `schedule-nightly` |

Deploy and test commands are in [DEPLOYMENT_GUIDE §3](docs/DEPLOYMENT_GUIDE.md#3-deploy) (six test classes: `AccountLocationGeocodingTest`, `AccountLocationGeocodeBatchTest`, `GoogleGeocodingServiceTest`, `GeoDistanceUtilTest`, `ThaiAddressNormalizerTest`, `OpenStreetMapGeocoderTest`).

## Operating it

| Need | How |
|---|---|
| Stop only the automatic lookup on create (e.g. before a data load) | Check *Disable Lookup On Create* in Google Maps Settings; buttons and nightly run keep working. Apex: `AccountLocationTriggerHandler.bypass = true` |
| Switch off immediately | Uncheck *Enabled* in Setup → Custom Settings → Google Maps Settings. Both buttons then say it's turned off, and a running batch stops calling out at its next chunk |
| Stop a running bulk run | Setup → Apex Jobs → *Abort* on `AccountLocationGeocodeBatch` |
| Stop / change the nightly run | Setup → Scheduled Jobs → *Suggest locations nightly* |
| See whether it ran / progress | Setup → Apex Jobs → `AccountLocationGeocodeBatch` (bulk: batches processed / total) or `AccountLocationGeocodeQueueable` (record button) |
| See why a record has no suggestion | Debug log of the **user who started the run** (for the schedule: the user who scheduled it). Typical messages: `No Google Maps result`, `Geocoding API status REQUEST_DENIED` / `OVER_QUERY_LIMIT` |
| See what was sent to Google for an address | `scripts/apex/test-geocode-address.apex` (prints the cleaned variants, source, `postcodeMatch`) |
| Fill in many records at once | List view button with nothing ticked, or `scripts/apex/regeocode-existing.apex` |
| Re-check records that were already processed | Tick them in a list view and use the list view button (or the record button). Or untick `isCoordsUpdated__c`, and the next automatic run picks them up |
| Find records with no result | List view: `isCoordsUpdated__c` = false and the run has finished; these addresses are blank or weren't found |
| Change the API key or options | Edit the custom setting; no deployment needed |
| Switch provider | *Provider* = `Google` (needs API key) or `OpenStreetMap` (no key, testing only) in the custom setting |

## Known limitations / possible follow-ups

1. **Changed addresses aren't detected.** The trigger runs on insert only. Once `isCoordsUpdated__c` is true, a record is only re-checked when ticked, sent through the record button, or its flag is unticked. If UPWARD changes an address on an existing location, nothing resets the flag. Records with no result (blank or unfindable address) stay `false` and are retried by every automatic bulk run, at 1–3 requests each. With OpenStreetMap, large inserts queue parallel jobs that break Nominatim's 1-request-per-second rule, so check *Disable Lookup On Create* first.
2. **Address cleaning uses fixed rules.** New ways of writing room, floor or building can slip through. Add the pattern to `ROOM_PATTERN` / `FLOOR_PATTERN` / `BUILDING_PATTERN` in `ThaiAddressNormalizer`, with a case in `ThaiAddressNormalizerTest`. The patterns were checked in Java, which uses the same regex engine as Apex.
3. **No audit fields.** The source used (Geocoding or Places), the query and the postcode match only go to the debug log. Fields for these would make reviewing easier.
4. **40-second wait in the browser.** If the job queue is slow, the toast says *Still running*; the values appear after a refresh.
5. **Cost.** Each record processed makes 1–3 Google requests: Geocoding first, Places only as a fallback. Keep quotas set in Google Cloud, and check current Google Maps Platform pricing against the expected volume.
6. **OpenStreetMap is a stop-gap.** It's weaker for Thai addresses, limited to 1 request per second, and not for bulk use (runs are capped at 200 records). Once Google works, remove `OpenStreetMapGeocoder` (+ test), the `Provider__c` field, the `OpenStreetMap_Nominatim` remote site and `configure-openstreetmap.apex`, together with the `osm` branches in `GoogleGeocodingService`, `GoogleMapsSettings`, `AccountLocationGeocodeBatch` and the list view page. If Nominatim answers `403`, it may be blocking Salesforce's shared IP addresses; there's no fix for that on our side.

## History

| PR | Change |
|---|---|
| [#1](https://github.com/Chaipitch/tter/pull/1) | Initial implementation, Thai address handling, guides |
| [#2](https://github.com/Chaipitch/tter/pull/2) | Object renamed to `ogg__Location__c` |
| [#3](https://github.com/Chaipitch/tter/pull/3) | Account lookup detected at run time (later replaced); cast fix in a test |
| [#4](https://github.com/Chaipitch/tter/pull/4) | Account linked through `ogg__ObjectId__c`; existing org fields used; tests fixed (settings in memory, `TestRecordFactory`) |
| [#5](https://github.com/Chaipitch/tter/pull/5) | Fallback test fixed (`ogg__ObjectId__c` is required) |
| [#6](https://github.com/Chaipitch/tter/pull/6) | HOW_IT_WORKS.md and HANDOFF.md |
| [#7](https://github.com/Chaipitch/tter/pull/7) | Trigger replaced by the **Suggest Location (Google)** quick action button; old trigger removed with `destructiveChanges.xml` |
| [#8](https://github.com/Chaipitch/tter/pull/8) | Docs: correct flag `--post-destructive-changes` |
| [#9](https://github.com/Chaipitch/tter/pull/9) | Temporary OpenStreetMap (Nominatim) provider for testing without a Google API key |
| [#10](https://github.com/Chaipitch/tter/pull/10) | Bulk processing: Batch Apex, list view button, nightly schedule; shared `AccountLocationGeocodeProcessor` |
| [#11](https://github.com/Chaipitch/tter/pull/11) | Fix: `OSM_MAX_RECORDS_PER_RUN` visible to the list view controller |
| [#12](https://github.com/Chaipitch/tter/pull/12) | `isCoordsUpdated__c` set after processing; automatic runs only pick records where it's false |
| [#13](https://github.com/Chaipitch/tter/pull/13) – [#15](https://github.com/Chaipitch/tter/pull/15) | HANDOFF status; GEO-TEST data scripts with edge cases |
| next | On-create trigger brought back (after insert), alongside the list view and record buttons; *Disable Lookup On Create* setting; `destructiveChanges.xml` removed |
