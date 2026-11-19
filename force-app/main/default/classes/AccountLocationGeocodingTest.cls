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
        // Tests below exercise the buttons / batch: keep the on-create trigger out of the way.
        // Trigger tests switch it back on explicitly.
        AccountLocationTriggerHandler.bypass = true;
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

    /** sourceId: the record the location belongs to (ogg__ObjectId__c / ogg__prefix__c are required). */
    private static ogg__Location__c newLocation(Id sourceId, Decimal lat, Decimal lng) {
        return (ogg__Location__c) TestRecordFactory.build(ogg__Location__c.SObjectType, new Map<String, Object>{
            'ogg__ObjectId__c' => String.valueOf(sourceId),
            'ogg__prefix__c' => String.valueOf(sourceId).left(3),
            GoogleMapsSettings.originalLatitudeField() => lat,
            GoogleMapsSettings.originalLongitudeField() => lng
        });
    }

    private static ogg__Location__c reload(Id recordId) {
        String soql = 'SELECT Id, Suggested_Latitude__c, Suggested_Longtitude__c, Different_Distance__c, isCoordsUpdated__c, '
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

    private static String expectFailure(Id recordId) {
        try {
            AccountLocationGeocodeAction.enqueue(recordId);
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        Assert.fail('Expected AuraHandledException');
        return null;
    }

    // ------------------------------------------------------------------ tests

    @IsTest
    static void buttonPopulatesSuggestedCoordinatesAndDistance() {
        configure(true);
        GoogleMapsCalloutMock mock = mockPreciseResult();
        Account acc = newAccount(THAI_ADDRESS);
        ogg__Location__c loc = newLocation(acc.Id, ORIGINAL_LAT, ORIGINAL_LNG);
        insert loc;

        Test.startTest();
        Id jobId = AccountLocationGeocodeAction.enqueue(loc.Id);
        Test.stopTest();

        ogg__Location__c rec = reload(loc.Id);
        Assert.areEqual(SUGGESTED_LAT, rec.Suggested_Latitude__c);
        Assert.areEqual(SUGGESTED_LNG, rec.Suggested_Longtitude__c);
        Assert.isNotNull(rec.Different_Distance__c, 'Distance should be calculated');
        Assert.areEqual(expectedDistance(rec), rec.Different_Distance__c);
        Assert.isTrue(rec.isCoordsUpdated__c, 'Processed records are flagged');
        Assert.areEqual(1, mock.requests.size(), 'Good first result -> single callout');
        Assert.areEqual(ThaiAddressNormalizer.prepare(THAI_ADDRESS).withoutUnit, mock.geocodeAddressParam(0),
            'Account address (without room / floor) must be sent to Google');

        Map<String, Object> status = AccountLocationGeocodeAction.getStatus(jobId, loc.Id);
        Assert.areEqual('Completed', status.get('status'));
        Assert.areEqual(SUGGESTED_LAT, status.get('suggestedLatitude'));
        Assert.areEqual(SUGGESTED_LNG, status.get('suggestedLongitude'));
        Assert.areEqual(rec.Different_Distance__c, status.get('distance'));
    }

    // ------------------------------------------------------------------ on-create trigger

    @IsTest
    static void insertTriggersLookup() {
        configure(true);
        AccountLocationTriggerHandler.bypass = false;
        GoogleMapsCalloutMock mock = mockPreciseResult();
        Account acc = newAccount(THAI_ADDRESS);

        Test.startTest();
        ogg__Location__c loc = newLocation(acc.Id, ORIGINAL_LAT, ORIGINAL_LNG);
        insert loc;
        Test.stopTest();

        ogg__Location__c rec = reload(loc.Id);
        Assert.areEqual(SUGGESTED_LAT, rec.Suggested_Latitude__c, 'New records are looked up automatically');
        Assert.areEqual(SUGGESTED_LNG, rec.Suggested_Longtitude__c);
        Assert.areEqual(expectedDistance(rec), rec.Different_Distance__c);
        Assert.isTrue(rec.isCoordsUpdated__c);
        Assert.areEqual(1, mock.requests.size());
    }

    @IsTest
    static void insertSkipsRecordsAlreadyFlagged() {
        configure(true);
        AccountLocationTriggerHandler.bypass = false;
        GoogleMapsCalloutMock mock = mockPreciseResult();
        Account acc = newAccount(THAI_ADDRESS);

        Test.startTest();
        ogg__Location__c loc = newLocation(acc.Id, ORIGINAL_LAT, ORIGINAL_LNG);
        loc.isCoordsUpdated__c = true;
        insert loc;
        Test.stopTest();

        Assert.isNull(reload(loc.Id).Suggested_Latitude__c);
        Assert.areEqual(0, mock.requests.size());
    }

    @IsTest
    static void disableLookupOnCreateSkipsTrigger() {
        insert new Google_Maps_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Enabled__c = true,
            API_Key__c = 'TEST_KEY',
            Disable_Lookup_On_Create__c = true);
        GoogleMapsSettings.cached = null;
        GoogleMapsCalloutMock mock = mockPreciseResult();
        Account acc = newAccount(THAI_ADDRESS);

        Test.startTest();
        ogg__Location__c loc = newLocation(acc.Id, ORIGINAL_LAT, ORIGINAL_LNG);
        insert loc;
        Test.stopTest();

        ogg__Location__c rec = reload(loc.Id);
        Assert.isNull(rec.Suggested_Latitude__c);
        Assert.isFalse(rec.isCoordsUpdated__c, 'Left for the list view button / nightly run');
        Assert.areEqual(0, mock.requests.size());
        Assert.isTrue(GoogleMapsSettings.isEnabled(), 'The buttons still work');
        Assert.isFalse(GoogleMapsSettings.lookupOnCreate());
    }

    @IsTest
    static void bulkInsertQueuesOneJob() {
        configure(true);   // Batch_Size__c = 30
        AccountLocationTriggerHandler.bypass = false;
        GoogleMapsCalloutMock mock = mockPreciseResult();
        Account acc = newAccount(THAI_ADDRESS);
        List<ogg__Location__c> locs = new List<ogg__Location__c>();
        for (Integer i = 0; i < 60; i++) {
            locs.add(newLocation(acc.Id, ORIGINAL_LAT, ORIGINAL_LNG));
        }

        Test.startTest();
        insert locs;
        Test.stopTest();

        Integer populated = [SELECT COUNT() FROM ogg__Location__c WHERE Id IN :locs AND isCoordsUpdated__c = true];
        // The other 30 are chained to a new job in real orgs; chaining is skipped in tests.
        Assert.areEqual(30, populated);
        Assert.areEqual(30, mock.requests.size());
    }

    @IsTest
    static void disabledSettingIsReportedToTheUser() {
        configure(false);
        GoogleMapsCalloutMock mock = mockPreciseResult();
        Account acc = newAccount(THAI_ADDRESS);
        ogg__Location__c loc = newLocation(acc.Id, ORIGINAL_LAT, ORIGINAL_LNG);
        insert loc;

        Test.startTest();
        String message = expectFailure(loc.Id);
        Test.stopTest();

        Assert.isTrue(message.contains('turned off'), message);
        Assert.isNull(reload(loc.Id).Suggested_Latitude__c);
        Assert.areEqual(0, mock.requests.size());
    }

    @IsTest
    static void wrongRecordTypeIsRejected() {
        configure(true);
        Account acc = newAccount(THAI_ADDRESS);
        Assert.isTrue(expectFailure(acc.Id).contains('oggLocation'));
        Assert.isTrue(expectFailure(null).contains('oggLocation'));
    }

    @IsTest
    static void blankAccountAddressIsSkipped() {
        configure(true);
        GoogleMapsCalloutMock mock = mockPreciseResult();
        Account acc = newAccount(null);
        ogg__Location__c loc = newLocation(acc.Id, ORIGINAL_LAT, ORIGINAL_LNG);
        insert loc;

        Test.startTest();
        Id jobId = AccountLocationGeocodeAction.enqueue(loc.Id);
        Test.stopTest();

        Assert.isNull(reload(loc.Id).Suggested_Latitude__c);
        Assert.isFalse(reload(loc.Id).isCoordsUpdated__c, 'Blank address: not flagged');
        Assert.areEqual(0, mock.requests.size());
        Assert.isNull(AccountLocationGeocodeAction.getStatus(jobId, loc.Id).get('suggestedLatitude'));
    }

    @IsTest
    static void googleErrorLeavesRecordUnchangedWithoutFailing() {
        configure(true);
        GoogleMapsCalloutMock mock = new GoogleMapsCalloutMock();
        mock.geocodeBody = GoogleMapsCalloutMock.geocodeError('OVER_QUERY_LIMIT', 'quota exceeded');
        Test.setMock(HttpCalloutMock.class, mock);
        Account acc = newAccount(THAI_ADDRESS);
        ogg__Location__c loc = newLocation(acc.Id, ORIGINAL_LAT, ORIGINAL_LNG);
        insert loc;

        Test.startTest();
        AccountLocationGeocodeAction.enqueue(loc.Id);
        Test.stopTest();

        ogg__Location__c rec = reload(loc.Id);
        Assert.isNull(rec.Suggested_Latitude__c);
        Assert.isFalse(rec.isCoordsUpdated__c, 'Not flagged when Google failed, so it is retried');
        Assert.areEqual(1, mock.requests.size());
    }

    @IsTest
    static void missingOriginalCoordinatesGiveNoDistance() {
        configure(true);
        mockPreciseResult();
        Account acc = newAccount(THAI_ADDRESS);
        ogg__Location__c loc = newLocation(acc.Id, null, null);
        insert loc;

        Test.startTest();
        AccountLocationGeocodeAction.enqueue(loc.Id);
        Test.stopTest();

        ogg__Location__c rec = reload(loc.Id);
        Assert.areEqual(SUGGESTED_LAT, rec.Suggested_Latitude__c);
        Assert.isNull(rec.Different_Distance__c, 'No distance without original coordinates');
    }

    @IsTest
    static void notLinkedToAnAccountIsSkipped() {
        configure(true);
        GoogleMapsCalloutMock mock = mockPreciseResult();
        // Linked to a non-Account record (here the running User): no Account address -> skipped.
        // ogg__RawAddress__c is deliberately NOT used as an address source.
        ogg__Location__c loc = newLocation(UserInfo.getUserId(), ORIGINAL_LAT, ORIGINAL_LNG);
        loc.ogg__RawAddress__c = THAI_ADDRESS;
        insert loc;

        Test.startTest();
        AccountLocationGeocodeAction.enqueue(loc.Id);
        Test.stopTest();

        ogg__Location__c rec = reload(loc.Id);
        Assert.isNull(rec.Suggested_Latitude__c);
        Assert.isFalse(rec.isCoordsUpdated__c);
        Assert.areEqual(0, mock.requests.size());
    }

    @IsTest
    static void billingAddressUsedWhenAddressFieldIsBlank() {
        configure(true);
        GoogleMapsCalloutMock mock = mockPreciseResult();
        // Address__c blank, Billing Address filled (State / Country left out: they may be picklists in the org)
        Account acc = (Account) TestRecordFactory.build(Account.SObjectType, new Map<String, Object>{
            'Name' => 'Geocode Test ' + Crypto.getRandomInteger(),
            'Address__c' => null,
            'BillingStreet' => '622 อาคารเอ็มโพเรียม ทาวเวอร์ ห้องเลขที่ 91,96 ชั้นที่ 9 ถนนสุขุมวิท แขวงคลองตัน',
            'BillingCity' => 'เขตคลองเตย',
            'BillingPostalCode' => '10110'
        });
        insert acc;
        ogg__Location__c loc = newLocation(acc.Id, ORIGINAL_LAT, ORIGINAL_LNG);
        insert loc;

        Test.startTest();
        AccountLocationGeocodeAction.enqueue(loc.Id);
        Test.stopTest();

        ogg__Location__c rec = reload(loc.Id);
        Assert.areEqual(SUGGESTED_LAT, rec.Suggested_Latitude__c, 'Billing Address is the backup');
        Assert.isTrue(rec.isCoordsUpdated__c);
        Assert.areEqual('622 อาคารเอ็มโพเรียม ทาวเวอร์ ถนนสุขุมวิท แขวงคลองตัน เขตคลองเตย 10110',
            mock.geocodeAddressParam(0), 'Billing Address sent to Google, without room / floor');
    }

    @IsTest
    static void addressSourceOrder() {
        Account acc = new Account(
            Id = '001000000000001',
            Address__c = '991 ถนนพระรามที่ 1 กรุงเทพมหานคร 10330',
            BillingStreet = '622 ถนนสุขุมวิท', BillingCity = 'เขตคลองเตย', BillingPostalCode = '10110');
        Map<Id, Account> accounts = new Map<Id, Account>{ acc.Id => acc };
        ogg__Location__c loc = new ogg__Location__c(ogg__ObjectId__c = acc.Id, ogg__RawAddress__c = 'raw address');

        Assert.areEqual(acc.Address__c, AccountLocationGeocodeProcessor.addressFor(loc, accounts), '1. Address__c');

        acc.Address__c = '  ';
        Assert.areEqual('622 ถนนสุขุมวิท เขตคลองเตย 10110',
            AccountLocationGeocodeProcessor.addressFor(loc, accounts), '2. Billing Address when Address__c is blank');

        acc.BillingStreet = null;
        acc.BillingCity = null;
        acc.BillingPostalCode = null;
        Assert.isNull(AccountLocationGeocodeProcessor.addressFor(loc, accounts), 'No address: skipped, raw address ignored');

        loc.ogg__ObjectId__c = UserInfo.getUserId();
        Assert.isNull(AccountLocationGeocodeProcessor.addressFor(loc, accounts), 'No Account: skipped');
    }

    @IsTest
    static void billingAddressFormat() {
        Account thai = new Account(BillingStreet = ' 99/1  หมู่ 3 ', BillingCity = 'อำเภอปากเกร็ด',
            BillingState = 'นนทบุรี', BillingPostalCode = '11120', BillingCountry = 'Thailand');
        Assert.areEqual('99/1 หมู่ 3 อำเภอปากเกร็ด นนทบุรี 11120', AccountLocationGeocodeProcessor.billingAddress(thai),
            'Thailand is left out');

        Account abroad = new Account(BillingStreet = '1 Raffles Place', BillingPostalCode = '048616', BillingCountry = 'Singapore');
        Assert.areEqual('1 Raffles Place 048616 Singapore', AccountLocationGeocodeProcessor.billingAddress(abroad));

        Assert.isNull(AccountLocationGeocodeProcessor.billingAddress(new Account(BillingCountry = 'Thailand')),
            'Country alone is not an address');
    }

    @IsTest
    static void objectIdOfAnotherObjectIsNotAnAccount() {
        Assert.isNull(AccountLocationGeocodeProcessor.toAccountId(UserInfo.getUserId()));
        Assert.isNull(AccountLocationGeocodeProcessor.toAccountId('not-an-id'));
        Assert.isNull(AccountLocationGeocodeProcessor.toAccountId(null));
    }

    @IsTest
    static void queueableProcessesOneBatchPerExecution() {
        configure(true);   // Batch_Size__c = 30
        GoogleMapsCalloutMock mock = mockPreciseResult();
        Account acc = newAccount(THAI_ADDRESS);

        List<ogg__Location__c> locs = new List<ogg__Location__c>();
        for (Integer i = 0; i < 60; i++) {
            locs.add(newLocation(acc.Id, ORIGINAL_LAT, ORIGINAL_LNG));
        }
        insert locs;
        List<Id> ids = new List<Id>(new Map<Id, ogg__Location__c>(locs).keySet());

        // The queueable processes one batch per execution and chains the rest (bulk runs use AccountLocationGeocodeBatch)
        Test.startTest();
        System.enqueueJob(new AccountLocationGeocodeQueueable(ids));
        Test.stopTest();

        Integer populated = 0;
        for (ogg__Location__c rec : [SELECT Suggested_Latitude__c FROM ogg__Location__c WHERE Id IN :locs]) {
            if (rec.Suggested_Latitude__c != null) {
                populated++;
            }
        }
        // Remaining 30 are chained to a new job in real orgs; chaining is skipped in tests.
        Assert.areEqual(30, populated);
        Assert.areEqual(30, mock.requests.size());
    }
}
