public without sharing class AccountLocationGeocodeProcessor {

    /**
     * Geocodes and updates the given records.
     * @return Ids that could not be processed in this transaction (callout limit) and must be retried.
     */
    public static List<Id> process(List<Id> ids) {
        List<Id> deferred = new List<Id>();
        String latField = GoogleMapsSettings.originalLatitudeField();
        String lngField = GoogleMapsSettings.originalLongitudeField();

        String soql = 'SELECT Id, ogg__ObjectId__c, ' + latField + ', ' + lngField
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
            [SELECT Id, Address__c, BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry
             FROM Account WHERE Id IN :accountIds WITH SYSTEM_MODE]);

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
     * The address to look up, in this order:
     *   1. Account.Address__c of the Account in ogg__ObjectId__c
     *   2. that Account's Billing Address, when Address__c is blank
     * Null (record skipped) when there is no Account (ogg__ObjectId__c is not an Account Id, or the Account
     * is gone) or both addresses are blank.
     */
    @TestVisible
    private static String addressFor(ogg__Location__c rec, Map<Id, Account> accounts) {
        Account acc = accounts.get(toAccountId(rec.ogg__ObjectId__c));
        if (acc != null) {
            if (String.isNotBlank(acc.Address__c)) {
                return acc.Address__c;
            }
            return billingAddress(acc);
        }
        return null;
    }

    /**
     * Billing Address as one line: street, city, state, postcode, and the country unless it is Thailand
     * (the lookup is already set up for Thailand). Null when all parts are blank.
     */
    @TestVisible
    private static String billingAddress(Account acc) {
        List<String> parts = new List<String>();
        for (String part : new List<String>{
                acc.BillingStreet, acc.BillingCity, acc.BillingState, acc.BillingPostalCode }) {
            if (String.isNotBlank(part)) {
                parts.add(part.normalizeSpace());
            }
        }
        if (parts.isEmpty()) {
            return null;
        }
        String country = acc.BillingCountry == null ? '' : acc.BillingCountry.trim();
        if (String.isNotBlank(country)
                && !country.equalsIgnoreCase('Thailand') && !country.equalsIgnoreCase('TH')
                && country != 'ไทย' && country != 'ประเทศไทย') {
            parts.add(country);
        }
        return String.join(parts, ' ');
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
