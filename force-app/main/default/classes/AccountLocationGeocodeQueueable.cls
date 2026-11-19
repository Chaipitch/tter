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
