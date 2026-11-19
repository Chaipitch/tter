/**
 * Server side of the utility bar panel "Suggest Locations" (LWC suggestLocationsPanel).
 * The panel floats over any page (e.g. the Account list view) and runs the same bulk lookup as the Account
 * list view button: AccountLocationGeocodeBatch for all oggLocations with isCoordsUpdated__c = false.
 *
 *  getOverview()                 settings, number not processed yet, and a run of this user that is still going
 *  startRun()                    starts the batch; returns what the panel needs to follow it
 *  getStatus(jobId, ...)         progress, and the summary once finished (LocationLookupRunService)
 */
public with sharing class SuggestLocationsPanelController {

    @AuraEnabled
    public static Map<String, Object> getOverview() {
        Integer counted = LocationLookupRunService.countUnprocessed();
        Map<String, Object> result = new Map<String, Object>{
            'enabled' => GoogleMapsSettings.isEnabled(),
            'openStreetMap' => GoogleMapsSettings.useOpenStreetMap(),
            'openStreetMapLimit' => AccountLocationGeocodeBatch.OSM_MAX_RECORDS_PER_RUN,
            'farDistanceMeters' => LocationLookupRunService.FAR_DISTANCE_METERS,
            'unprocessedCount' => Math.min(counted, LocationLookupRunService.COUNT_LIMIT),
            'moreThanCounted' => counted > LocationLookupRunService.COUNT_LIMIT
        };
        AsyncApexJob running = LocationLookupRunService.findRunningJob();
        if (running != null) {
            result.put('runningJob', new Map<String, Object>{
                'jobId' => running.Id,
                // One second back: record timestamps are compared to the second
                'startedAtMs' => running.CreatedDate.addSeconds(-1).getTime()
            });
        }
        return result;
    }

    @AuraEnabled
    public static Map<String, Object> startRun() {
        if (!GoogleMapsSettings.isEnabled()) {
            throw error('Location lookup is turned off. Ask your administrator to enable Google Maps Settings '
                + '(and add an API key, or set Provider to OpenStreetMap).');
        }
        Integer recordsInRun = LocationLookupRunService.recordsForRun(LocationLookupRunService.countUnprocessed());
        if (recordsInRun == 0) {
            throw error('There are no oggLocation records to process (all have isCoordsUpdated checked).');
        }
        Long startedAtMs = System.now().addSeconds(-1).getTime();
        Id jobId = AccountLocationGeocodeBatch.run(null);
        return new Map<String, Object>{
            'jobId' => jobId,
            'startedAtMs' => startedAtMs,
            'recordsInRun' => recordsInRun
        };
    }

    @AuraEnabled
    public static LocationLookupRunService.RunStatus getStatus(Id jobId, Long startedAtMs, Integer recordsInRun) {
        Datetime startedAt = startedAtMs == null ? null : Datetime.newInstance(startedAtMs);
        return LocationLookupRunService.getStatus(jobId, startedAt, recordsInRun);
    }

    /** AuraHandledException with a message that is also visible to Apex tests. */
    private static AuraHandledException error(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}
