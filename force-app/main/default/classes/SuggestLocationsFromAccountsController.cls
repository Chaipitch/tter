/**
 * Controller extension for the Account list view button "Suggest Locations (Google)"
 * (Visualforce page SuggestLocationsFromAccounts).
 *
 * ogg__Location__c belongs to a managed package, so the bulk button lives on Account list views instead.
 * It ignores which Accounts are selected and starts AccountLocationGeocodeBatch for ALL oggLocation records
 * not processed yet (isCoordsUpdated__c = false).
 *
 * After Start, the page polls refreshStatus() every few seconds: a progress bar from the batch job
 * (AsyncApexJob), and a summary when the job has finished. The summary is counted from the data:
 * oggLocations flagged since the run started, and those still unflagged.
 */
public with sharing class SuggestLocationsFromAccountsController {

    @TestVisible private static final Integer COUNT_LIMIT = LocationLookupRunService.COUNT_LIMIT;
    /** Suggested pin further than this from UPWARD's pin = worth checking (TESTING_GUIDE suggestion). */
    public static final Integer FAR_DISTANCE_METERS = LocationLookupRunService.FAR_DISTANCE_METERS;

    private final ApexPages.StandardSetController setController;

    public Boolean started { get; private set; }
    public Id jobId { get; private set; }
    /** Number of oggLocations not processed yet (counted up to COUNT_LIMIT). */
    public Integer unprocessedCount { get; private set; }
    public Boolean moreThanCounted { get; private set; }

    // ---- progress (from AsyncApexJob) ----
    public Datetime startedAt { get; private set; }
    public String jobStatus { get; private set; }
    public String jobMessage { get; private set; }
    public Integer batchesProcessed { get; private set; }
    public Integer batchesTotal { get; private set; }
    public Integer batchesFailed { get; private set; }
    public Integer percent { get; private set; }
    public Integer recordsInRun { get; private set; }
    public Integer recordsDoneApprox { get; private set; }
    public Boolean finished { get; private set; }

    // ---- summary (counted when finished) ----
    public Integer updatedCount { get; private set; }
    public Integer farCount { get; private set; }
    public Integer noDistanceCount { get; private set; }
    public Integer remainingCount { get; private set; }

    public SuggestLocationsFromAccountsController(ApexPages.StandardSetController setController) {
        this.setController = setController;
        started = false;
        finished = false;
        percent = 0;
        Integer counted = LocationLookupRunService.countUnprocessed();
        moreThanCounted = counted > COUNT_LIMIT;
        unprocessedCount = Math.min(counted, COUNT_LIMIT);
    }

    public Boolean enabled {
        get { return GoogleMapsSettings.isEnabled(); }
    }

    /** FAR_DISTANCE_METERS for the page (Visualforce reads instance properties only). */
    public Integer farDistanceMeters {
        get { return FAR_DISTANCE_METERS; }
    }

    public Boolean openStreetMap {
        get { return GoogleMapsSettings.useOpenStreetMap(); }
    }

    public Integer openStreetMapLimit {
        get { return AccountLocationGeocodeBatch.OSM_MAX_RECORDS_PER_RUN; }
    }

    /** True while the page should keep polling. */
    public Boolean polling {
        get { return started && !finished; }
    }

    public PageReference start() {
        try {
            // One second back: record timestamps are compared to the second
            startedAt = System.now().addSeconds(-1);
            recordsInRun = LocationLookupRunService.recordsForRun(unprocessedCount);
            jobId = AccountLocationGeocodeBatch.run(null);   // null = all with isCoordsUpdated__c = false
            started = true;
            refreshStatus();
        } catch (Exception e) {
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, e.getMessage()));
        }
        return null;
    }

    /** Called by the page's poller: reads the batch job; counts the summary once it has finished. */
    public PageReference refreshStatus() {
        if (jobId == null) {
            return null;
        }
        LocationLookupRunService.RunStatus st = LocationLookupRunService.getStatus(jobId, startedAt, recordsInRun);
        jobStatus = st.status;
        jobMessage = st.message;
        batchesProcessed = st.batchesProcessed;
        batchesTotal = st.batchesTotal;
        batchesFailed = st.batchesFailed;
        percent = st.percent;
        recordsDoneApprox = st.recordsDoneApprox;
        finished = st.finished;
        updatedCount = st.updatedCount;
        farCount = st.farCount;
        noDistanceCount = st.noDistanceCount;
        remainingCount = st.remainingCount;
        return null;
    }

    /** Back to the Account list view. */
    public PageReference back() {
        return setController.cancel();
    }
}
