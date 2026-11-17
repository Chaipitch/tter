# AccountLocation – Google Maps Suggested Coordinates

This SFDX project adds a **"Suggest Location (Google)"** quick action button to `ogg__Location__c`. Clicking it checks the Account's single-field address against Google Maps in the background, and stores Google's coordinates next to the ones UPWARD saved:

| Existing field on `ogg__Location__c` | Content |
|---|---|
| `Suggested_Latitude__c` | Latitude from Google Maps for the related Account's `Address__c` |
| `Suggested_Longtitude__c` | Longitude from Google Maps for the related Account's `Address__c` |
| `Different_Distance__c` | Distance in **meters** between the original and the suggested coordinates |

## How it works

Full explanation: [docs/HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md). Current status and next steps: [HANDOFF.md](HANDOFF.md).

```
User clicks "Suggest Location (Google)" on an ogg__Location__c record
   └─ LWC suggestGoogleLocation (headless quick action)
        └─ AccountLocationGeocodeAction.enqueue(recordId)  ── enqueues ──►  AccountLocationGeocodeQueueable  (Database.AllowsCallouts)
                                                                              ├─ Account Id from ogg__ObjectId__c → Account.Address__c   (fallback: ogg__RawAddress__c)
                                                                              ├─ ThaiAddressNormalizer.prepare(address)   Thai digits, ถ./ซ./กทม. ..., drop room/floor
                                                                              ├─ GoogleGeocodingService.findCoordinates(address)   max 3 callouts, stops at first good result
                                                                              │     1. Geocoding API  – without room/floor
                                                                              │     2. Geocoding API  – street level (no building name)
                                                                              │     3. (optional) Places API (New) Text Search – without room/floor
                                                                              │     "good" = precise AND postcode matches the address
                                                                              ├─ GeoDistanceUtil.distanceInMeters(original, suggested)
                                                                              └─ update Suggested_* + Different_Distance__c
   └─ LWC polls AccountLocationGeocodeAction.getStatus every 2 s, refreshes the record, shows a toast
```

The lookup runs as a background (Queueable) job because Google is called over HTTP. It usually finishes within a few seconds. Many records at once (back-fill): `scripts/apex/regeocode-existing.apex`, which runs the same job in batches of 30.

## Project layout

```
force-app/main/default/
├── classes/
│   ├── AccountLocationGeocodeAction.cls      Apex behind the button: start the job, report its status
│   ├── AccountLocationGeocodeQueueable.cls   async callout + update, self-chaining
│   ├── GoogleGeocodingService.cls            Google Geocoding / Places (New) HTTP client
│   ├── GoogleMapsSettings.cls                reads the Google_Maps_Settings__c custom setting
│   ├── OpenStreetMapGeocoder.cls             TEMPORARY no-key provider (OpenStreetMap Nominatim)
│   ├── ThaiAddressNormalizer.cls             cleans Thai addresses into search variants + postcode
│   ├── GeoDistanceUtil.cls                   distance (meters) helper
│   ├── GoogleMapsCalloutMock.cls             @IsTest HTTP mock
│   ├── TestRecordFactory.cls                 @IsTest records with the org's required fields filled in
│   ├── AccountLocationGeocodingTest.cls      end-to-end button/queueable tests
│   ├── GoogleGeocodingServiceTest.cls
│   ├── GeoDistanceUtilTest.cls
│   ├── ThaiAddressNormalizerTest.cls
│   └── OpenStreetMapGeocoderTest.cls
├── lwc/suggestGoogleLocation/                headless quick action (button → job → toast)
├── quickActions/ogg__Location__c.Suggest_Google_Location   the "Suggest Location (Google)" button
├── objects/Google_Maps_Settings__c/          hierarchy custom setting (API key, switches, field mapping)
├── remoteSiteSettings/                       maps.googleapis.com, places.googleapis.com, nominatim.openstreetmap.org
└── permissionsets/AccountLocation_Geocoding  read access to the 3 suggested/distance fields
manifest/package.xml                          deployment manifest
manifest/destructiveChanges.xml               removes the old trigger from orgs that had it
scripts/apex/                                 anonymous Apex: configure settings (Google or OpenStreetMap), probe an address, back-fill old records
docs/HOW_IT_WORKS.md                         how the feature works, design decisions, limits
docs/DEPLOYMENT_GUIDE.md                      deploy to a sandbox / production
docs/TESTING_GUIDE.md                         unit + functional tests
HANDOFF.md                                    ← start here: status, next steps, org facts
```

## Org facts this project relies on

| Item | API name |
|---|---|
| AccountLocation object (ogg package) | `ogg__Location__c` |
| Link to the Account | `ogg__ObjectId__c` (Text 18, the Account Id; `ogg__prefix__c` = `001`). There's no lookup field. |
| Address on Account | `Account.Address__c`. If `ogg__ObjectId__c` points to a record that isn't an Account (or the Account is gone), `ogg__Location__c.ogg__RawAddress__c` is used instead. |
| Original coordinates | `ogg__Latitude__c`, `ogg__Longitude__c` |
| Target fields (already in the org, **not** deployed by this project) | `Suggested_Latitude__c`, `Suggested_Longtitude__c` (spelled *Longtitude* in the org), `Different_Distance__c` |
