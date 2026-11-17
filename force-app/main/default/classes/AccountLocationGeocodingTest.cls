/**
 * End-to-end tests: AccountLocationTrigger -> AccountLocationTriggerHandler -> AccountLocationGeocodeQueueable.
 *
 * NOTE: if your org has extra required fields / validation rules on Account or AccountLocation__c,
 * add them in newAccount() / newLocation() below.
 */
@IsTest
private class AccountLocationGeocodingTest {

    // Original coordinates (what UPWARD stored) and the mocked Google Maps "suggested" coordinates.
    private static final Decimal ORIGINAL_LAT  = 13.7500000;
    private static final Decimal ORIGINAL_LNG  = 100.4913000;
    private static final Decimal SUGGESTED_LAT = 13.7462000;
    private static final Decimal SUGGESTED_LNG = 100.5347000;

    // ------------------------------------------------------------------ helpers

    private static void configure(Boolean enabled) {
        insert new Google_Maps_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Enabled__c = enabled,
            API_Key__c = 'TEST_KEY',
            Batch_Size__c = 40,
            Use_Places_Fallback__c = false);
        GoogleMapsSettings.cached = null;
    }

    private static GoogleMapsCalloutMock mockPreciseResult() {
        GoogleMapsCalloutMock mock = new GoogleMapsCalloutMock();
        mock.geocodeBody = GoogleMapsCalloutMock.geocodeOk(SUGGESTED_LAT, SUGGESTED_LNG, 'ROOFTOP', false);
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    private static Account newAccount(String address) {
        Account a = new Account(Name = 'Geocode Test ' + Crypto.getRandomInteger(), Address__c = address);
        insert a;
        return a;
    }

    private static AccountLocation__c newLocation(Id accountId, Decimal lat, Decimal lng) {
        AccountLocation__c loc = new AccountLocation__c(Account__c = accountId);
        loc.put(GoogleMapsSettings.originalLatitudeField(), lat);
        loc.put(GoogleMapsSettings.originalLongitudeField(), lng);
        return loc;
    }

    private static AccountLocation__c reload(Id recordId) {
        String soql = 'SELECT Id, Suggested_Latitude__c, Suggested_Longitude__c, Different_Distance__c, '
            + GoogleMapsSettings.originalLatitudeField() + ', ' + GoogleMapsSettings.originalLongitudeField()
            + ' FROM AccountLocation__c WHERE Id = :recordId';
        return Database.queryWithBinds(soql, new Map<String, Object>{ 'recordId' => recordId }, AccessLevel.SYSTEM_MODE)[0];
    }

    private static Decimal expectedDistance(AccountLocation__c rec) {
        return GeoDistanceUtil.distanceInMeters(
            GeoDistanceUtil.toDecimal(rec.get(GoogleMapsSettings.originalLatitudeField())),
            GeoDistanceUtil.toDecimal(rec.get(GoogleMapsSettings.originalLongitudeField())),
            rec.Suggested_Latitude__c, rec.Suggested_Longitude__c);
    }

    // ------------------------------------------------------------------ tests

    @IsTest
    static void insertPopulatesSuggestedCoordinatesAndDistance() {
        configure(true);
        GoogleMapsCalloutMock mock = mockPreciseResult();
        Account acc = newAccount('991 Rama I Rd, Pathum Wan, Bangkok 10330');

        Test.startTest();
        AccountLocation__c loc = newLocation(acc.Id, ORIGINAL_LAT, ORIGINAL_LNG);
        insert loc;
        Test.stopTest();

        AccountLocation__c rec = reload(loc.Id);
        Assert.areEqual(SUGGESTED_LAT, rec.Suggested_Latitude__c);
        Assert.areEqual(SUGGESTED_LNG, rec.Suggested_Longitude__c);
        Assert.isNotNull(rec.Different_Distance__c, 'Distance should be calculated');
        Assert.areEqual(expectedDistance(rec), rec.Different_Distance__c);
        Assert.isTrue(mock.requests[0].getEndpoint().contains('Rama+I+Rd'), 'Account address must be sent to Google');
    }

    @IsTest
    static void disabledSettingMakesNoCallout() {
        configure(false);
        GoogleMapsCalloutMock mock = mockPreciseResult();
        Account acc = newAccount('991 Rama I Rd, Bangkok');

        Test.startTest();
        AccountLocation__c loc = newLocation(acc.Id, ORIGINAL_LAT, ORIGINAL_LNG);
        insert loc;
        Test.stopTest();

        AccountLocation__c rec = reload(loc.Id);
        Assert.isNull(rec.Suggested_Latitude__c);
        Assert.isNull(rec.Suggested_Longitude__c);
        Assert.isNull(rec.Different_Distance__c);
        Assert.areEqual(0, mock.requests.size());
    }

    @IsTest
    static void blankAccountAddressIsSkipped() {
        configure(true);
        GoogleMapsCalloutMock mock = mockPreciseResult();
        Account acc = newAccount(null);

        Test.startTest();
        AccountLocation__c loc = newLocation(acc.Id, ORIGINAL_LAT, ORIGINAL_LNG);
        insert loc;
        Test.stopTest();

        Assert.isNull(reload(loc.Id).Suggested_Latitude__c);
        Assert.areEqual(0, mock.requests.size());
    }

    @IsTest
    static void googleErrorLeavesRecordUnchangedWithoutFailing() {
        configure(true);
        GoogleMapsCalloutMock mock = new GoogleMapsCalloutMock();
        mock.geocodeBody = GoogleMapsCalloutMock.geocodeError('OVER_QUERY_LIMIT', 'quota exceeded');
        Test.setMock(HttpCalloutMock.class, mock);
        Account acc = newAccount('991 Rama I Rd, Bangkok');

        Test.startTest();
        AccountLocation__c loc = newLocation(acc.Id, ORIGINAL_LAT, ORIGINAL_LNG);
        insert loc;
        Test.stopTest();

        Assert.isNull(reload(loc.Id).Suggested_Latitude__c);
        Assert.areEqual(1, mock.requests.size());
    }

    @IsTest
    static void missingOriginalCoordinatesThenLaterSetRecalculatesDistance() {
        configure(true);
        mockPreciseResult();
        Account acc = newAccount('991 Rama I Rd, Bangkok');

        Test.startTest();
        AccountLocation__c loc = newLocation(acc.Id, null, null);
        insert loc;
        Test.stopTest();

        AccountLocation__c rec = reload(loc.Id);
        Assert.areEqual(SUGGESTED_LAT, rec.Suggested_Latitude__c);
        Assert.isNull(rec.Different_Distance__c, 'No distance without original coordinates');

        // Simulate UPWARD filling the original coordinates afterwards
        rec.put(GoogleMapsSettings.originalLatitudeField(), ORIGINAL_LAT);
        rec.put(GoogleMapsSettings.originalLongitudeField(), ORIGINAL_LNG);
        update rec;

        AccountLocation__c after = reload(loc.Id);
        Assert.isNotNull(after.Different_Distance__c);
        Assert.areEqual(expectedDistance(after), after.Different_Distance__c);
    }

    @IsTest
    static void bypassFlagSkipsHandler() {
        configure(true);
        GoogleMapsCalloutMock mock = mockPreciseResult();
        Account acc = newAccount('991 Rama I Rd, Bangkok');

        Test.startTest();
        AccountLocationTriggerHandler.bypass = true;
        AccountLocation__c loc = newLocation(acc.Id, ORIGINAL_LAT, ORIGINAL_LNG);
        insert loc;
        AccountLocationTriggerHandler.bypass = false;
        Test.stopTest();

        Assert.isNull(reload(loc.Id).Suggested_Latitude__c);
        Assert.areEqual(0, mock.requests.size());
    }

    @IsTest
    static void bulkInsertProcessesOneBatchPerJob() {
        configure(true);   // Batch_Size__c = 40
        GoogleMapsCalloutMock mock = mockPreciseResult();
        Account acc = newAccount('991 Rama I Rd, Bangkok');

        List<AccountLocation__c> locs = new List<AccountLocation__c>();
        for (Integer i = 0; i < 60; i++) {
            locs.add(newLocation(acc.Id, ORIGINAL_LAT, ORIGINAL_LNG));
        }

        Test.startTest();
        insert locs;
        Test.stopTest();

        Integer populated = 0;
        for (AccountLocation__c rec : [SELECT Suggested_Latitude__c FROM AccountLocation__c WHERE Id IN :locs]) {
            if (rec.Suggested_Latitude__c != null) {
                populated++;
            }
        }
        // Remaining 20 are chained to a new job in real orgs; chaining is skipped in tests.
        Assert.areEqual(40, populated);
        Assert.areEqual(40, mock.requests.size());
    }
}
