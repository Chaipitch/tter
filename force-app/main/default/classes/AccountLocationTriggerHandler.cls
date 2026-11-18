/**
 * Handler for AccountLocationTrigger (ogg__Location__c, after insert).
 *
 * New oggLocation records are looked up automatically: one AccountLocationGeocodeQueueable is queued for the
 * whole trigger batch (it processes GoogleMapsSettings.batchSize() records per execution and chains the
 * rest), using the same AccountLocationGeocodeProcessor as the list view button and the record button.
 *
 * Skipped when:
 *   - the feature is off, or Google_Maps_Settings__c.Disable_Lookup_On_Create__c is checked
 *   - AccountLocationTriggerHandler.bypass = true (Apex: data loads, tests)
 *   - the record already has isCoordsUpdated__c = true
 *   - no more background jobs can be queued in this transaction (e.g. inserted from async code)
 * Skipped records keep isCoordsUpdated__c = false, so the list view button (nothing ticked) or the
 * nightly run picks them up later.
 */
public without sharing class AccountLocationTriggerHandler {

    /** Set to true to suppress the automatic lookup in this transaction. */
    public static Boolean bypass = false;

    public static void afterInsert(List<ogg__Location__c> newList) {
        if (bypass || newList.isEmpty() || !GoogleMapsSettings.lookupOnCreate()) {
            return;
        }
        List<Id> ids = new List<Id>();
        for (ogg__Location__c rec : newList) {
            if (rec.isCoordsUpdated__c != true) {
                ids.add(rec.Id);
            }
        }
        if (ids.isEmpty()) {
            return;
        }
        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            System.debug(LoggingLevel.ERROR, 'Location lookup on create skipped (no background job slot left); '
                + 'the list view button or the nightly run will pick these up: ' + ids);
            return;
        }
        System.enqueueJob(new AccountLocationGeocodeQueueable(ids));
    }
}
