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
