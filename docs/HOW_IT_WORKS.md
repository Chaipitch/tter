# How It Works

This explains how the Google Maps "suggested coordinates" feature for `ogg__Location__c` works: how a run is started (automatically when a record is created, in bulk from a list view or a schedule, or for one record from a button), and how each record gets its values. For deployment see [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md); for testing see [TESTING_GUIDE.md](TESTING_GUIDE.md).

---

## 1. The problem it solves

Customers keep their whole address in one field, `Account.Address__c`, and the same address in the standard **Billing Address**. UPWARD creates an `ogg__Location__c` record from the Billing Address with a latitude/longitude and a map pin. If the address doesn't exactly match Google's data, UPWARD's pin can land in the wrong place.

This feature gives a second opinion, **for large numbers of records**. The address is sent to Google Maps, and Google's coordinates are stored next to UPWARD's. The distance between the two pins is stored too, so wrong pins are easy to spot. New oggLocation records are looked up **automatically** right after they're created. Existing records, records the trigger skipped, and re-checks are handled in bulk from a list view button or a schedule, or one at a time from a record button. Nothing runs when records are *changed*.

| Field on `ogg__Location__c` | Set by | Meaning |
|---|---|---|
| `ogg__Latitude__c`, `ogg__Longitude__c` | UPWARD | Original pin |
| `Suggested_Latitude__c`, `Suggested_Longtitude__c` | this feature | Google's pin for the address |
| `Different_Distance__c` | this feature | Distance between the two pins, in **meters** |
| `isCoordsUpdated__c` (checkbox) | this feature | `true` once coordinates were written; automatic runs skip these records |

`Suggested_Longtitude__c` is spelled that way in the org, so the code uses that name.

---

## 2. The big picture

```
      ON CREATE                         BULK                                        SINGLE RECORD
 ogg__Location__c inserted    list view button "Suggest Locations (Google)"   record button "Suggest Location (Google)"
   → AccountLocationTrigger     → page AccountLocationGeocodeList (Start)       → LWC suggestGoogleLocation
   → AccountLocationTrigger-  scheduled job (schedule-nightly.apex)             → AccountLocationGeocodeAction.enqueue
     Handler.afterInsert      script regeocode-existing.apex                           │
        │                            │                                                 │
        ▼                            ▼                                                 ▼
 AccountLocationGeocode-      AccountLocationGeocodeBatch  (Batch Apex)        AccountLocationGeocodeQueueable
 Queueable (one per insert)     selected records, or all with                          │
        │                       isCoordsUpdated__c = false                             │
        │                       30 per execute (10 with OpenStreetMap)                 │
        └──────────────────────────► AccountLocationGeocodeProcessor.process(ids) ◄────┘
                                       1. ogg__ObjectId__c → Account → Address__c (blank: Billing Address)
                                       2. ThaiAddressNormalizer: clean the address
                                       3. GoogleGeocodingService: ask Google (max 3 calls; OpenStreetMap: max 2)
                                       4. GeoDistanceUtil: distance in meters
                                       5. update Suggested_*, Different_Distance__c, isCoordsUpdated__c = true
                                                                                       │
                                                         record button: LWC polls getStatus, refreshes, shows a toast
```

---

## 3. Step by step

### 3.0 Automatic on create — `AccountLocationTrigger`

**`AccountLocationTrigger` (after insert) → `AccountLocationTriggerHandler.afterInsert`**

* Callouts aren't allowed inside a trigger, so the trigger only collects the new record Ids and queues **one** `AccountLocationGeocodeQueueable` for the whole insert. The job runs a few seconds later. It processes *Batch Size* records per execution and chains itself for the rest, using the same processor as the buttons (§3.3).
* It skips:
  * everything, when the feature is off or *Disable Lookup On Create* is checked in the custom setting. Use that before a large data load, then process the loaded records with the list view button or the nightly run.
  * everything, when `AccountLocationTriggerHandler.bypass = true` in Apex (data-load scripts, tests).
  * records inserted with `isCoordsUpdated__c` already checked.
  * everything, when the transaction has no background-job slot left. That can happen if UPWARD creates the records from code that's already asynchronous. A message goes to the debug log.
* Skipped records keep `isCoordsUpdated__c` = false, so **the list view button (nothing ticked) or the nightly run always catches up** with what the trigger didn't do.
* The trigger never blocks or slows UPWARD's own insert. It only queues a job.

### 3.1 Bulk: Batch Apex — `AccountLocationGeocodeBatch`

