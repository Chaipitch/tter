// Back-fills Suggested_Latitude__c / Suggested_Longtitude__c / Different_Distance__c for EXISTING
// ogg__Location__c records at once (instead of clicking the button on each record).
// Records whose Account has a blank Address__c are skipped by the job.
// The job processes Batch_Size__c records and chains itself for the rest.
// Run:  sf apex run --file scripts/apex/regeocode-existing.apex --target-org tterakit-sb
List<Id> ids = new List<Id>(new Map<Id, ogg__Location__c>([
    SELECT Id FROM ogg__Location__c
    WHERE Suggested_Latitude__c = null
    ORDER BY CreatedDate DESC
    LIMIT 2000
]).keySet());
System.debug(LoggingLevel.ERROR, 'Queued ' + ids.size() + ' records, job Id: '
    + System.enqueueJob(new AccountLocationGeocodeQueueable(ids)));
