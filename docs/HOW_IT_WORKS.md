# How It Works

This explains how the Google Maps "suggested coordinates" feature for `ogg__Location__c` works, from the click on the **Suggest Location (Google)** button to the values on the page. For deployment see [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md); for testing see [TESTING_GUIDE.md](TESTING_GUIDE.md).

---

## 1. The problem it solves

Customers keep their whole address in one field, `Account.Address__c`. When that field is filled in, UPWARD creates an `ogg__Location__c` record with a latitude/longitude and a map pin. If the address doesn't exactly match Google's data, UPWARD's pin can land in the wrong place.

This feature gives a second opinion **on demand**. A user clicks a button on the oggLocation record; the address is sent to Google Maps and Google's coordinates are stored next to UPWARD's. The distance between the two pins is stored too, so wrong pins are easy to spot. Nothing happens automatically when records are created or changed.

| Field on `ogg__Location__c` | Set by | Meaning |
|---|---|---|
| `ogg__Latitude__c`, `ogg__Longitude__c` | UPWARD | Original pin |
| `Suggested_Latitude__c`, `Suggested_Longtitude__c` | this feature | Google's pin for the address |
| `Different_Distance__c` | this feature | Distance between the two pins, in **meters** |

`Suggested_Longtitude__c` is spelled that way in the org, so the code uses that name.

---

## 2. The big picture

```
UPWARD has created ogg__Location__c  (ogg__ObjectId__c = Account Id, ogg__Latitude__c / ogg__Longitude__c)
        │
        ▼
User clicks "Suggest Location (Google)"  (quick action → LWC suggestGoogleLocation)
        │  AccountLocationGeocodeAction.enqueue(recordId)
        ▼
AccountLocationGeocodeQueueable  (background job, usually done in a few seconds)
   1. read ogg__ObjectId__c, find the Account, read Address__c
   2. ThaiAddressNormalizer: clean the address
   3. GoogleGeocodingService: ask Google (max 3 calls)
   4. GeoDistanceUtil: distance in meters
   5. update Suggested_* and Different_Distance__c
        │
        ▼
LWC polls AccountLocationGeocodeAction.getStatus every 2 s (up to ~40 s),
refreshes the record and shows a toast with the result
```

---

## 3. Step by step

### 3.1 The button

**Quick action `ogg__Location__c.Suggest_Google_Location` → LWC `suggestGoogleLocation` → `AccountLocationGeocodeAction`**

* The quick action is **headless**: no dialog opens. The component's `invoke()` runs as soon as the button is clicked.
* It calls `AccountLocationGeocodeAction.enqueue(recordId)`. That checks the record is an oggLocation and the feature is on (custom setting *Enabled* and an API key). It then queues **one** background job for the record and returns the job Id. If the feature is off, the user gets an error toast saying so.
* A background job is needed because Google is called over HTTP. Running the lookup in the background keeps the page responsive, and keeps the code identical for one record (button) and many (back-fill).
* The component then calls `AccountLocationGeocodeAction.getStatus(jobId, recordId)` every 2 seconds, for up to about 40 seconds. When the job finishes, it refreshes the record on screen (`notifyRecordUpdateAvailable`) and shows a toast:

| Toast | When |
|---|---|
| *Suggested location updated* – lat, lng and distance | job completed and suggested coordinates are filled |
| *No suggestion* | job completed but Google found nothing (or the address is blank) |
| *Google Maps lookup failed* | feature off, job failed, or an unexpected error |
| *Still running* | the job hasn't finished after ~40 s; refresh later |

* Clicking again while a lookup is still running does nothing.

### 3.2 Background job

**`AccountLocationGeocodeQueueable`** (Queueable + `Database.AllowsCallouts`, runs `without sharing`)

1. **Batching.** From the button the job gets one record. From the back-fill script it gets many: it takes the first *Batch Size* records (default and max **30**). Anything left over goes to a new job that it queues itself ("chaining"). Salesforce allows 100 callouts per transaction, and one address can need up to 3, so 30 × 3 = 90 stays under the limit. Before each record it also checks how many callouts are left, and pushes the record to the next job if there aren't enough.
2. **Finding the address.** `ogg__Location__c` has **no lookup** to Account. Instead, `ogg__ObjectId__c` (Text 18) holds the Id of the source record, with `ogg__prefix__c` = `001` for Account. The job:
   * turns `ogg__ObjectId__c` into an Id and checks that it really is an Account Id
   * queries those Accounts in **one** SOQL statement for the whole batch
   * uses `Account.Address__c`
   * falls back to the location's own `ogg__RawAddress__c` if the Id isn't an Account or the Account no longer exists
   * skips the record if the address is blank
3. **Asking Google** (§4). If Google finds nothing, or returns an error, the record is left as it is and a message goes to the debug log. **Saving the record is never blocked.**
4. **Distance** (§5).
5. **Saving.** All callouts happen first, then **one** `Database.update(..., false)` saves every record in the batch. Salesforce doesn't allow callouts after a DML statement in the same transaction. Partial success is allowed: a record that fails to save is logged, and the rest are still saved. Only the three target fields are written. UPWARD's own fields are never touched.

### 3.3 Distance is calculated when the job runs

`Different_Distance__c` is calculated by the job from UPWARD's pin and Google's pin at that moment. If UPWARD changes its pin later, click the button again to refresh the suggestion and the distance. There is no trigger that recalculates it automatically.

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
| `classes/AccountLocationGeocodeQueueable.cls` | Batching and chaining, Account lookup through `ogg__ObjectId__c`, callouts, one update per batch |
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
| Button instead of a trigger | Users decide which locations to check. No Google cost or background work on every insert, and no interference with UPWARD's own saves. |
| Headless quick action (LWC) | One click, no dialog; it can report the result in a toast. |
| Queueable instead of `@future` | It can carry a list of Ids, can chain itself for large volumes (back-fill), and its status can be polled from Apex Jobs. |
| Batches of 30, chained | Stays within the callout limits when the back-fill script sends many records. |
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

* **Manual.** Nothing runs on its own. New or changed addresses only get a suggestion when someone clicks the button, or when the back-fill script runs.
* **Rule-based address cleaning.** Uncommon ways of writing room, floor or building may not be removed. Run `test-geocode-address.apex` to see what was sent, and add a pattern to `ThaiAddressNormalizer` with a test.
* **40-second wait in the browser.** If Google or the job queue is slow, the toast says *Still running*; the job still finishes and the values appear after a refresh.
* **No result field.** The source (Geocoding or Places), the query used and the postcode match are only written to the debug log, not stored on the record.
* **Cost.** Each click costs 1–3 Google requests. Set quotas in Google Cloud and check current Google Maps Platform pricing for the expected volume.
