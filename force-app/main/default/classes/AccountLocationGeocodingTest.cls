/**
 * End-to-end tests: AccountLocationTrigger -> AccountLocationTriggerHandler -> AccountLocationGeocodeQueueable.
 *
 * Required fields on Account / ogg__Location__c are filled by TestRecordFactory. If a validation rule
 * needs a specific value, add it to the values map in newAccount() / newLocation().
 *
 * UPWARD may create its own ogg__Location__c when a test inserts an Account with an address; those
 * records are also geocoded (against the same mock), so assertions check our record rather than
 * exact callout counts where that matters.
 */
@IsTest
private class AccountLocationGeocodingTest {

    // Original coordinates (what UPWARD stored) and the mocked Google Maps "suggested" coordinates.
    private static final Decimal ORIGINAL_LAT  = 13.7280000;
    private static final Decimal ORIGINAL_LNG  = 100.5650000;
    private static final Decimal SUGGESTED_LAT = 13.7307000;
    private static final Decimal SUGGESTED_LNG = 100.5694000;

    private static final String THAI_ADDRESS =
        '622 อาคารเอ็มโพเรียม ทาวเวอร์ ห้องเลขที่ 91,96 ชั้นที่ 9 ถนนสุขุมวิท แขวงคลองตัน เขตคลองเตย กรุงเทพมหานคร 10110';

    // ------------------------------------------------------------------ helpers

