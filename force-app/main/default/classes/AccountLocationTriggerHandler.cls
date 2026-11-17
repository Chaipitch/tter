/**
 * Handler for AccountLocationTrigger.
 */
public without sharing class AccountLocationTriggerHandler {

    /** Set to true to suppress this handler (e.g. data loads). */
    public static Boolean bypass = false;

    /**
     * New AccountLocation__c records: queue the Google Maps lookup.
     * A single job is enqueued for the whole trigger batch; the job chains itself for large volumes.
     */
    public static void afterInsert(List<AccountLocation__c> newList) {
        if (bypass || !GoogleMapsSettings.isEnabled() || newList.isEmpty()) {
            return;
        }
        List<Id> ids = new List<Id>(new Map<Id, AccountLocation__c>(newList).keySet());

        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            // e.g. records inserted from an async context that already used its single enqueue slot
            System.debug(LoggingLevel.ERROR,
                'AccountLocation geocoding skipped (queueable limit reached) for Ids: ' + ids);
            return;
        }
        System.enqueueJob(new AccountLocationGeocodeQueueable(ids));
    }

    /**
     * Updated AccountLocation__c records: recalculate Different_Distance__c when the original
     * coordinates (e.g. set later by UPWARD) or the suggested coordinates (set by the queueable) change.
     */
    public static void beforeUpdate(List<AccountLocation__c> newList, Map<Id, AccountLocation__c> oldMap) {
        if (bypass || !GoogleMapsSettings.isEnabled()) {
            return;
        }
        String latField;
        String lngField;
        try {
            latField = GoogleMapsSettings.originalLatitudeField();
            lngField = GoogleMapsSettings.originalLongitudeField();
        } catch (GoogleMapsSettings.ConfigurationException e) {
            // Mis-configuration must never block saving AccountLocation records.
            System.debug(LoggingLevel.ERROR, e.getMessage());
            return;
        }

        for (AccountLocation__c rec : newList) {
            AccountLocation__c old = oldMap.get(rec.Id);
            Boolean changed =
                   rec.get(latField) != old.get(latField)
                || rec.get(lngField) != old.get(lngField)
                || rec.Suggested_Latitude__c  != old.Suggested_Latitude__c
                || rec.Suggested_Longitude__c != old.Suggested_Longitude__c;
            if (changed) {
                setDistance(rec, latField, lngField);
            }
        }
    }

    /** Populates Different_Distance__c from the record's original + suggested coordinates (null if either is missing). */
    public static void setDistance(AccountLocation__c rec, String latField, String lngField) {
        rec.Different_Distance__c = GeoDistanceUtil.distanceInMeters(
            GeoDistanceUtil.toDecimal(rec.get(latField)),
            GeoDistanceUtil.toDecimal(rec.get(lngField)),
            rec.Suggested_Latitude__c,
            rec.Suggested_Longitude__c);
    }
}
