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
  --code-coverage --result-format human --wait 15 \
  --target-org tterakit-sb
```

**Expected:** all tests pass, and every class shows high coverage (> 85%). The tests use `GoogleMapsCalloutMock`, so **Google is never called** and no API key is needed.

| Test class | Covers |
|---|---|
| `AccountLocationGeocodingTest` | Button Apex (`enqueue` → job → `getStatus`) fills suggested lat/lng + distance; an insert alone does nothing; setting disabled and wrong record type report an error; blank address; Google error leaves the record unchanged; no original coordinates → no distance; `ogg__RawAddress__c` fallback; back-fill job with 60 records (30 per execution). Uses the Thai Emporium address. |
| `GoogleGeocodingServiceTest` | Thai search order (address without room/floor → street level → Places); postcode check; best-score choice; country/region/language params; Places failure keeps the Geocoding result; REQUEST_DENIED and HTTP 500 errors; blank address; settings defaults/validation |
| `ThaiAddressNormalizerTest` | Room/floor removal (`ห้องเลขที่ 91,96`, `ชั้นที่ 9`, `Room`, `12th Floor`); building removal; Thai digits; abbreviations (`ถ.`, `ซ.`, `ต.`, `อ.`, `จ.`, `ม.`, `กทม.`, `กรุงเทพฯ`); postcode extraction |
| `OpenStreetMapGeocoderTest` | Provider switch (`OpenStreetMap`/`OSM`/blank/`Google`); enabled without an API key; batch capped at 10; Nominatim request (`format=jsonv2`, `countrycodes`, `accept-language`, User-Agent, no key); area result → street-level query; best result when only area results; empty result; HTTP 429; button end to end with OpenStreetMap; Google and Places never called |
| `GeoDistanceUtilTest` | Distance math (known distances, same point = 0, null/out-of-range input) |

---

## 2. Functional tests (real Google calls)

### Preparation

* Put the **Suggest Location (Google)** button and the `Suggested Latitude`, `Suggested Longtitude` and `Different Distance` fields on the oggLocation page (DEPLOYMENT_GUIDE 3.5).
* Open **Setup → Debug Logs** and add a trace flag for **your user** (the job runs as the user who clicked the button), with Apex = `DEBUG`. Errors from the job are written with `System.debug(LoggingLevel.ERROR, ...)`.
* Optionally, tail the logs live:

  ```bash
  sf apex tail log --color --target-org tterakit-sb
  ```

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

Create each Account the way users normally do, so that UPWARD creates the oggLocation record. Open that oggLocation record and click **Suggest Location (Google)**. Within a few seconds a toast shows the result and the record refreshes.

| # | Scenario | Steps | Expected result |
|---|---|---|---|
| TC-01 | Thai address with building, room and floor | Account with `Address__c` = `622 อาคารเอ็มโพเรียม ทาวเวอร์ ห้องเลขที่ 91,96 ชั้นที่ 9 ถนนสุขุมวิท แขวงคลองตัน เขตคลองเตย กรุงเทพมหานคร 10110` | Suggested point is at the Emporium Tower on Sukhumvit (around 13.730, 100.569). The probe script (§4) shows `postcodeMatch=true`. |
| TC-02 | Thai digits and abbreviations | `เลขที่ ๙๙/๑ ม.๓ ต.บางพูด อ.ปากเกร็ด จ.นนทบุรี ๑๑๑๒๐` | The address is read as `99/1 หมู่ 3 ตำบลบางพูด อำเภอปากเกร็ด จังหวัดนนทบุรี 11120`. The suggested point is in Bang Phut, Pak Kret. |
| TC-03 | Real customer addresses that don't match Google exactly | Take 10–20 real customer addresses, including ones where the UPWARD pin is known to be wrong | Suggested coordinates point to the real place (check in Google Maps, see §3). Different Distance shows how far off the UPWARD pin was. With *Use Places Fallback* on, building or shop names are found through Places. |
| TC-04 | Nonsense address | `asdfgh 99999` | Toast *No suggestion*; fields stay blank. The debug log shows `No Google Maps result`. |
| TC-05 | Blank address | oggLocation whose Account has an empty `Address__c` | Toast *No suggestion*. No callout; fields stay blank. |
| TC-06 | Feature switched off | Uncheck *Enabled* in the custom setting and click the button | Error toast *Google Maps lookup is turned off…*; no job in Apex Jobs. Re-enable after the test. |
| TC-07 | Invalid API key | Put a wrong key in the setting and click the button | Toast *No suggestion*; record unchanged. The log shows `Geocoding API status REQUEST_DENIED`. Restore the key. |
| TC-08 | No automatic run | Create a new Account / oggLocation and don't click the button | Suggested fields stay blank. Nothing appears in Apex Jobs. |
| TC-09 | Click again after UPWARD changes its pin | Change the original Lat/Lng (or wait for UPWARD to update it), click the button again | Suggested values and Different Distance are refreshed. If you set the original Lat/Lng to the suggested values first, the distance is 0. |
| TC-10 | Double click | Click the button twice quickly | Only one lookup runs; one result toast. |
| TC-11 | Non-admin user | Repeat TC-01 as a standard sales user with the permission set | Same result. Without the permission set, the button shows an error. |
| TC-12 | Many records at once (optional) | Run `sf apex run --file scripts/apex/regeocode-existing.apex --target-org tterakit-sb` | Records without Suggested values get populated within a few minutes. **Setup → Apex Jobs** shows chained `AccountLocationGeocodeQueueable` jobs, each Completed. |

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

The output first shows the query variants built from the Thai address (`withoutUnit`, `streetLevel`, `postcode`). Then it shows the chosen result: its source (`GEOCODING_API` or `PLACES_TEXT_SEARCH`), the query that produced it, `location_type`, `partial_match`, `postcode` / `postcodeMatch`, and Google's formatted address. Use it to tune *Country Code*, *Region*, *Language* and *Use Places Fallback*.

---

## 5. Troubleshooting at runtime

| Symptom | Check |
|---|---|
| Button missing | It isn't on the page layout / Lightning page yet (DEPLOYMENT_GUIDE 3.5). |
| Error toast when clicking | *turned off* → custom setting: *Enabled* and API key, on the **Organization** default. *You do not have access to the Apex class* → assign the `AccountLocation_Geocoding` permission set. |
| Toast *Still running* | The job queue is busy. The job still finishes; refresh the page in a minute, or check **Setup → Apex Jobs**. |
| Toast *No suggestion* | Debug log of the user who clicked. `REQUEST_DENIED` = key or API not enabled / restricted. `OVER_QUERY_LIMIT` = quota or billing. `No Google Maps result` = address not found. |
| `Unauthorized endpoint` in log | Remote Site Setting missing or inactive. |
| `OpenStreetMap Nominatim HTTP 403` / `429` | Nominatim refused or rate-limited the org. Wait a few minutes and click less often. If 403 persists, Nominatim may be blocking Salesforce's shared IPs. Use Google instead. |
| `field "..." does not exist on ogg__Location__c` | *Original Latitude/Longitude Field* in the setting is wrong. |
| `Different_Distance__c` blank but Suggested filled | The original coordinates were empty when the job ran. Click the button again once UPWARD has set them. |
| Wrong country results | Set *Country Code* = `TH` and *Region* = `th`. |
| Result in a different district | The postcode check should catch it (`postcodeMatch=false` in the probe script). Make sure the address ends with the 5-digit postcode, and turn on *Use Places Fallback*. |
| A room/floor/building pattern isn't removed | Run the probe script to see `withoutUnit` / `streetLevel`. Add the pattern to `ThaiAddressNormalizer` (`ROOM_PATTERN`, `FLOOR_PATTERN`, `BUILDING_PATTERN`) with a test in `ThaiAddressNormalizerTest`. |

---

## 6. Sign-off checklist

- [ ] Unit tests pass, coverage ≥ 75% (target > 85%)
- [ ] TC-01 – TC-12 executed and results recorded
- [ ] Accuracy sample (§3) reviewed with the business
- [ ] API key restricted and quota set in Google Cloud
- [ ] Permission set assigned to the right users, fields on the layout
