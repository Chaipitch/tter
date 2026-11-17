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
  --code-coverage --result-format human --wait 15 \
  --target-org tterakit-sb
```

**Expected:** all tests pass, and every class and the trigger shows high coverage (> 85%). The tests use `GoogleMapsCalloutMock`, so **Google is never called** and no API key is needed.

| Test class | Covers |
|---|---|
| `AccountLocationGeocodingTest` | Insert → suggested lat/lng + distance; setting disabled; blank address; Google error doesn't fail the insert; original coordinates set later → distance recalculated; bypass flag; 60-record bulk insert (30 per job). Uses the Thai Emporium address. |
| `GoogleGeocodingServiceTest` | Thai search order (address without room/floor → street level → Places); postcode check; best-score choice; country/region/language params; Places failure keeps the Geocoding result; REQUEST_DENIED and HTTP 500 errors; blank address; settings defaults/validation |
| `ThaiAddressNormalizerTest` | Room/floor removal (`ห้องเลขที่ 91,96`, `ชั้นที่ 9`, `Room`, `12th Floor`); building removal; Thai digits; abbreviations (`ถ.`, `ซ.`, `ต.`, `อ.`, `จ.`, `ม.`, `กทม.`, `กรุงเทพฯ`); postcode extraction |
| `GeoDistanceUtilTest` | Distance math (known distances, same point = 0, null/out-of-range input) |

---

## 2. Functional tests (real Google calls)

### Preparation

* Add `Suggested Latitude`, `Suggested Longitude` and `Different Distance (m)` to the AccountLocation layout.
* Open **Setup → Debug Logs** and add a trace flag for **Automated Process** and for your user, with Apex = `DEBUG`. Errors from the job are written with `System.debug(LoggingLevel.ERROR, ...)`.
* Optionally, tail the logs live:

  ```bash
  sf apex tail log --color --target-org tterakit-sb
  ```

### How Thai addresses are searched

`ThaiAddressNormalizer` cleans each address, then `GoogleGeocodingService` tries up to 3 searches. It stops at the first result that is precise and whose postcode matches the address:

| Step | Query sent | Example for `622 อาคารเอ็มโพเรียม ทาวเวอร์ ห้องเลขที่ 91,96 ชั้นที่ 9 ถนนสุขุมวิท ... 10110` |
|---|---|---|
| 1. Geocoding API | Without room / floor | `622 อาคารเอ็มโพเรียม ทาวเวอร์ ถนนสุขุมวิท แขวงคลองตัน เขตคลองเตย กรุงเทพมหานคร 10110` |
| 2. Geocoding API | Street level (building removed too) | `622 ถนนสุขุมวิท แขวงคลองตัน เขตคลองเตย กรุงเทพมหานคร 10110` |
| 3. Places API (New), if enabled | Without room / floor | Same as step 1. Places is good at building names. |

Before searching, Thai digits (๐–๙) are converted, and abbreviations (`ถ.` `ซ.` `ต.` `อ.` `จ.` `ม.` `กทม.` `กรุงเทพฯ`) are expanded. If no result is good, the best one is used, ranked by postcode match first and precision second. A result whose postcode differs from the address ranks lowest.

### Test cases

Create each Account the way users normally do, so that UPWARD creates the AccountLocation. Wait about 5–30 seconds, then refresh the AccountLocation record.

| # | Scenario | Steps | Expected result |
|---|---|---|---|
| TC-01 | Thai address with building, room and floor | Account with `Address__c` = `622 อาคารเอ็มโพเรียม ทาวเวอร์ ห้องเลขที่ 91,96 ชั้นที่ 9 ถนนสุขุมวิท แขวงคลองตัน เขตคลองเตย กรุงเทพมหานคร 10110` | Suggested point is at the Emporium Tower on Sukhumvit (around 13.730, 100.569). The probe script (§4) shows `postcodeMatch=true`. |
| TC-02 | Thai digits and abbreviations | `เลขที่ ๙๙/๑ ม.๓ ต.บางพูด อ.ปากเกร็ด จ.นนทบุรี ๑๑๑๒๐` | The address is read as `99/1 หมู่ 3 ตำบลบางพูด อำเภอปากเกร็ด จังหวัดนนทบุรี 11120`. The suggested point is in Bang Phut, Pak Kret. |
| TC-03 | Real customer addresses that don't match Google exactly | Take 10–20 real customer addresses, including ones where the UPWARD pin is known to be wrong | Suggested coordinates point to the real place (check in Google Maps, see §3). Different Distance shows how far off the UPWARD pin was. With *Use Places Fallback* on, building or shop names are found through Places. |
| TC-04 | Nonsense address | `asdfgh 99999` | Suggested fields stay blank, no error for the user. The debug log shows `No Google Maps result`. |
| TC-05 | Blank address | AccountLocation whose Account has an empty `Address__c` | No callout. Fields stay blank. |
| TC-06 | Feature switched off | Uncheck *Enabled* in the custom setting and create a record | Nothing happens (no job in Apex Jobs). Re-enable after the test. |
| TC-07 | Invalid API key | Put a wrong key in the setting and create a record | Record saves normally. The log shows `Geocoding API status REQUEST_DENIED`. Restore the key. |
| TC-08 | Original coordinates arrive later | If UPWARD fills Lat/Lng after creation, or you edit them manually | Different Distance is recalculated on save. |
| TC-09 | Manual distance check | Edit the original Lat/Lng to the same values as Suggested | Different Distance = 0. |
| TC-10 | Bulk (Data Loader / Data Import Wizard) | Insert 100+ AccountLocation records (or Accounts, if UPWARD creates the locations) | All records get suggested values within a few minutes. **Setup → Apex Jobs** shows several chained `AccountLocationGeocodeQueueable` jobs, each Completed. |
| TC-11 | Non-admin user | Repeat TC-01 as a standard sales user | Same result. The job runs in system mode. The user can see the fields if the permission set is assigned. |
| TC-12 | Existing records back-fill (optional) | Run `sf apex run --file scripts/apex/regeocode-existing.apex --target-org tterakit-sb` | Old records without Suggested values get populated. |

### Checking the job

* **Setup → Apex Jobs:** look for `AccountLocationGeocodeQueueable` with status *Completed*. If the status is *Failed*, open the job to see the error.
* With SOQL:

  ```bash
  sf data query --target-org tterakit-sb --query "SELECT Id, Name, Suggested_Latitude__c, Suggested_Longitude__c, Different_Distance__c FROM ogg__Location__c ORDER BY CreatedDate DESC LIMIT 20"
  ```

  Add your original latitude/longitude field names to the `SELECT` to compare them.

---

## 3. Verifying accuracy

For a sample of records:

1. Open `https://www.google.com/maps?q=<Suggested_Latitude__c>,<Suggested_Longitude__c>` and confirm it shows the customer's location.
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
| Suggested fields never fill, no Apex Job | Custom setting: *Enabled* checked, API key present, and it is the **Organization** default. Check that the trigger is Active. |
| Job *Completed* but fields blank | Debug log of the Automated Process user / record creator. `REQUEST_DENIED` = key or API not enabled / restricted. `OVER_QUERY_LIMIT` = quota or billing. `No Google Maps result` = address not found. |
| `Unauthorized endpoint` in log | Remote Site Setting missing or inactive. |
| `field "..." does not exist on ogg__Location__c` | *Original Latitude/Longitude Field* in the setting is wrong. |
| `Different_Distance__c` blank but Suggested filled | The original coordinates were empty when the job ran. It's recalculated automatically when they're set. |
| `queueable limit reached` in log | The record was inserted from async code that had already used its one enqueue slot. Run `regeocode-existing.apex` for those records. |
| Wrong country results | Set *Country Code* = `TH` and *Region* = `th`. |
| Result in a different district | The postcode check should catch it (`postcodeMatch=false` in the probe script). Make sure the address ends with the 5-digit postcode, and turn on *Use Places Fallback*. |
| A room/floor/building pattern isn't removed | Run the probe script to see `withoutUnit` / `streetLevel`. Add the pattern to `ThaiAddressNormalizer` (`ROOM_PATTERN`, `FLOOR_PATTERN`, `BUILDING_PATTERN`) with a test in `ThaiAddressNormalizerTest`. |

---

## 6. Sign-off checklist

- [ ] Unit tests pass, coverage ≥ 75% (target > 85%)
- [ ] TC-01 – TC-11 executed and results recorded
- [ ] Accuracy sample (§3) reviewed with the business
- [ ] API key restricted and quota set in Google Cloud
- [ ] Permission set assigned to the right users, fields on the layout
