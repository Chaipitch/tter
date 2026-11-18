/**
 * Geocodes ogg__Location__c records and saves the result. Shared by the single-record button
 * (AccountLocationGeocodeQueueable) and bulk processing (AccountLocationGeocodeBatch).
 *
 * For each record: Account Id from ogg__ObjectId__c -> Account.Address__c (fallback ogg__RawAddress__c)
 * -> GoogleGeocodingService (Google or OpenStreetMap) -> Suggested_Latitude__c / Suggested_Longtitude__c /
 * Different_Distance__c, and isCoordsUpdated__c = true (only when coordinates were written; records with no
 * result or a blank address keep the flag false so they can be retried). All callouts first, then one
 * partial-success update.
 * Runs without sharing: a system process that must update records regardless of the running user.
 */
public without sharing class AccountLocationGeocodeProcessor {

    /**
     * Geocodes and updates the given records.
     * @return Ids that could not be processed in this transaction (callout limit) and must be retried.
     */
    public static List<Id> process(List<Id> ids) {
        List<Id> deferred = new List<Id>();
        String latField = GoogleMapsSettings.originalLatitudeField();
        String lngField = GoogleMapsSettings.originalLongitudeField();

        String soql = 'SELECT Id, ogg__ObjectId__c, ogg__RawAddress__c, ' + latField + ', ' + lngField
                    + ' FROM ogg__Location__c WHERE Id IN :ids';
        List<ogg__Location__c> records = Database.queryWithBinds(
            soql, new Map<String, Object>{ 'ids' => ids }, AccessLevel.SYSTEM_MODE);

        // ogg__Location__c has no lookup to Account: ogg__ObjectId__c holds the source record's Id.
        Set<Id> accountIds = new Set<Id>();
        for (ogg__Location__c rec : records) {
            Id accountId = toAccountId(rec.ogg__ObjectId__c);
            if (accountId != null) {
                accountIds.add(accountId);
            }
        }
        Map<Id, Account> accounts = new Map<Id, Account>(
            [SELECT Id, Address__c FROM Account WHERE Id IN :accountIds WITH SYSTEM_MODE]);

        GoogleGeocodingService service = new GoogleGeocodingService();
        List<ogg__Location__c> updates = new List<ogg__Location__c>();

        for (ogg__Location__c rec : records) {
            // Each address can need up to MAX_CALLOUTS_PER_ADDRESS callouts; defer the rest to the caller.
            if (Limits.getCallouts() + GoogleGeocodingService.MAX_CALLOUTS_PER_ADDRESS > Limits.getLimitCallouts()) {
                deferred.add(rec.Id);
                continue;
            }
            String address = addressFor(rec, accounts);
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
                // Distance is calculated from UPWARD's pin as it is right now.
                updates.add(new ogg__Location__c(
                    Id = rec.Id,
                    isCoordsUpdated__c     = true,   // processed: automatic runs skip it from now on
                    Suggested_Latitude__c  = suggestedLat,
                    Suggested_Longtitude__c = suggestedLng,
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

    /**
     * Account.Address__c of the Account in ogg__ObjectId__c. Falls back to the location's own
     * ogg__RawAddress__c when ogg__ObjectId__c is not an Account Id (or the Account is gone).
     */
    @TestVisible
    private static String addressFor(ogg__Location__c rec, Map<Id, Account> accounts) {
        Account acc = accounts.get(toAccountId(rec.ogg__ObjectId__c));
        if (acc != null) {
            return acc.Address__c;
        }
        return rec.ogg__RawAddress__c;
    }

    /** The value as an Account Id, or null if it is blank, not an Id, or the Id of another object. */
    @TestVisible
    private static Id toAccountId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            Id recordId = Id.valueOf(value.trim());
            return recordId.getSObjectType() == Account.SObjectType ? recordId : null;
        } catch (Exception e) {
            return null;
        }
    }
}
