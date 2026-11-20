# Testing Guide – Sandbox

Complete [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) first, including steps 3.4 (permission set) and 4 (custom setting).

---

## 1. Apex unit tests

```bash
sf apex run test \
  --class-names AccountLocationGeocodingTest \
  --class-names GoogleGeocodingServiceTest \
  --class-names GeoDistanceUtilTest \
  --class-names ThaiAddressNormalizerTest \
  --class-names OpenStreetMapGeocoderTest \
  --class-names AccountLocationGeocodeBatchTest \
  --code-coverage --result-format human --wait 15 \
  --target-org tterakit-sb
```

**Expected:** all tests pass, and every class shows high coverage (> 85%). The tests use `GoogleMapsCalloutMock`, so **Google is never called** and no API key is needed.

| Test class | Covers |
|---|---|
| `AccountLocationGeocodingTest` | On-create trigger: an insert is looked up automatically and flagged; records inserted already flagged are skipped; with the lookup on create switched off the trigger skips, but the buttons still work; a 60-record insert queues one job (30 per execution). Record button Apex (`enqueue` → job → `getStatus`) fills suggested lat/lng + distance; setting disabled and wrong record type report an error; blank address; Google error leaves the record unchanged; no original coordinates → no distance; Billing Address used when `Address__c` is blank (address order: `Address__c` → Billing; no Account → skipped, `ogg__RawAddress__c` ignored). Uses the Thai Emporium address. |
| `GoogleGeocodingServiceTest` | Thai search order (address without room/floor → street level → Places); postcode check; best-score choice; country/region/language params; Places failure keeps the Geocoding result; REQUEST_DENIED and HTTP 500 errors; blank address; settings defaults/validation |
| `ThaiAddressNormalizerTest` | Room/floor removal (`ห้องเลขที่ 91,96`, `ชั้นที่ 9`, `Room`, `12th Floor`); building removal; Thai digits; abbreviations (`ถ.`, `ซ.`, `ต.`, `อ.`, `จ.`, `ม.`, `กทม.`, `กรุงเทพฯ`); postcode extraction |
| `OpenStreetMapGeocoderTest` | Provider switch (`OpenStreetMap`/`OSM`/blank/`Google`); enabled without an API key; batch capped at 10; Nominatim request (`format=jsonv2`, `countrycodes`, `accept-language`, User-Agent, no key); area result → street-level query; best result when only area results; empty result; HTTP 429; button end to end with OpenStreetMap; Google and Places never called |
| `AccountLocationGeocodeBatchTest` | Bulk: a run processes all records with `isCoordsUpdated__c` = false and flags them; the flag (not Suggested Latitude) decides what a run picks up; a run with record Ids processes those even if flagged; feature off can't start; OpenStreetMap run capped at 200 (Google not capped); scheduled entry point; global action panel controller: overview, start, picking up a running job, progress and summary (updated, > 500 m, no distance, still not processed, a record without an Account counted as not processed), refusal when off or nothing to do |
| `GeoDistanceUtilTest` | Distance math (known distances, same point = 0, null/out-of-range input) |

---

## 2. Functional tests (real Google calls)

### Preparation

* Put the **Suggest Location** button and the `Suggested Latitude`, `Suggested Longtitude` and `Different Distance` fields on the oggLocation page (DEPLOYMENT_GUIDE 3.5).
* Open **Setup → Debug Logs** and add a trace flag for **your user** (the job runs as the user who clicked the button), with Apex = `DEBUG`. Errors from the job are written with `System.debug(LoggingLevel.ERROR, ...)`.
* Optionally, tail the logs live:

  ```bash
  sf apex tail log --color --target-org tterakit-sb
  ```

### Test data

The test data follows the real flow: the script creates Accounts, and **UPWARD creates the oggLocations**.

