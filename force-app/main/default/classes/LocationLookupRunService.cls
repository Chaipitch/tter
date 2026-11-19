/**
 * Shared logic for bulk runs started from the UI (Account list view page and the utility bar panel):
 * counting oggLocations not processed yet, finding a run that's still going, and reporting a run's
 * progress (from AsyncApexJob) and summary (counted from the data when it has finished).
 */
public with sharing class LocationLookupRunService {

    /** Counts stop here; the UI shows "10000+" beyond it. */
    public static final Integer COUNT_LIMIT = 10000;
    /** Suggested pin further than this from UPWARD's pin = worth checking (TESTING_GUIDE suggestion). */
    public static final Integer FAR_DISTANCE_METERS = 500;

    private static final Set<String> FINISHED_STATUSES = new Set<String>{ 'Completed', 'Failed', 'Aborted' };
    private static final Set<String> RUNNING_STATUSES  = new Set<String>{ 'Holding', 'Queued', 'Preparing', 'Processing' };

    /** Progress and, once finished, summary of one bulk run. */
    public class RunStatus {
        @AuraEnabled public Id jobId;
        @AuraEnabled public String status;
        @AuraEnabled public String message;
        @AuraEnabled public Integer batchesProcessed = 0;
        @AuraEnabled public Integer batchesTotal = 0;
        @AuraEnabled public Integer batchesFailed = 0;
        @AuraEnabled public Integer percent = 0;
        @AuraEnabled public Integer recordsInRun = 0;
        @AuraEnabled public Integer recordsDoneApprox = 0;
        @AuraEnabled public Boolean finished = false;
        // summary (only when finished)
        @AuraEnabled public Integer updatedCount;
        @AuraEnabled public Integer farCount;
        @AuraEnabled public Integer noDistanceCount;
        @AuraEnabled public Integer remainingCount;
    }

    /** oggLocations with isCoordsUpdated__c = false, counted up to COUNT_LIMIT + 1. */
    public static Integer countUnprocessed() {
        Integer countUpTo = COUNT_LIMIT + 1;
        return [
            SELECT COUNT() FROM ogg__Location__c
            WHERE isCoordsUpdated__c = false
            WITH SYSTEM_MODE
            LIMIT :countUpTo
        ];
    }

    /** Records a run will process: OpenStreetMap runs are capped. */
    public static Integer recordsForRun(Integer unprocessed) {
        Integer n = Math.min(unprocessed, COUNT_LIMIT);
        return GoogleMapsSettings.useOpenStreetMap()
            ? Math.min(n, AccountLocationGeocodeBatch.OSM_MAX_RECORDS_PER_RUN) : n;
    }

    /** The current user's AccountLocationGeocodeBatch that hasn't finished yet, or null. */
    public static AsyncApexJob findRunningJob() {
        List<AsyncApexJob> jobs = [
            SELECT Id, Status, CreatedDate, TotalJobItems
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
              AND ApexClass.Name = 'AccountLocationGeocodeBatch'
              AND Status IN :RUNNING_STATUSES
              AND CreatedById = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return jobs.isEmpty() ? null : jobs[0];
    }

    /**
     * Progress of the batch job; when it has finished, also the summary: oggLocations flagged since
     * startedAt (of which far / without distance) and those still unflagged.
     */
    public static RunStatus getStatus(Id jobId, Datetime startedAt, Integer recordsInRun) {
        RunStatus s = new RunStatus();
        s.jobId = jobId;
        s.recordsInRun = recordsInRun == null ? 0 : recordsInRun;
        List<AsyncApexJob> jobs = jobId == null ? new List<AsyncApexJob>() : [
            SELECT Status, ExtendedStatus, JobItemsProcessed, TotalJobItems, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
            WITH SYSTEM_MODE
        ];
        if (jobs.isEmpty()) {
            s.status = 'Unknown';
            return s;
        }
        AsyncApexJob job = jobs[0];
        s.status = job.Status;
        s.message = job.ExtendedStatus;
        s.batchesProcessed = job.JobItemsProcessed == null ? 0 : job.JobItemsProcessed;
        s.batchesTotal = job.TotalJobItems == null ? 0 : job.TotalJobItems;
        s.batchesFailed = job.NumberOfErrors == null ? 0 : job.NumberOfErrors;
        s.finished = FINISHED_STATUSES.contains(job.Status);

        if (s.finished) {
            s.percent = 100;
        } else if (s.batchesTotal > 0) {
            s.percent = (100.0 * s.batchesProcessed / s.batchesTotal).intValue();
        }
        if (s.recordsInRun == 0 && s.batchesTotal > 0) {
            s.recordsInRun = s.batchesTotal * GoogleMapsSettings.batchSize();   // estimate (resumed run)
        }
        s.recordsDoneApprox = s.finished
            ? s.recordsInRun : Math.min(s.recordsInRun, s.batchesProcessed * GoogleMapsSettings.batchSize());

        if (s.finished) {
            Integer countUpTo = COUNT_LIMIT + 1;
            Decimal far = FAR_DISTANCE_METERS;
            Datetime since = startedAt == null ? System.now().addDays(-1) : startedAt;
            s.updatedCount = [
                SELECT COUNT() FROM ogg__Location__c
                WHERE isCoordsUpdated__c = true AND SystemModstamp >= :since
                WITH SYSTEM_MODE LIMIT :countUpTo
            ];
            s.farCount = [
                SELECT COUNT() FROM ogg__Location__c
                WHERE isCoordsUpdated__c = true AND SystemModstamp >= :since AND Different_Distance__c > :far
                WITH SYSTEM_MODE LIMIT :countUpTo
            ];
            s.noDistanceCount = [
                SELECT COUNT() FROM ogg__Location__c
                WHERE isCoordsUpdated__c = true AND SystemModstamp >= :since AND Different_Distance__c = null
                WITH SYSTEM_MODE LIMIT :countUpTo
            ];
            s.remainingCount = countUnprocessed();
        }
        return s;
    }
}