This is the main way to process **large numbers of records**. Batch Apex splits the work into chunks (*Batch Size*, default and max **30**), and each chunk runs in its own transaction with its own limits. Salesforce allows 100 callouts per transaction, and an address needs up to 3, so 30 × 3 = 90 fits. A run can cover any number of records, and it shows up in **Setup → Apex Jobs** with progress (batches processed / total).

**Which records**

| Started with | Records processed |
|---|---|
| Records ticked in the list view | exactly those, **even if `isCoordsUpdated__c` is already true** (use this to re-check) |
| Nothing ticked / `AccountLocationGeocodeBatch.run(null)` / the schedule | **all** records with `isCoordsUpdated__c` = false (not processed yet) |

**How to start it**

* **List view button "Suggest Locations (Google)"** (`WebLink` → Visualforce page `AccountLocationGeocodeList` + `AccountLocationGeocodeListController`). The page says what will be processed: the number of ticked records, or "all not processed yet". After **Start**, it shows the batch job Id; **Back to list** returns to the list view. A list view lets you tick up to 200 records at a time; for more, tick nothing.
* **Schedule:** `AccountLocationGeocodeBatch` is also `Schedulable`. `scripts/apex/schedule-nightly.apex` schedules it at 02:00 every night, for all records not processed yet. New records are then filled in overnight without anyone clicking.
* **Script:** `scripts/apex/regeocode-existing.apex` starts the same "all not processed yet" run.

`AccountLocationGeocodeBatch.run(...)` refuses to start when the feature is off. Each chunk checks again, so unchecking *Enabled* stops a running batch from making further calls.

**The `isCoordsUpdated__c` flag** is set to `true` in the same update that writes the coordinates. Automatic runs (nothing ticked, schedule, script) only pick records where it's `false`, so a record is processed once. Records Google can't find (blank address, or no result) and records where the call failed **keep `false`**, so they're tried again by the next automatic run, at 1–3 requests each time. Fix the address, or tick the flag by hand to stop retries. To process a record again, tick it in the list view, use the record button, or untick its flag.

**With OpenStreetMap** (temporary provider, §4.5), each chunk is 10 records and a run is capped at **200 records** (`OSM_MAX_RECORDS_PER_RUN`), because Nominatim's usage policy doesn't allow bulk geocoding. Real volumes need Google.

### 3.2 Single record: the record button

**Quick action `ogg__Location__c.Suggest_Google_Location` → LWC `suggestGoogleLocation` → `AccountLocationGeocodeAction`**

* The quick action is **headless**: no dialog opens. The component's `invoke()` runs as soon as the button is clicked.
* It calls `AccountLocationGeocodeAction.enqueue(recordId)`. That checks the record is an oggLocation and the feature is on. It then queues **one** `AccountLocationGeocodeQueueable` for the record and returns the job Id. If the feature is off, the user gets an error toast saying so.
* The component calls `AccountLocationGeocodeAction.getStatus(jobId, recordId)` every 2 seconds, for up to about 40 seconds. When the job finishes, it refreshes the record on screen (`notifyRecordUpdateAvailable`) and shows a toast:

| Toast | When |
|---|---|
| *Suggested location updated* – lat, lng and distance | job completed and suggested coordinates are filled |
| *No suggestion* | job completed but nothing was found (or the address is blank) |
| *Google Maps lookup failed* | feature off, job failed, or an unexpected error |
| *Still running* | the job hasn't finished after ~40 s; refresh later |

* Clicking again while a lookup is still running does nothing.

### 3.3 Processing a record — `AccountLocationGeocodeProcessor` (shared)

Both paths call `AccountLocationGeocodeProcessor.process(ids)`. It runs `without sharing`, so it can update records whoever started the run.

1. **Finding the address.** `ogg__Location__c` has **no lookup** to Account. Instead, `ogg__ObjectId__c` (Text 18) holds the Id of the source record, with `ogg__prefix__c` = `001` for Account. The processor:
   * turns `ogg__ObjectId__c` into an Id and checks that it really is an Account Id
   * queries those Accounts in **one** SOQL statement per chunk
   * uses `Account.Address__c`
   * if that's blank, uses the Account's **Billing Address** as one line: Street, City, State, Postal Code, plus Country unless it's Thailand
   * skips the record if both are blank, or if the Id isn't an Account or the Account no longer exists. The location's own `ogg__RawAddress__c` is deliberately not used
2. **Callout budget.** Before each record it checks that 3 callouts are still available. If not, the record is returned as "deferred". The queueable chains those into a new job. The batch logs them, and they're picked up by the next automatic run (their flag is still false); with a batch size of 30 or less this doesn't happen.
3. **Asking the provider** (§4). If nothing is found, or the provider returns an error, the record is left as it is and a message goes to the debug log. **One bad record never stops the others.**
4. **Distance** (§5).
5. **Saving.** All callouts happen first, then **one** `Database.update(..., false)` saves the chunk. Salesforce doesn't allow callouts after a DML statement in the same transaction. Partial success is allowed: a record that fails to save is logged, and the rest are still saved. Only the three target fields are written. UPWARD's own fields are never touched.

