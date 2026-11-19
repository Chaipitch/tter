# AccountLocation – Google Maps Suggested Coordinates

This SFDX project checks the Account's single-field address of `ogg__Location__c` records against Google Maps in the background, and stores Google's coordinates next to the ones UPWARD saved. Ways it runs:

* **Automatically when an oggLocation is created** (trigger, after insert). Can be switched off with *Disable Lookup On Create* in the custom setting, for example during a large data load.
* **Account list view button "Suggest Locations (Google)"**: processes **all oggLocations not processed yet (`isCoordsUpdated__c` unchecked)**, whichever Accounts are selected. It lives on Account because oggLocation belongs to a managed package. Runs as Batch Apex, with a progress bar and a summary when it's finished. Each processed record gets `isCoordsUpdated__c` = true, so it isn't processed again.
* **"Suggest Locations" utility bar panel**: the same bulk run in a panel that floats over any page (e.g. the Account list view), with progress, a summary and a toast. It keeps following the run while you navigate.
* **Scheduled run** (for example nightly) over all records not processed yet: `scripts/apex/schedule-nightly.apex`.
* **Record button "Suggest Location (Google)"**: one record, with the result shown in a toast.

The Account list view button and the schedule are for **large volumes**: existing records, and records the trigger skipped. To re-check a processed record, untick its `isCoordsUpdated__c` or use the record button.

Fields written:

| Existing field on `ogg__Location__c` | Content |
|---|---|
| `Suggested_Latitude__c` | Latitude from Google Maps for the related Account's `Address__c` |
| `Suggested_Longtitude__c` | Longitude from Google Maps for the related Account's `Address__c` |
| `Different_Distance__c` | Distance in **meters** between the original and the suggested coordinates |
| `isCoordsUpdated__c` | Set to true once coordinates were written; automatic runs skip records where it's true |

## How it works

Full explanation: [docs/HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md). Current status and next steps: [HANDOFF.md](HANDOFF.md).

```
Bulk:   Account list view button "Suggest Locations (Google)" ─► VF page SuggestLocationsFromAccounts (confirm)
        scheduled job / regeocode-existing.apex          │
                                                          ▼
                                       AccountLocationGeocodeBatch  (Batch Apex, 30 records per execute; 10 with OpenStreetMap)
                                         all oggLocations with isCoordsUpdated__c = false
                                                          │
Create: ogg__Location__c inserted ─► AccountLocationTrigger ─► AccountLocationTriggerHandler ─┐
Single: record button "Suggest Location (Google)" ─► LWC ─► AccountLocationGeocodeAction ─────┴─► AccountLocationGeocodeQueueable
                                                          │                          (record button: toast with the result)
                                                          ▼
                                       AccountLocationGeocodeProcessor.process(ids)   (shared)
                                         ├─ Account Id from ogg__ObjectId__c → Account.Address__c   (blank: Account Billing Address)
                                         ├─ ThaiAddressNormalizer.prepare(address)   Thai digits, ถ./ซ./กทม. ..., drop room/floor
                                         ├─ GoogleGeocodingService.findCoordinates(address)   max 3 callouts, stops at first good result
                                         │     1. Geocoding API – without room/floor   2. – street level   3. (optional) Places API (New)
                                         │     (Provider = OpenStreetMap: Nominatim for 1 and 2, temporary)
                                         ├─ GeoDistanceUtil.distanceInMeters(original, suggested)
                                         └─ update Suggested_* + Different_Distance__c
```

## Project layout

```
force-app/main/default/
├── classes/
│   ├── AccountLocationGeocodeBatch.cls       BULK: Batch Apex over selected / all records not processed yet; Schedulable
│   ├── SuggestLocationsFromAccountsController.cls  Account list view button page controller
│   ├── SuggestLocationsPanelController.cls   utility bar panel Apex (overview, start, status)
│   ├── LocationLookupRunService.cls          shared: count, running job, progress + summary
│   ├── AccountLocationGeocodeProcessor.cls   shared: find address, geocode, save (used by batch + queueable)
│   ├── AccountLocationTriggerHandler.cls     on create: queue the lookup for new records
│   ├── AccountLocationGeocodeAction.cls      record button Apex: start the job, report its status
│   ├── AccountLocationGeocodeQueueable.cls   job for the trigger and the record button
│   ├── GoogleGeocodingService.cls            Google Geocoding / Places (New) HTTP client
│   ├── GoogleMapsSettings.cls                reads the Google_Maps_Settings__c custom setting
│   ├── OpenStreetMapGeocoder.cls             TEMPORARY no-key provider (OpenStreetMap Nominatim)
│   ├── ThaiAddressNormalizer.cls             cleans Thai addresses into search variants + postcode
│   ├── GeoDistanceUtil.cls                   distance (meters) helper
│   ├── GoogleMapsCalloutMock.cls             @IsTest HTTP mock
│   ├── TestRecordFactory.cls                 @IsTest records with the org's required fields filled in
│   ├── AccountLocationGeocodeBatchTest.cls   bulk: batch, schedule, Account list view button
│   ├── AccountLocationGeocodingTest.cls      end-to-end trigger / record button / queueable tests
│   ├── GoogleGeocodingServiceTest.cls
│   ├── GeoDistanceUtilTest.cls
│   ├── ThaiAddressNormalizerTest.cls
│   └── OpenStreetMapGeocoderTest.cls
├── triggers/AccountLocationTrigger.trigger   after insert on ogg__Location__c
├── pages/SuggestLocationsFromAccounts.page   Account list view button confirmation page
├── objects/Account/webLinks/Suggest_Locations_Google   the Account list view button
├── lwc/suggestLocationsPanel/                utility bar panel (floats over any page)
├── lwc/suggestGoogleLocation/                headless quick action (button → job → toast)
├── quickActions/ogg__Location__c.Suggest_Google_Location   the "Suggest Location (Google)" button
├── objects/Google_Maps_Settings__c/          hierarchy custom setting (API key, switches, field mapping)
├── remoteSiteSettings/                       maps.googleapis.com, places.googleapis.com, nominatim.openstreetmap.org
└── permissionsets/AccountLocation_Geocoding  access to both buttons + read access to the 3 suggested/distance fields
manifest/package.xml                          deployment manifest
scripts/apex/                                 anonymous Apex: configure settings (Google or OpenStreetMap), probe an address, bulk run, nightly schedule
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
| Address on Account | `Account.Address__c`; if it's blank, the Account's **Billing Address** (Street, City, State, Postal Code; Country unless Thailand). No Account (`ogg__ObjectId__c` isn't an Account Id) or no address: the record is skipped. `ogg__RawAddress__c` is not used. |
| Original coordinates | `ogg__Latitude__c`, `ogg__Longitude__c` |
| Target fields (already in the org, **not** deployed by this project) | `Suggested_Latitude__c`, `Suggested_Longtitude__c` (spelled *Longtitude* in the org), `Different_Distance__c`, `isCoordsUpdated__c` (checkbox: processed) |