    private static void configure(Boolean enabled) {
        insert new Google_Maps_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Enabled__c = enabled,
            API_Key__c = 'TEST_KEY',
            Batch_Size__c = 30,
            Use_Places_Fallback__c = false);
        GoogleMapsSettings.cached = null;
    }

    private static GoogleMapsCalloutMock mockPreciseResult() {
        GoogleMapsCalloutMock mock = new GoogleMapsCalloutMock();
        mock.geocodeBody = GoogleMapsCalloutMock.geocodeOk(SUGGESTED_LAT, SUGGESTED_LNG, 'ROOFTOP', false, '10110');
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    private static Account newAccount(String address) {
        Account a = (Account) TestRecordFactory.build(Account.SObjectType, new Map<String, Object>{
            'Name' => 'Geocode Test ' + Crypto.getRandomInteger(),
            'Address__c' => address
        });
        insert a;
        return a;
    }

    private static ogg__Location__c newLocation(Id accountId, Decimal lat, Decimal lng) {
        return (ogg__Location__c) TestRecordFactory.build(ogg__Location__c.SObjectType, new Map<String, Object>{
            'ogg__ObjectId__c' => accountId == null ? null : String.valueOf(accountId),
            'ogg__prefix__c' => accountId == null ? null : String.valueOf(accountId).left(3),
            GoogleMapsSettings.originalLatitudeField() => lat,
            GoogleMapsSettings.originalLongitudeField() => lng
        });
    }

    private static ogg__Location__c reload(Id recordId) {
        String soql = 'SELECT Id, Suggested_Latitude__c, Suggested_Longtitude__c, Different_Distance__c, '
            + GoogleMapsSettings.originalLatitudeField() + ', ' + GoogleMapsSettings.originalLongitudeField()
            + ' FROM ogg__Location__c WHERE Id = :recordId';
        return (ogg__Location__c) Database.queryWithBinds(
            soql, new Map<String, Object>{ 'recordId' => recordId }, AccessLevel.SYSTEM_MODE)[0];
    }

    private static Decimal expectedDistance(ogg__Location__c rec) {
        return GeoDistanceUtil.distanceInMeters(
            GeoDistanceUtil.toDecimal(rec.get(GoogleMapsSettings.originalLatitudeField())),
            GeoDistanceUtil.toDecimal(rec.get(GoogleMapsSettings.originalLongitudeField())),
            rec.Suggested_Latitude__c, rec.Suggested_Longtitude__c);
    }

    // ------------------------------------------------------------------ tests

    @IsTest
    static void insertPopulatesSuggestedCoordinatesAndDistance() {
        configure(true);
        GoogleMapsCalloutMock mock = mockPreciseResult();
        Account acc = newAccount(THAI_ADDRESS);

        Test.startTest();
        ogg__Location__c loc = newLocation(acc.Id, ORIGINAL_LAT, ORIGINAL_LNG);
        insert loc;
        Test.stopTest();

        ogg__Location__c rec = reload(loc.Id);
        Assert.areEqual(SUGGESTED_LAT, rec.Suggested_Latitude__c);
        Assert.areEqual(SUGGESTED_LNG, rec.Suggested_Longtitude__c);
        Assert.isNotNull(rec.Different_Distance__c, 'Distance should be calculated');
        Assert.areEqual(expectedDistance(rec), rec.Different_Distance__c);
        Assert.areEqual(ThaiAddressNormalizer.prepare(THAI_ADDRESS).withoutUnit, mock.geocodeAddressParam(0),
            'Account address (without room / floor) must be sent to Google');
    }

    @IsTest
    static void disabledSettingMakesNoCallout() {
        configure(false);
        GoogleMapsCalloutMock mock = mockPreciseResult();
        Account acc = newAccount(THAI_ADDRESS);

        Test.startTest();
        ogg__Location__c loc = newLocation(acc.Id, ORIGINAL_LAT, ORIGINAL_LNG);
        insert loc;
        Test.stopTest();

        ogg__Location__c rec = reload(loc.Id);
        Assert.isNull(rec.Suggested_Latitude__c);
        Assert.isNull(rec.Suggested_Longtitude__c);
        Assert.isNull(rec.Different_Distance__c);
        Assert.areEqual(0, mock.requests.size());
    }

    @IsTest
    static void blankAccountAddressIsSkipped() {
        configure(true);
        GoogleMapsCalloutMock mock = mockPreciseResult();
        Account acc = newAccount(null);

        Test.startTest();
        ogg__Location__c loc = newLocation(acc.Id, ORIGINAL_LAT, ORIGINAL_LNG);
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
        Account acc = newAccount(THAI_ADDRESS);

        Test.startTest();
        ogg__Location__c loc = newLocation(acc.Id, ORIGINAL_LAT, ORIGINAL_LNG);
        insert loc;
        Test.stopTest();

        Assert.isNull(reload(loc.Id).Suggested_Latitude__c);
        Assert.isFalse(mock.requests.isEmpty(), 'Google was called');
    }

    @IsTest
    static void missingOriginalCoordinatesThenLaterSetRecalculatesDistance() {
        configure(true);
        mockPreciseResult();
        Account acc = newAccount(THAI_ADDRESS);

        Test.startTest();
        ogg__Location__c loc = newLocation(acc.Id, null, null);
        insert loc;
        Test.stopTest();

        ogg__Location__c rec = reload(loc.Id);
        Assert.areEqual(SUGGESTED_LAT, rec.Suggested_Latitude__c);
        Assert.isNull(rec.Different_Distance__c, 'No distance without original coordinates');

        // Simulate UPWARD filling the original coordinates afterwards
        rec.put(GoogleMapsSettings.originalLatitudeField(), ORIGINAL_LAT);
        rec.put(GoogleMapsSettings.originalLongitudeField(), ORIGINAL_LNG);
        update rec;

        ogg__Location__c after = reload(loc.Id);
        Assert.isNotNull(after.Different_Distance__c);
        Assert.areEqual(expectedDistance(after), after.Different_Distance__c);
    }

    @IsTest
    static void bypassFlagSkipsHandler() {
        configure(true);
        GoogleMapsCalloutMock mock = mockPreciseResult();
        Account acc = newAccount(THAI_ADDRESS);

        Test.startTest();
        AccountLocationTriggerHandler.bypass = true;
        ogg__Location__c loc = newLocation(acc.Id, ORIGINAL_LAT, ORIGINAL_LNG);
        insert loc;
        AccountLocationTriggerHandler.bypass = false;
        Test.stopTest();

        Assert.isNull(reload(loc.Id).Suggested_Latitude__c);
    }

    @IsTest
    static void rawAddressUsedWhenNotLinkedToAccount() {
        configure(true);
        mockPreciseResult();

        Test.startTest();
        ogg__Location__c loc = newLocation(null, ORIGINAL_LAT, ORIGINAL_LNG);
        loc.ogg__RawAddress__c = THAI_ADDRESS;
        insert loc;
        Test.stopTest();

        Assert.areEqual(SUGGESTED_LAT, reload(loc.Id).Suggested_Latitude__c);
    }

    @IsTest
    static void objectIdOfAnotherObjectIsNotAnAccount() {
        Assert.isNull(AccountLocationGeocodeQueueable.toAccountId(UserInfo.getUserId()));
        Assert.isNull(AccountLocationGeocodeQueueable.toAccountId('not-an-id'));
        Assert.isNull(AccountLocationGeocodeQueueable.toAccountId(null));
    }

    @IsTest
    static void bulkInsertProcessesOneBatchPerJob() {
        configure(true);   // Batch_Size__c = 30
        GoogleMapsCalloutMock mock = mockPreciseResult();
        Account acc = newAccount(THAI_ADDRESS);

        List<ogg__Location__c> locs = new List<ogg__Location__c>();
        for (Integer i = 0; i < 60; i++) {
            locs.add(newLocation(acc.Id, ORIGINAL_LAT, ORIGINAL_LNG));
        }

        Test.startTest();
        insert locs;
        Test.stopTest();

        Integer populated = 0;
        for (ogg__Location__c rec : [SELECT Suggested_Latitude__c FROM ogg__Location__c WHERE Id IN :locs]) {
            if (rec.Suggested_Latitude__c != null) {
                populated++;
            }
        }
        // Remaining 30 are chained to a new job in real orgs; chaining is skipped in tests.
        Assert.areEqual(30, populated);
        Assert.isTrue(mock.requests.size() >= 30);
    }
}
