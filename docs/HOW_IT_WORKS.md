# How It Works

This explains how the Google Maps "suggested coordinates" feature for `ogg__Location__c` works, from the moment a record is created to the values on the page. For deployment see [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md); for testing see [TESTING_GUIDE.md](TESTING_GUIDE.md).

---

## 1. The problem it solves

Customers keep their whole address in one field, `Account.Address__c`. When that field is filled in, UPWARD creates an `ogg__Location__c` record with a latitude/longitude and a map pin. If the address doesn't exactly match Google's data, UPWARD's pin can land in the wrong place.

This feature gives a second opinion. It sends the same address to Google Maps itself and stores Google's coordinates next to UPWARD's. It also stores the distance between the two pins, so wrong pins are easy to spot.

| Field on `ogg__Location__c` | Set by | Meaning |
|---|---|---|
| `ogg__Latitude__c`, `ogg__Longitude__c` | UPWARD | Original pin |
| `Suggested_Latitude__c`, `Suggested_Longtitude__c` | this feature | Google's pin for the address |
| `Different_Distance__c` | this feature | Distance between the two pins, in **meters** |

`Suggested_Longtitude__c` is spelled that way in the org, so the code uses that name.

---

## 2. The big picture

```
User / integration saves Account.Address__c
        │
        ▼
UPWARD creates ogg__Location__c  (ogg__ObjectId__c = Account Id, ogg__Latitude__c / ogg__Longitude__c)
        │
        ▼
AccountLocationTrigger  ── after insert ──►  AccountLocationTriggerHandler.afterInsert
                                                   │  enqueue (callouts are not allowed in triggers)
                                                   ▼
                                     AccountLocationGeocodeQueueable  (async, a few seconds later)
                                       1. read ogg__ObjectId__c, find the Account, read Address__c
                                       2. ThaiAddressNormalizer: clean the address
                                       3. GoogleGeocodingService: ask Google (max 3 calls)
                                       4. GeoDistanceUtil: distance in meters
                                       5. update Suggested_* and Different_Distance__c
                                                   │
                                                   ▼
AccountLocationTrigger  ── before update ──►  distance recalculated whenever either pin changes
```

---

## 3. Step by step

### 3.1 Trigger: after insert

**`AccountLocationTrigger` → `AccountLocationTriggerHandler.afterInsert`**

* Salesforce doesn't allow HTTP callouts inside a trigger. So the trigger only collects the new record Ids and queues **one** background job (`System.enqueueJob`) for the whole batch.
* It does nothing if the feature is off: the custom setting has *Enabled* unchecked or no API key, or `AccountLocationTriggerHandler.bypass` is `true`.
* If the transaction can't queue any more jobs (for example, records inserted from code that is already asynchronous), it writes an error to the debug log and skips. Those records can be filled in later with `scripts/apex/regeocode-existing.apex`.

### 3.2 Background job

**`AccountLocationGeocodeQueueable`** (Queueable + `Database.AllowsCallouts`, runs `without sharing`)

1. **Batching.** It takes the first *Batch Size* records (default and max **30**). Anything left over goes to a new job that it queues itself ("chaining"). Salesforce allows 100 callouts per transaction, and one address can need up to 3, so 30 × 3 = 90 stays under the limit. Before each record it also checks how many callouts are left, and pushes the record to the next job if there aren't enough.
2. **Finding the address.** `ogg__Location__c` has **no lookup** to Account. Instead, `ogg__ObjectId__c` (Text 18) holds the Id of the source record, with `ogg__prefix__c` = `001` for Account. The job:
   * turns `ogg__ObjectId__c` into an Id and checks that it really is an Account Id
   * queries those Accounts in **one** SOQL statement for the whole batch
   * uses `Account.Address__c`
   * falls back to the location's own `ogg__RawAddress__c` if the Id isn't an Account or the Account no longer exists
   * skips the record if the address is blank
3. **Asking Google** (§4). If Google finds nothing, or returns an error, the record is left as it is and a message goes to the debug log. **Saving the record is never blocked.**
4. **Distance** (§5).
5. **Saving.** All callouts happen first, then **one** `Database.update(..., false)` saves every record in the batch. Salesforce doesn't allow callouts after a DML statement in the same transaction. Partial success is allowed: a record that fails to save is logged, and the rest are still saved. Only the three target fields are written. UPWARD's own fields are never touched.

