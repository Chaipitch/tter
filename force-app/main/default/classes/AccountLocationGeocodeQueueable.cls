/**
 * Async job: for each ogg__Location__c, geocode ogg__Account__r.Address__c via Google Maps and store
 * Suggested_Latitude__c / Suggested_Longitude__c / Different_Distance__c.
 *
 * Processes GoogleMapsSettings.batchSize() records per execution and chains itself for the rest.
 * All callouts are made before the single DML statement (callouts after DML are not allowed).
 * Runs without sharing: this is a system process and must update records regardless of the inserting user.
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

        remaining.addAll(process(current));

        // Apex tests do not allow chaining queueables.
        if (!remaining.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(new AccountLocationGeocodeQueueable(remaining));
        }
    }

    /**
     * Geocodes and updates the given records.
     * @return Ids that could not be processed in this transaction (callout limit) and must be retried.
     */
    @TestVisible
    private List<Id> process(List<Id> ids) {
        List<Id> deferred = new List<Id>();
        String latField = GoogleMapsSettings.originalLatitudeField();
        String lngField = GoogleMapsSettings.originalLongitudeField();

        String soql = 'SELECT Id, ogg__Account__r.Address__c, ' + latField + ', ' + lngField
                    + ' FROM ogg__Location__c WHERE Id IN :ids';
        List<ogg__Location__c> records = Database.queryWithBinds(
            soql, new Map<String, Object>{ 'ids' => ids }, AccessLevel.SYSTEM_MODE);

        GoogleGeocodingService service = new GoogleGeocodingService();
        List<ogg__Location__c> updates = new List<ogg__Location__c>();

        for (ogg__Location__c rec : records) {
            // Each address can need up to MAX_CALLOUTS_PER_ADDRESS callouts; defer the rest to the next job.
            if (Limits.getCallouts() + GoogleGeocodingService.MAX_CALLOUTS_PER_ADDRESS > Limits.getLimitCallouts()) {
                deferred.add(rec.Id);
                continue;
            }
            String address = rec.ogg__Account__r == null ? null : rec.ogg__Account__r.Address__c;
            if (String.isBlank(address)) {
                continue;
            }
            try {
                GoogleGeocodingService.GeocodeResult result = service.findCoordinates(address);
                if (result == null) {
                    System.debug(LoggingLevel.WARN, 'No Google Maps result for AccountLocation ' + rec.Id
                        + ' address: ' + address);
                    continue;
                }
                Decimal suggestedLat = result.latitude.setScale(7, RoundingMode.HALF_UP);
                Decimal suggestedLng = result.longitude.setScale(7, RoundingMode.HALF_UP);
                // Only the fields this job owns are written; the original coordinates are never touched.
                // Distance is set here and also recalculated by the before-update trigger (same value),
                // so it stays correct even if the trigger handler is bypassed.
                updates.add(new ogg__Location__c(
                    Id = rec.Id,
                    Suggested_Latitude__c  = suggestedLat,
                    Suggested_Longitude__c = suggestedLng,
                    Different_Distance__c  = GeoDistanceUtil.distanceInMeters(
                        GeoDistanceUtil.toDecimal(rec.get(latField)),
                        GeoDistanceUtil.toDecimal(rec.get(lngField)),
                        suggestedLat,
                        suggestedLng)));
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Google Maps lookup failed for AccountLocation ' + rec.Id
                    + ': ' + e.getMessage());
            }
        }

        if (!updates.isEmpty()) {
            List<Database.SaveResult> results = Database.update(updates, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    System.debug(LoggingLevel.ERROR, 'Failed to update AccountLocation ' + updates[i].Id
                        + ': ' + results[i].getErrors());
                }
            }
        }
        return deferred;
    }
}
