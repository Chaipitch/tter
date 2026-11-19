public with sharing class AccountLocationGeocodeAction {

    @AuraEnabled
    public static Id enqueue(Id recordId) {
        if (recordId == null || recordId.getSObjectType() != ogg__Location__c.SObjectType) {
            throw error('This action only works on an oggLocation record.');
        }
        if (!GoogleMapsSettings.isEnabled()) {
            throw error('Google Maps lookup is turned off. Ask your administrator to enable '
                + 'Google Maps Settings and add an API key.');
        }
        return System.enqueueJob(new AccountLocationGeocodeQueueable(new List<Id>{ recordId }));
    }

    @AuraEnabled
    public static Map<String, Object> getStatus(Id jobId, Id recordId) {
        List<AsyncApexJob> jobs = [
            SELECT Status, ExtendedStatus, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
            WITH SYSTEM_MODE
        ];
        List<ogg__Location__c> locs = [
            SELECT Suggested_Latitude__c, Suggested_Longtitude__c, Different_Distance__c
            FROM ogg__Location__c
            WHERE Id = :recordId
            WITH SYSTEM_MODE
        ];

        Map<String, Object> result = new Map<String, Object>{
            'status' => jobs.isEmpty() ? 'Unknown' : jobs[0].Status,
            'message' => jobs.isEmpty() ? null : jobs[0].ExtendedStatus
        };
        if (!locs.isEmpty()) {
            result.put('suggestedLatitude', locs[0].Suggested_Latitude__c);
            result.put('suggestedLongitude', locs[0].Suggested_Longtitude__c);
            result.put('distance', locs[0].Different_Distance__c);
        }
        return result;
    }

    /** AuraHandledException with a message that is also visible to Apex tests. */
    private static AuraHandledException error(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}