### 3.4 Distance is calculated when the record is processed

`Different_Distance__c` is calculated from UPWARD's pin and the suggested pin at that moment. If UPWARD changes its pin later, process the record again (tick it in the list view, or use the record button) to refresh the suggestion and the distance. The trigger only runs on insert; nothing recalculates the distance when a record is updated.

---

## 4. Finding the coordinates (Thai addresses)

### 4.1 Cleaning the address — `ThaiAddressNormalizer`

Google matches Thai addresses well down to house number + road + แขวง/ตำบล + เขต/อำเภอ + province + postcode. Room, floor and unit details often cause a partial match or a wrong spot. So the address is cleaned first:

| Step | What it does | Example |
|---|---|---|
| Thai digits | ๐–๙ → 0–9 | `๙๙/๑` → `99/1` |
| Abbreviations | `ถ.`→ถนน, `ซ.`→ซอย, `ต.`→ตำบล, `อ.`→อำเภอ, `จ.`→จังหวัด, `ม.`→หมู่, `กทม.`/`กรุงเทพฯ`→กรุงเทพมหานคร | `ถ.สุขุมวิท` → `ถนนสุขุมวิท` |
| Room / unit | `ห้อง`, `ห้องเลขที่`, `ยูนิต`, `Room`, `Unit`, `Suite` + number(s) removed | `ห้องเลขที่ 91,96` → (removed) |
| Floor | `ชั้น`, `ชั้นที่`, `Floor`, `Fl.`, `12th Floor` + number(s) removed | `ชั้นที่ 9` → (removed) |
| `เลขที่` | the word is removed before a house number | `เลขที่ 99/1` → `99/1` |
| Building (street-level variant only) | `อาคาร…` / `ตึก…` removed up to the next part of the address | `อาคารเอ็มโพเรียม ทาวเวอร์` → (removed) |
| Postcode | the last 5-digit number, kept to check Google's answer | `10110` |

Words that only *start* like a keyword are kept: `ห้องสมุด` (library), `ชั้นนำ` (leading).

This produces two search variants. Example:

```
input        622 อาคารเอ็มโพเรียม ทาวเวอร์ ห้องเลขที่ 91,96 ชั้นที่ 9 ถนนสุขุมวิท แขวงคลองตัน เขตคลองเตย กรุงเทพมหานคร 10110
withoutUnit  622 อาคารเอ็มโพเรียม ทาวเวอร์ ถนนสุขุมวิท แขวงคลองตัน เขตคลองเตย กรุงเทพมหานคร 10110
streetLevel  622 ถนนสุขุมวิท แขวงคลองตัน เขตคลองเตย กรุงเทพมหานคร 10110
postcode     10110
```

### 4.2 Search order — `GoogleGeocodingService`

At most **3 calls** per address. Cheaper calls go first, and the search stops at the first *good* result:

