# AccountLocation – Google Maps Suggested Coordinates

This SFDX project adds Apex that checks the Account's single-field address against Google Maps every time an `ogg__Location__c` record is created. It stores Google's coordinates next to the ones UPWARD saved:

| Field (on `ogg__Location__c`) | Content |
|---|---|
| `Suggested_Latitude__c` | Latitude from Google Maps for `ogg__Account__r.Address__c` |
| `Suggested_Longitude__c` | Longitude from Google Maps for `ogg__Account__r.Address__c` |
| `Different_Distance__c` | Distance in **meters** between the original and the suggested coordinates |

## How it works

```
ogg__Location__c inserted
   └─ AccountLocationTrigger (after insert)
        └─ AccountLocationTriggerHandler.afterInsert  ── enqueues ──►  AccountLocationGeocodeQueueable  (Database.AllowsCallouts)
                                                                         ├─ SOQL: ogg__Account__r.Address__c + original lat/lng
                                                                         ├─ ThaiAddressNormalizer.prepare(address)   Thai digits, ถ./ซ./กทม. ..., drop room/floor
                                                                         ├─ GoogleGeocodingService.findCoordinates(address)   max 3 callouts, stops at first good result
                                                                         │     1. Geocoding API  – without room/floor
                                                                         │     2. Geocoding API  – street level (no building name)
                                                                         │     3. (optional) Places API (New) Text Search – without room/floor
                                                                         │     "good" = precise AND postcode matches the address
                                                                         ├─ GeoDistanceUtil.distanceInMeters(original, suggested)
                                                                         └─ update Suggested_* + Different_Distance__c   (chains itself for > Batch Size)

ogg__Location__c updated (original or suggested coordinates changed, e.g. UPWARD sets them later)
   └─ AccountLocationTrigger (before update) ─► Different_Distance__c recalculated
```

Apex can't make callouts inside a trigger, so the lookup runs asynchronously, usually a few seconds after the record is saved.

## Project layout

```
force-app/main/default/
├── classes/
│   ├── AccountLocationTriggerHandler.cls     trigger logic (enqueue + distance recalculation)
│   ├── AccountLocationGeocodeQueueable.cls   async callout + update, self-chaining
│   ├── GoogleGeocodingService.cls            Google Geocoding / Places (New) HTTP client
│   ├── GoogleMapsSettings.cls                reads the Google_Maps_Settings__c custom setting
│   ├── ThaiAddressNormalizer.cls             cleans Thai addresses into search variants + postcode
│   ├── GeoDistanceUtil.cls                   distance (meters) helper
│   ├── GoogleMapsCalloutMock.cls             @IsTest HTTP mock
│   ├── AccountLocationGeocodingTest.cls      end-to-end trigger/queueable tests
│   ├── GoogleGeocodingServiceTest.cls
│   ├── GeoDistanceUtilTest.cls
│   └── ThaiAddressNormalizerTest.cls
├── triggers/AccountLocationTrigger.trigger
├── objects/
│   ├── ogg__Location__c/fields/            Suggested_Latitude__c, Suggested_Longitude__c, Different_Distance__c
│   └── Google_Maps_Settings__c/              hierarchy custom setting (API key, switches, field mapping)
├── remoteSiteSettings/                       maps.googleapis.com, places.googleapis.com
└── permissionsets/AccountLocation_Geocoding  read access to the 3 new fields
manifest/package.xml                          deployment manifest
scripts/apex/                                 anonymous Apex: configure settings, probe an address, back-fill old records
docs/DEPLOYMENT_GUIDE.md                      ← start here
docs/TESTING_GUIDE.md
```

## Assumptions to confirm before deploying

These are covered in detail in [docs/DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md#1-pre-deployment-checks-in-the-sandbox):

1. The object and field names are already set: `ogg__Location__c` (the ogg package's AccountLocation object), its lookup `ogg__Account__c` → Account, and `Account.Address__c`.
2. The Account address field is `Account.Address__c`.
3. The API names of the original latitude/longitude fields. These are set in the custom setting, so no code change is needed.
4. Whether `Suggested_Latitude__c`, `Suggested_Longitude__c` and `Different_Distance__c` already exist in the org.
