/**
 * Async job started by the single-record button (AccountLocationGeocodeAction): geocodes the given
 * ogg__Location__c records with AccountLocationGeocodeProcessor. Processes GoogleMapsSettings.batchSize()
 * records per execution and chains itself for the rest. For large volumes use AccountLocationGeocodeBatch.
 */
public without sharing class AccountLocationGeocodeQueueable implements Queueable, Database.AllowsCallouts {

    private final List<Id> recordIds;

    public AccountLocationGeocodeQueueable(List<Id> recordIds) {
        this.recordIds = recordIds == null ? new List<Id>() : recordIds;
    }

    public void execute(QueueableContext ctx) {
        if (recordIds.isEmpty() || !GoogleMapsSettings.isEnabled()) {
            return;
        }

        Integer size = Math.min(GoogleMapsSettings.batchSize(), recordIds.size());
        List<Id> current   = new List<Id>();
        List<Id> remaining = new List<Id>();
        for (Integer i = 0; i < recordIds.size(); i++) {
            if (i < size) {
                current.add(recordIds[i]);
            } else {
                remaining.add(recordIds[i]);
            }
        }

        remaining.addAll(AccountLocationGeocodeProcessor.process(current));

        // Apex tests do not allow chaining queueables.
        if (!remaining.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(new AccountLocationGeocodeQueueable(remaining));
        }
    }
}
