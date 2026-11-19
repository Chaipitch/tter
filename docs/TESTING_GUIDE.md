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
| `AccountLocationGeocodingTest` | On-create trigger: an insert is looked up automatically and flagged; records inserted already flagged are skipped; *Disable Lookup On Create* skips the trigger but the buttons still work; a 60-record insert queues one job (30 per execution). Record button Apex (`enqueue` → job → `getStatus`) fills suggested lat/lng + distance; setting disabled and wrong record type report an error; blank address; Google error leaves the record unchanged; no original coordinates → no distance; Billing Address used when `Address__c` is blank (address order: `Address__c` → Billing; no Account → skipped, `ogg__RawAddress__c` ignored). Uses the Thai Emporium address. |
| `GoogleGeocodingServiceTest` | Thai search order (address without room/floor → street level → Places); postcode check; best-score choice; country/region/language params; Places failure keeps the Geocoding result; REQUEST_DENIED and HTTP 500 errors; blank address; settings defaults/validation |
| `ThaiAddressNormalizerTest` | Room/floor removal (`ห้องเลขที่ 91,96`, `ชั้นที่ 9`, `Room`, `12th Floor`); building removal; Thai digits; abbreviations (`ถ.`, `ซ.`, `ต.`, `อ.`, `จ.`, `ม.`, `กทม.`, `กรุงเทพฯ`); postcode extraction |
| `OpenStreetMapGeocoderTest` | Provider switch (`OpenStreetMap`/`OSM`/blank/`Google`); enabled without an API key; batch capped at 10; Nominatim request (`format=jsonv2`, `countrycodes`, `accept-language`, User-Agent, no key); area result → street-level query; best result when only area results; empty result; HTTP 429; button end to end with OpenStreetMap; Google and Places never called |
| `AccountLocationGeocodeBatchTest` | Bulk: a run processes all records with `isCoordsUpdated__c` = false and flags them; the flag (not Suggested Latitude) decides what a run picks up; a run with record Ids processes those even if flagged; feature off can't start; OpenStreetMap run capped at 200 (Google not capped); scheduled entry point; Account list view button controller: counts unprocessed oggLocations, ignores the selection, starts the batch, reports progress while it runs and a summary when it's finished (updated, > 500 m, no distance, still not processed), and shows an error when the feature is off; utility bar panel controller: overview, start, picking up a running job, progress and summary, refusal when off or nothing to do |