1. **Create the Accounts:** `scripts/apex/create-test-data.apex` creates 18 Accounts named `GEO-TEST …` with Thai addresses chosen per test case. Each address goes into both `Address__c` (what the lookup uses) and the **Billing Address**, split into street, district (City), province (State), postcode and Thailand. **UPWARD creates the oggLocation from the Billing Address.** If State and Country/Territory Picklists are on, the province goes into City and the country code is `TH`. 01–10 are everyday cases; 11–18 are edge cases, see TC-18 and TC-19. It's safe to re-run: existing Accounts are skipped.

   ```bash
   sf apex run --file scripts/apex/create-test-data.apex --target-org tterakit-sb
   ```

2. **Wait for UPWARD** to create the oggLocations, then check them. The on-create trigger looks them up automatically:

   ```bash
   sf data query --target-org tterakit-sb --query "SELECT Name, ogg__ObjectId__c, ogg__RawAddress__c, ogg__Latitude__c, ogg__Longitude__c, Suggested_Latitude__c, Suggested_Longtitude__c, Different_Distance__c, isCoordsUpdated__c, CreatedBy.Name FROM ogg__Location__c ORDER BY CreatedDate DESC LIMIT 25"
   ```

   UPWARD may not create one for case 10 (blank address) or 09 (nonsense).
3. **Optional: apply the test pins.** UPWARD sets its own (real) pins. For the pin cases, especially 11–16 (pin far away, `0,0`, swapped and so on), run `scripts/apex/apply-test-pins.apex`. It overwrites the pins with deliberate test pins and clears the results (suggested fields, distance, flag). Then run the "Suggest Locations" global action. Re-run the script any time to reset the GEO-TEST results.

   ```bash
   sf apex run --file scripts/apex/apply-test-pins.apex --target-org tterakit-sb
   ```

**More variety:** `scripts/apex/create-random-test-data.apex` adds extra random Accounts on each run, 20 by default, and never changes existing ones.
* **Where:** about half inside and half outside Bangkok. Addresses are obscure and messy: real sub-districts, districts and roads, with made-up house numbers, sois, `หมู่`, villages, shophouse buildings, market stalls and warehouses.
* **How it's written:** random variations: abbreviations, Thai digits, floor and room, an English unit prefix, a missing postcode, commas between parts, or parts run together without spaces.
* **Names** are just the run stamp and the variations, for example `GEO-TEST R261118153000-07 [UPC,abbr,comma]`.
* **Settings** at the top: `RECORD_COUNT`, `INSIDE_BANGKOK_PERCENT`, `VARIATION_PERCENT`.

There's no exact "right" pin for these, since the house numbers are made up. Judge the results by whether the suggestion lands in the right sub-district or district, and how far UPWARD's pin is from it. With OpenStreetMap, keep runs small (Nominatim allows 1 request per second).

```bash
sf apex run --file scripts/apex/create-random-test-data.apex --target-org tterakit-sb
```

Remove everything with `scripts/apex/delete-test-data.apex`; it also deletes the oggLocations UPWARD created for the GEO-TEST Accounts. The expected result of each case is in the comments of `create-test-data.apex`.

### Testing without a Google API key (OpenStreetMap)

Until the Google key is available, run `scripts/apex/configure-openstreetmap.apex` (DEPLOYMENT_GUIDE §4). All test cases work the same way, with these differences:
* The pin comes from OpenStreetMap. Thai house numbers are often missing there, so a street- or district-level pin and a larger `Different Distance` are normal. **Don't judge accuracy (TC-03) with OpenStreetMap**; repeat TC-01 – TC-03 with Google later.
* TC-07 (invalid API key) doesn't apply.
* Click at a normal pace. Nominatim allows at most 1 request per second from the org.
* The probe script prints `provider = OpenStreetMap` and `source=OPENSTREETMAP`.

### How Thai addresses are searched

`ThaiAddressNormalizer` cleans each address, then `GoogleGeocodingService` tries up to 3 searches. It stops at the first result that is precise and whose postcode matches the address:

| Step | Query sent | Example for `622 อาคารเอ็มโพเรียม ทาวเวอร์ ห้องเลขที่ 91,96 ชั้นที่ 9 ถนนสุขุมวิท ... 10110` |
|---|---|---|
| 1. Geocoding API | Without room / floor | `622 อาคารเอ็มโพเรียม ทาวเวอร์ ถนนสุขุมวิท แขวงคลองตัน เขตคลองเตย กรุงเทพมหานคร 10110` |
| 2. Geocoding API | Street level (building removed too) | `622 ถนนสุขุมวิท แขวงคลองตัน เขตคลองเตย กรุงเทพมหานคร 10110` |
| 3. Places API (New), if enabled | Without room / floor | Same as step 1. Places is good at building names. |

