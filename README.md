# AccountLocation – Google Maps Suggested Coordinates

This SFDX project adds Apex that checks the Account's single-field address against Google Maps every time an `ogg__Location__c` record is created. It stores Google's coordinates next to the ones UPWARD saved:

| Existing field on `ogg__Location__c` | Content |
|---|---|
| `Suggested_Latitude__c` | Latitude from Google Maps for the related Account's `Address__c` |
| `Suggested_Longtitude__c` | Longitude from Google Maps for the related Account's `Address__c` |
| `Different_Distance__c` | Distance in **meters** between the original and the suggested coordinates |

## How it works

```
ogg__Location__c inserted
   └─ AccountLocationTrigger (after insert)
        └─ AccountLocationTriggerHandler.afterInsert  ── enqueues ──►  AccountLocationGeocodeQueueable  (Database.AllowsCallouts)
                                                                         ├─ Account Id from ogg__ObjectId__c → Account.Address__c   (fallback: ogg__RawAddress__c)
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
│   ├── TestRecordFactory.cls                 @IsTest records with the org's required fields filled in
│   ├── AccountLocationGeocodingTest.cls      end-to-end trigger/queueable tests
│   ├── GoogleGeocodingServiceTest.cls
│   ├── GeoDistanceUtilTest.cls
│   └── ThaiAddressNormalizerTest.cls
├── triggers/AccountLocationTrigger.trigger
├── objects/Google_Maps_Settings__c/          hierarchy custom setting (API key, switches, field mapping)
├── remoteSiteSettings/                       maps.googleapis.com, places.googleapis.com
└── permissionsets/AccountLocation_Geocoding  read access to the 3 suggested/distance fields
manifest/package.xml                          deployment manifest
scripts/apex/                                 anonymous Apex: configure settings, probe an address, back-fill old records
docs/DEPLOYMENT_GUIDE.md                      ← start here
docs/TESTING_GUIDE.md
```

## Org facts this project relies on

| Item | API name |
|---|---|
| AccountLocation object (ogg package) | `ogg__Location__c` |
| Link to the Account | `ogg__ObjectId__c` (Text 18, the Account Id; `ogg__prefix__c` = `001`). There's no lookup field. |
| Address on Account | `Account.Address__c`. If the location isn't linked to an Account, `ogg__Location__c.ogg__RawAddress__c` is used instead. |
| Original coordinates | `ogg__Latitude__c`, `ogg__Longitude__c` |
| Target fields (already in the org, **not** deployed by this project) | `Suggested_Latitude__c`, `Suggested_Longtitude__c` (spelled *Longtitude* in the org), `Different_Distance__c` |