### 3.3 Trigger: before update

**`AccountLocationTriggerHandler.beforeUpdate`**

When `ogg__Latitude__c`, `ogg__Longitude__c`, `Suggested_Latitude__c` or `Suggested_Longtitude__c` changes, `Different_Distance__c` is recalculated in the same save. This covers:

* the job's own update (the job also calculates the distance itself, with the same result)
* UPWARD filling in or correcting its pin **after** the job ran
* someone editing the coordinates by hand

There are no callouts here. If the setting names a field that doesn't exist, the error is logged and the save goes ahead.

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
| API Key | — | Google Maps Platform key |
| Country Code | — (set `TH`) | Restricts Geocoding results to that country |
| Region | — (set `th`) | Biases results |
| Language | — (set `th`) | Language of Google's formatted address |
| Use Places Fallback | off (set on) | Enables search step 3 |
| Original Latitude Field / Original Longitude Field | `ogg__Latitude__c` / `ogg__Longitude__c` | Where UPWARD's pin is stored; checked against the object's fields |
| Batch Size | 30 (max 30) | Records per background job |
| Timeout (ms) | 10000 (max 120000) | Per-callout timeout |

The Remote Site Settings `Google_Maps_Geocoding_API` and `Google_Places_API` allow the two Google hosts.

---

## 7. Code map

| File | Role |
|---|---|
| `triggers/AccountLocationTrigger.trigger` | Calls the handler on after insert and before update. Contains no logic. |
| `classes/AccountLocationTriggerHandler.cls` | Queues the job; recalculates the distance; `bypass` flag |
| `classes/AccountLocationGeocodeQueueable.cls` | Batching and chaining, Account lookup through `ogg__ObjectId__c`, callouts, one update per batch |
| `classes/GoogleGeocodingService.cls` | HTTP calls to the Geocoding and Places APIs, search order, scoring |
| `classes/ThaiAddressNormalizer.cls` | Thai address cleaning, search variants, postcode |
| `classes/GeoDistanceUtil.cls` | Distance in meters, safe number conversion |
| `classes/GoogleMapsSettings.cls` | Reads the custom setting, defaults, field-name checks |
| `classes/*Test.cls`, `GoogleMapsCalloutMock.cls`, `TestRecordFactory.cls` | Tests: an HTTP mock (Google is never called), and records that fill in the org's required fields |
| `scripts/apex/*.apex` | Set up the settings, check one address, fill in existing records |

---

## 8. Design decisions

| Decision | Reason |
|---|---|
| Queueable instead of `@future` | It can carry a list of Ids, can chain itself for large volumes, and shows up in Apex Jobs. |
| One job per trigger batch, chained | Uses one enqueue slot no matter how many records are inserted, and stays within the callout limits. |
| Callouts first, then one DML | Salesforce forbids callouts after DML in the same transaction; it also saves DML statements. |
| Account found through `ogg__ObjectId__c` | The ogg package doesn't provide a lookup field. |
| Existing target fields are not deployed | They already exist in the org (one spelled `Longtitude`); deploying them could change their definitions. |
| Clean the address before searching | Thai room, floor and building details are the main cause of wrong matches. |
| Geocoding before Places | Geocoding costs much less per request. |
| Postcode check | It's a cheap, reliable signal that Google chose the right area. |
| Errors never block saving | UPWARD's own saves must never fail because of this feature. |
| Settings in a custom setting | The feature can be switched off, and the key and options changed, without a deployment. The API key stays out of git. |

---

## 9. Limits and known gaps

* **Only new records.** The trigger runs on insert. If `Account.Address__c` changes later and UPWARD *updates* the existing location instead of creating a new one, the suggestion isn't refreshed. Run `regeocode-existing.apex`, or extend the trigger. See HANDOFF.md.
* **Rule-based address cleaning.** Uncommon ways of writing room, floor or building may not be removed. Run `test-geocode-address.apex` to see what was sent, and add a pattern to `ThaiAddressNormalizer` with a test.
* **One enqueue slot.** Records inserted from code that is already asynchronous and has used its slot are skipped with a log message.
* **No result field.** The source (Geocoding or Places), the query used and the postcode match are only written to the debug log, not stored on the record.
* **Cost.** Each new location costs 1–3 Google requests. Set quotas in Google Cloud and check current Google Maps Platform pricing for the expected volume.
