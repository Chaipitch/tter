/**
 * Controller extension for the Account list view button "Suggest Locations (Google)"
 * (Visualforce page SuggestLocationsFromAccounts).
 *
 * ogg__Location__c belongs to a managed package, so the bulk button lives on Account list views instead.
 * It ignores which Accounts are selected and starts AccountLocationGeocodeBatch for ALL oggLocation records
 * not processed yet (isCoordsUpdated__c = false). Progress is in Setup -> Apex Jobs.
 */
public with sharing class SuggestLocationsFromAccountsController {

    @TestVisible private static final Integer COUNT_LIMIT = 10000;

    private final ApexPages.StandardSetController setController;

    public Boolean started { get; private set; }
    public Id jobId { get; private set; }
    /** Number of oggLocations not processed yet (counted up to COUNT_LIMIT). */
    public Integer unprocessedCount { get; private set; }
    public Boolean moreThanCounted { get; private set; }

    public SuggestLocationsFromAccountsController(ApexPages.StandardSetController setController) {
        this.setController = setController;
        started = false;
        Integer countUpTo = COUNT_LIMIT + 1;
        Integer counted = [
            SELECT COUNT() FROM ogg__Location__c
            WHERE isCoordsUpdated__c = false
            WITH SYSTEM_MODE
            LIMIT :countUpTo
        ];
        moreThanCounted = counted > COUNT_LIMIT;
        unprocessedCount = Math.min(counted, COUNT_LIMIT);
    }

    public Boolean enabled {
        get { return GoogleMapsSettings.isEnabled(); }
    }

    public Boolean openStreetMap {
        get { return GoogleMapsSettings.useOpenStreetMap(); }
    }

    public Integer openStreetMapLimit {
        get { return AccountLocationGeocodeBatch.OSM_MAX_RECORDS_PER_RUN; }
    }

    public PageReference start() {
        try {
            jobId = AccountLocationGeocodeBatch.run(null);   // null = all with isCoordsUpdated__c = false
            started = true;
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.CONFIRM,
                'Location lookup started (batch job ' + jobId + ') for ' + unprocessedCount
                + (moreThanCounted ? '+' : '') + ' oggLocation record(s). It runs in the background; '
                + 'progress is in Setup > Apex Jobs.'));
        } catch (Exception e) {
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, e.getMessage()));
        }
        return null;
    }

    /** Back to the Account list view. */
    public PageReference back() {
        return setController.cancel();
    }
}