| # | API | Query | Why |
|---|---|---|---|
| 1 | Geocoding API (GET `maps.googleapis.com/maps/api/geocode/json`) | `withoutUnit` | best match for a full address |
| 2 | Geocoding API | `streetLevel` (skipped if it's the same as #1) | building names sometimes confuse Geocoding |
| 3 | Places API (New) Text Search (POST `places.googleapis.com/v1/places:searchText`), only if *Use Places Fallback* is on | `withoutUnit` | finds named places such as buildings, malls and shops |

Request options come from the custom setting:
* **Geocoding:** `components=country:TH` (*Country Code*), `region=th`, `language=th`.
* **Places:** `languageCode`, `regionCode`, and only the fields it needs (`places.location,places.formattedAddress,places.addressComponents`), to keep the cost down.

### 4.3 What counts as a "good" result

A result is **good** when both of these hold:
1. **It's precise.** Google didn't flag a `partial_match`, and `location_type` isn't `APPROXIMATE` (district/province level). Places results count as precise.
2. **The postcode doesn't contradict the address.** If the address has a postcode and Google's result has one, they must be the same. If either one is missing, the result still passes.

If no result is good, the **best-scoring** one is used:

| Score part | Points |
|---|---|
| Postcode matches | 4 |
| Postcode unknown (either side missing) | 2 |
| Postcode differs | 0 |
| Precise | +1 |

When two results tie, the earlier (cheaper) one wins. A result whose postcode differs can still be used, but only if nothing better was found. A large `Different_Distance__c` then flags it for review.

### 4.4 Errors

| Situation | Result |
|---|---|
| `ZERO_RESULTS` / empty Places response | that step gives nothing; the next step is tried |
| Geocoding error (`REQUEST_DENIED`, `OVER_QUERY_LIMIT`, HTTP 4xx/5xx) | the address is skipped with a log message; the record is unchanged |
| Places error (for example, the API isn't enabled) | ignored; the Geocoding result, if any, is used |

### 4.5 Temporary provider: OpenStreetMap (no API key)

When the custom setting's *Provider* is `OpenStreetMap`, `OpenStreetMapGeocoder` replaces the Google calls. It's meant for testing until a Google API key is available.

| | Google (default) | OpenStreetMap |
|---|---|---|
| API key | required | none |
| Search steps | Geocoding `withoutUnit` → Geocoding `streetLevel` → Places | Nominatim `withoutUnit` → Nominatim `streetLevel` |
| Request | `maps.googleapis.com/maps/api/geocode/json` | `nominatim.openstreetmap.org/search?format=jsonv2&addressdetails=1&countrycodes=th&accept-language=th` |
| "Precise" | not `partial_match`, not `APPROXIMATE` | `place_rank` ≥ 26 (street, house, building) |
| Postcode check | `address_components` → `postal_code` | `address.postcode` |
| Rate | no limit beyond the callout limits | ≤ 1 request/s: requests are spaced 1.1 s apart, batch ≤ 10 records |
| Thai coverage | good | weaker, especially house numbers |

The scoring and postcode check (§4.3) are the same for both. The Nominatim usage policy also requires the request to identify the application, so the code sends a generic `User-Agent` and no company or personal details. To go back to Google, set *Provider* to `Google` (or blank) and add the API key.

---

## 5. Distance

`GeoDistanceUtil.distanceInMeters` uses Salesforce's built-in `Location.getDistance` (great-circle distance on a sphere) and rounds to 2 decimals. It returns `null`, leaving the field blank, if either pin is missing or out of range. Over the distances involved here (meters to kilometers), the difference from Google Maps' "Measure distance" is negligible.

Suggested coordinates are stored with 7 decimals (about 1 cm). That's Google's own precision.

---

## 6. Configuration — `Google_Maps_Settings__c`

This is a hierarchy custom setting; only the **Organization Default** record is used. `scripts/apex/configure-settings.apex` creates it.

| Field | Default | Purpose |
|---|---|---|
| Enabled | off | Master switch for the whole feature |
| Provider | Google | `OpenStreetMap` = temporary no-key provider (§4.5) |
| API Key | — | Google Maps Platform key (not needed for OpenStreetMap) |
| Country Code | — (set `TH`) | Restricts Geocoding results to that country |
| Region | — (set `th`) | Biases results |
| Language | — (set `th`) | Language of Google's formatted address |
| Use Places Fallback | off (set on) | Enables search step 3 |
| Disable Lookup On Create | off | When checked, the trigger doesn't look up new records (the buttons and the nightly run still work) |
| Original Latitude Field / Original Longitude Field | `ogg__Latitude__c` / `ogg__Longitude__c` | Where UPWARD's pin is stored; checked against the object's fields |
| Batch Size | 30 (max 30; max 10 with OpenStreetMap) | Records per background job |
| Timeout (ms) | 10000 (max 120000) | Per-callout timeout |

The Remote Site Settings `Google_Maps_Geocoding_API`, `Google_Places_API` and `OpenStreetMap_Nominatim` allow the three hosts.

---

## 7. Code map

| File | Role |
|---|---|
| `quickActions/ogg__Location__c.Suggest_Google_Location` | The **Suggest Location (Google)** button (Lightning Web Component action) |
| `lwc/suggestGoogleLocation/` | Headless action: starts the job, polls its status, refreshes the record, shows toasts |
| `classes/AccountLocationGeocodeAction.cls` | `@AuraEnabled enqueue` / `getStatus` used by the button |
| `objects/ogg__Location__c/webLinks/Suggest_Locations_Google` | The **Suggest Locations (Google)** list view button |
| `pages/AccountLocationGeocodeList.page` + `classes/AccountLocationGeocodeListController.cls` | Confirmation page behind the list view button; starts the batch |
| `classes/AccountLocationGeocodeBatch.cls` | Bulk: Batch Apex over selected records or all with `isCoordsUpdated__c` = false; Schedulable |
| `classes/AccountLocationGeocodeProcessor.cls` | Shared per-record work: Account lookup via `ogg__ObjectId__c`, callouts, one update per chunk |
| `triggers/AccountLocationTrigger.trigger` + `classes/AccountLocationTriggerHandler.cls` | After insert: queue the lookup for new records; `bypass` flag |
| `classes/AccountLocationGeocodeQueueable.cls` | Job behind the trigger and the record button; calls the processor and chains itself |
| `classes/GoogleGeocodingService.cls` | HTTP calls to the Geocoding and Places APIs, search order, scoring |
| `classes/OpenStreetMapGeocoder.cls` | Temporary no-key provider: Nominatim request, throttling, result mapping |
| `classes/ThaiAddressNormalizer.cls` | Thai address cleaning, search variants, postcode |
| `classes/GeoDistanceUtil.cls` | Distance in meters, safe number conversion |
| `classes/GoogleMapsSettings.cls` | Reads the custom setting, defaults, field-name checks |
| `classes/*Test.cls`, `GoogleMapsCalloutMock.cls`, `TestRecordFactory.cls` | Tests: an HTTP mock (Google is never called), and records that fill in the org's required fields |
| `scripts/apex/*.apex` | Set up the settings, check one address, fill in existing records |

---

## 8. Design decisions

| Decision | Reason |
|---|---|
| Batch Apex for bulk | Made for large volumes: each chunk has its own limits, any number of records, progress in Apex Jobs, and it can be scheduled. |
| List view button with a Visualforce page | Salesforce doesn't allow LWC quick actions on list views; a Visualforce list button receives the ticked records. |
| "Nothing ticked" = all not processed yet | A list view allows ticking at most 200 records; this covers any volume without a separate tool. |
| Trigger on insert **plus** list view button and schedule | New records get a suggestion right away. The bulk paths cover existing records, records the trigger skipped, and re-checks, and they're the safe way to handle large data loads (with *Disable Lookup On Create*). |
| The trigger only queues a job | Callouts aren't allowed in triggers; queuing keeps UPWARD's insert fast and unaffected by Google errors. |
| Headless quick action (LWC) | One click, no dialog; it can report the result in a toast. |
| Queueable for the record button | Starts at once (a batch can wait in the flex queue), and its status can be polled for the toast. |
| `isCoordsUpdated__c` flag instead of "Suggested Latitude is empty" | An explicit, editable "processed" marker. Users can untick it to queue a record again, and suggestions entered or cleared by hand don't confuse the selection. |
| Chunks of 30 | 30 × 3 callouts = 90, within the limit of 100 per transaction. |
| Callouts first, then one DML | Salesforce forbids callouts after DML in the same transaction; it also saves DML statements. |
| Account found through `ogg__ObjectId__c` | The ogg package doesn't provide a lookup field. |
| Existing target fields are not deployed | They already exist in the org (one spelled `Longtitude`); deploying them could change their definitions. |
| Clean the address before searching | Thai room, floor and building details are the main cause of wrong matches. |
| Geocoding before Places | Geocoding costs much less per request. |
| Postcode check | It's a cheap, reliable signal that Google chose the right area. |
| Errors never block saving | A failed lookup leaves the record as it is and is reported to the user. |
| Settings in a custom setting | The feature can be switched off, and the key and options changed, without a deployment. The API key stays out of git. |

---

## 9. Limits and known gaps

* **Two address sources.** UPWARD pins the Billing Address; this feature looks up `Address__c` (the Billing Address only when `Address__c` is blank). If the two aren't the same address, a large `Different_Distance__c` may just mean the fields disagree, so check both before correcting a pin.
* **Changed addresses aren't detected.** The trigger runs on insert only. Once `isCoordsUpdated__c` is true, a record is only re-checked when ticked, sent through the record button, or its flag is unticked.
* **Large inserts with the trigger on** queue one job per insert transaction (Data Loader: one per 200 records). That's fine for Google within its quota, but with OpenStreetMap many parallel jobs break Nominatim's 1-request-per-second rule. Check *Disable Lookup On Create* before big loads.
* **Unfindable records are retried.** Records with no result keep `isCoordsUpdated__c` = false and are tried again by every automatic run.
* **Rule-based address cleaning.** Uncommon ways of writing room, floor or building may not be removed. Run `test-geocode-address.apex` to see what was sent, and add a pattern to `ThaiAddressNormalizer` with a test.
* **40-second wait in the browser.** If Google or the job queue is slow, the toast says *Still running*; the job still finishes and the values appear after a refresh.
* **No result field.** The source (Geocoding or Places), the query used and the postcode match are only written to the debug log, not stored on the record.
* **Cost.** Each record processed costs 1–3 Google requests. Set quotas in Google Cloud and check current Google Maps Platform pricing for the expected volume.