Before searching, Thai digits (๐–๙) are converted, and abbreviations (`ถ.` `ซ.` `ต.` `อ.` `จ.` `ม.` `กทม.` `กรุงเทพฯ`) are expanded. If no result is good, the best one is used, ranked by postcode match first and precision second. A result whose postcode differs from the address ranks lowest.

### Test cases

Create each Account the way users normally do, so that UPWARD creates the oggLocation record. **New records are looked up automatically by the trigger** (TC-08). TC-01 – TC-11 use the **record button**, which also works on records the trigger already processed (to reset GEO-TEST results, run `apply-test-pins.apex`): open the oggLocation record and click **Suggest Location**. Within a few seconds a toast shows the result and the record refreshes. TC-12 – TC-17 test **bulk processing**; TC-18 – TC-19 are edge cases.

| # | Scenario | Steps | Expected result |
|---|---|---|---|
| TC-01 | Thai address with building, room and floor | Account with `Address__c` = `622 อาคารเอ็มโพเรียม ทาวเวอร์ ห้องเลขที่ 91,96 ชั้นที่ 9 ถนนสุขุมวิท แขวงคลองตัน เขตคลองเตย กรุงเทพมหานคร 10110` | Suggested point is at the Emporium Tower on Sukhumvit (around 13.730, 100.569). The probe script (§4) shows `postcodeMatch=true`. |
| TC-02 | Thai digits and abbreviations | `เลขที่ ๙๙/๑ ม.๓ ต.บางพูด อ.ปากเกร็ด จ.นนทบุรี ๑๑๑๒๐` | The address is read as `99/1 หมู่ 3 ตำบลบางพูด อำเภอปากเกร็ด จังหวัดนนทบุรี 11120`. The suggested point is in Bang Phut, Pak Kret. |
| TC-03 | Real customer addresses that don't match Google exactly | Take 10–20 real customer addresses, including ones where the UPWARD pin is known to be wrong | Suggested coordinates point to the real place (check in Google Maps, see §3). Different Distance shows how far off the UPWARD pin was. With Google, building or shop names are also found through Places (the fallback is always on). |
| TC-04 | Nonsense address | `asdfgh 99999` | Toast *No suggestion*; fields stay blank. The debug log shows `No Google Maps result`. |
| TC-05 | Blank address | oggLocation whose Account has an empty `Address__c` | Toast *No suggestion*. No callout; fields stay blank. |
| TC-06 | Feature switched off | Uncheck *Enabled* in the custom setting and click the button | Error toast *Google Maps lookup is turned off…*; no job in Apex Jobs. Re-enable after the test. |
| TC-07 | Invalid API key | Put a wrong key in the setting and click the button | Toast *No suggestion*; record unchanged. The log shows `Geocoding API status REQUEST_DENIED`. Restore the key. |
| TC-08 | Automatic lookup on create | Create a new Account with a Thai address so UPWARD creates the oggLocation (or run the test-data script). Don't click anything | Within a few seconds to a minute, the new oggLocation has suggested values and `isCoordsUpdated__c` checked; **Setup → Apex Jobs** shows an `AccountLocationGeocodeQueueable`.  |
| TC-09 | Click again after UPWARD changes its pin | Change the original Lat/Lng (or wait for UPWARD to update it), click the button again | Suggested values and Different Distance are refreshed. If you set the original Lat/Lng to the suggested values first, the distance is 0. |
| TC-10 | Double click | Click the button twice quickly | Only one lookup runs; one result toast. |
| TC-11 | Non-admin user | Repeat TC-01 as a standard sales user with the permission set | Same result. Without the permission set, the button shows an error. |
| TC-12 | Global action | On the Account list view in the managed app, click **+** in the header → **Suggest Locations** → **Start**. Keep the modal open | A modal floats over the list view: the number of oggLocations not processed yet, then a progress bar (every 5 s). At the end: a **toast** and a **summary** (updated, of which > 500 m from UPWARD's pin, without a distance, still not processed, failed batches). **Setup → Apex Jobs** shows `AccountLocationGeocodeBatch` Completed; the updated oggLocations have suggested values and `isCoordsUpdated__c` checked. |
| TC-12c | Close and reopen | Start a run (TC-12), close the modal while it's running, open **Suggest Locations** again | It shows the same run's progress again, and the summary when it's done. |
| TC-13 | Run it again | Open **Suggest Locations** again once the first run has finished | The count now only includes records whose address is blank or couldn't be found (still unchecked). **Start** doesn't touch records processed by the first run (check *Last Modified Date*). |
| TC-14 | Large volume (Google only) | With Google as the provider, run TC-13 or `scripts/apex/regeocode-existing.apex` on a sandbox with 1,000+ unprocessed locations | Apex Jobs shows the batch progressing in chunks of 30 (*Batches Processed / Total Batches*) and finishing Completed with 0 failures. Spot-check results (§3). Check the request count in Google Cloud against the quota. |
| TC-15 | Nightly schedule | Run `scripts/apex/schedule-nightly.apex`; create a new Account so UPWARD creates a location; check the next morning | Setup → Scheduled Jobs lists *Suggest locations nightly*. The new location has suggested values after the run. Delete the scheduled job after testing if it isn't wanted yet. |
| TC-16 | OpenStreetMap cap | With Provider = OpenStreetMap, run TC-13 with more than 200 unprocessed records | The page warns about the 200-record cap. At most 200 records are processed and flagged in that run; the next run continues with the rest. |
| TC-17 | Re-queue a processed record | Untick `isCoordsUpdated__c` on a processed record, then run TC-13 | That record is processed again (new Last Modified Date); other flagged records aren't. |
| TC-18 | UPWARD pin far away or invalid | Test data 11–16, after `apply-test-pins.apex`: the same Siam Paragon address with the pin in Chiang Mai, in Singapore, at `0,0`, with the longitude sign flipped, at the antipode, and with lat/lng swapped | Suggestion at Siam Paragon (~13.746, 100.535) every time. Different Distance ≈ 585 km, 1,430 km, 11,145 km, 16,180 km and 20,015 km (the maximum possible). **Swapped lat/lng: distance stays empty**, because a latitude of 100.5 isn't a valid coordinate. If UPWARD rejects that pin at insert, the create script says so. |
| TC-19 | Address side contradicts | After `apply-test-pins.apex`. Test data 17: Phuket address, Bangkok pin. Test data 18: Bangkok address with Chiang Mai postcode 50000, correct pin | 17: suggestion in Phuket Town (~7.88, 98.39), distance ≈ 690 km. 18: the probe script shows `postcodeMatch=false`; all search steps are tried and the best-scored result is used (most likely still Siam Paragon, small distance). Treat 18 as "needs review": the address itself is inconsistent. |

### Checking the job

* **Setup → Apex Jobs:** look for `AccountLocationGeocodeQueueable` with status *Completed*. If the status is *Failed*, open the job to see the error.
* With SOQL:

  ```bash
  sf data query --target-org tterakit-sb --query "SELECT Id, Name, ogg__ObjectId__c, ogg__Latitude__c, ogg__Longitude__c, Suggested_Latitude__c, Suggested_Longtitude__c, Different_Distance__c FROM ogg__Location__c ORDER BY CreatedDate DESC LIMIT 20"
  ```

  `ogg__ObjectId__c` is the linked Account Id, and `ogg__Latitude__c` / `ogg__Longitude__c` are UPWARD's original pin.

---

## 3. Verifying accuracy

For a sample of records:

1. Open `https://www.google.com/maps?q=<Suggested_Latitude__c>,<Suggested_Longtitude__c>` and confirm it shows the customer's location.
2. Open `https://www.google.com/maps?q=<original lat>,<original lng>` to see the UPWARD pin.
3. Measure the distance between the two pins in Google Maps (right click → *Measure distance*). It should match `Different_Distance__c` within a few meters. The code uses great-circle distance.

The following tolerance is only a suggestion for the business: under 50 m is OK, 50–500 m needs review, over 500 m is probably wrong. You can use `Different_Distance__c` in a report or list view to find records that need correcting.

---

## 4. Probing an address without creating records

Edit the address in `scripts/apex/test-geocode-address.apex`, then run:

```bash
sf apex run --file scripts/apex/test-geocode-address.apex --target-org tterakit-sb
```

The output first shows the query variants built from the Thai address (`withoutUnit`, `streetLevel`, `postcode`). Then it shows the chosen result: its source (`GEOCODING_API` or `PLACES_TEXT_SEARCH`), the query that produced it, `location_type`, `partial_match`, `postcode` / `postcodeMatch`, and Google's formatted address. Use it to see why a result was chosen.

---

## 5. Troubleshooting at runtime

| Symptom | Check |
|---|---|
| New records aren't looked up automatically | The feature is off (*Enabled* unchecked), or the record was inserted with `isCoordsUpdated__c` already checked. Also check the debug log for `no background job slot left` (UPWARD inserting from async code). The "Suggest Locations" global action or the nightly run will catch them up. |
| Action missing | Global action: add **Suggest Locations** to the Global Publisher Layout, and check *Publisher Layout Assignment* for the user's profile. Record button: add it to the oggLocation page layout / Lightning page. See DEPLOYMENT_GUIDE 3.5 and 3.5b. |
| Batch Completed but some records still empty | Those addresses are blank or weren't found (their `isCoordsUpdated__c` stays unchecked, so they're retried next run); check the debug log of the user who started it. With OpenStreetMap, only 200 records are processed per run. |
| A record is never picked up by the nightly run / global action | Its `isCoordsUpdated__c` is already checked. Untick it, or use the record button. |
| Batch stays *Holding* / *Queued* | Other batch jobs in the org are running; Salesforce runs at most 5 at a time. It starts when one finishes. |
| Error toast when clicking | *turned off* → custom setting: *Enabled* and API key, on the **Organization** default. *You do not have access to the Apex class* → assign the `AccountLocation_Geocoding` permission set. |
| Toast *Still running* | The job queue is busy. The job still finishes; refresh the page in a minute, or check **Setup → Apex Jobs**. |
| Toast *No suggestion* | Debug log of the user who clicked. `REQUEST_DENIED` = key or API not enabled / restricted. `OVER_QUERY_LIMIT` = quota or billing. `No Google Maps result` = address not found. |
| `Unauthorized endpoint` in log | Remote Site Setting missing or inactive. |
| `OpenStreetMap Nominatim HTTP 403` / `429` | Nominatim refused or rate-limited the org. Wait a few minutes and click less often. If 403 persists, Nominatim may be blocking Salesforce's shared IPs. Use Google instead. |
| `field "..." does not exist on ogg__Location__c` | *Original Latitude/Longitude Field* in the setting is wrong. |
| `Different_Distance__c` blank but Suggested filled | The original coordinates were empty when the job ran. Click the button again once UPWARD has set them. |
| Wrong country results | Results are restricted to Thailand in code (`GoogleMapsSettings.COUNTRY_CODE`); include the province and postcode in the address. |
| Result in a different district | The postcode check should catch it (`postcodeMatch=false` in the probe script). Make sure the address ends with the 5-digit postcode, and turn on *Use Places Fallback*. |
| A room/floor/building pattern isn't removed | Run the probe script to see `withoutUnit` / `streetLevel`. Add the pattern to `ThaiAddressNormalizer` (`ROOM_PATTERN`, `FLOOR_PATTERN`, `BUILDING_PATTERN`) with a test in `ThaiAddressNormalizerTest`. |

---

## 6. Sign-off checklist

- [ ] Unit tests pass, coverage ≥ 75% (target > 85%)
- [ ] TC-01 – TC-19 executed and results recorded
- [ ] Accuracy sample (§3) reviewed with the business
- [ ] API key restricted and quota set in Google Cloud
- [ ] Permission set assigned to the right users, fields on the layout
