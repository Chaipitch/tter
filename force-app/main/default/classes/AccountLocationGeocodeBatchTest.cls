/**
 * Bulk processing: AccountLocationGeocodeBatch (selected records / all not processed yet / scheduled)
 * and the list view button controller AccountLocationGeocodeListController.
 */
@IsTest
private class AccountLocationGeocodeBatchTest {

    private static final Decimal SUGGESTED_LAT = 13.7307000;
    private static final Decimal SUGGESTED_LNG = 100.5694000;
    private static final String THAI_ADDRESS =
        '622 อาคารเอ็มโพเรียม ทาวเวอร์ ห้องเลขที่ 91,96 ชั้นที่ 9 ถนนสุขุมวิท แขวงคลองตัน เขตคลองเตย กรุงเทพมหานคร 10110';

    private static void configure(Boolean enabled, String provider) {
        insert new Google_Maps_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Enabled__c = enabled,
            Provider__c = provider,
            API_Key__c = 'TEST_KEY',
            Batch_Size__c = 30);
        GoogleMapsSettings.cached = null;
        // Tests below exercise the buttons / batch: keep the on-create trigger out of the way.
        // Trigger tests switch it back on explicitly.
        AccountLocationTriggerHandler.bypass = true;
    }

    private static GoogleMapsCalloutMock mockGoogle() {
        GoogleMapsCalloutMock m = new GoogleMapsCalloutMock();
        m.geocodeBody = GoogleMapsCalloutMock.geocodeOk(SUGGESTED_LAT, SUGGESTED_LNG, 'ROOFTOP', false, '10110');
        Test.setMock(HttpCalloutMock.class, m);
        return m;
    }

    /** n locations for one Account; the first "processed" already have a suggestion and isCoordsUpdated__c = true. */
    private static List<ogg__Location__c> createLocations(Integer n, Integer processed) {
        Account acc = (Account) TestRecordFactory.build(Account.SObjectType, new Map<String, Object>{
            'Name' => 'Batch Test ' + Crypto.getRandomInteger(),
            'Address__c' => THAI_ADDRESS
        });
        insert acc;
        List<ogg__Location__c> locs = new List<ogg__Location__c>();
        for (Integer i = 0; i < n; i++) {
            ogg__Location__c loc = (ogg__Location__c) TestRecordFactory.build(ogg__Location__c.SObjectType,
                new Map<String, Object>{
                    'ogg__ObjectId__c' => String.valueOf(acc.Id),
                    'ogg__prefix__c' => String.valueOf(acc.Id).left(3),
                    'ogg__Latitude__c' => 13.7280,
                    'ogg__Longitude__c' => 100.5650
                });
            if (i < processed) {
                loc.Suggested_Latitude__c = 1;
                loc.Suggested_Longtitude__c = 1;
                loc.isCoordsUpdated__c = true;
            }
            locs.add(loc);
        }
        insert locs;
        return locs;
    }

    private static Integer countWithSuggestion(List<ogg__Location__c> locs, Decimal lat) {
        Integer n = 0;
        for (ogg__Location__c rec : [SELECT Suggested_Latitude__c FROM ogg__Location__c WHERE Id IN :locs]) {
            if (rec.Suggested_Latitude__c == lat) {
                n++;
            }
        }
        return n;
    }

    @IsTest
    static void selectedRecordsAreProcessedEvenIfAlreadyFlagged() {
        configure(true, null);
        mockGoogle();
        List<ogg__Location__c> locs = createLocations(5, 5);   // all 5 already processed (flag true)
        Set<Id> selected = new Set<Id>{ locs[0].Id, locs[1].Id };

        Test.startTest();
        AccountLocationGeocodeBatch.run(selected);
        Test.stopTest();

        Assert.areEqual(2, countWithSuggestion(locs, SUGGESTED_LAT), 'Only the selected records are re-checked');
    }

    @IsTest
    static void noSelectionProcessesAllRecordsWithoutASuggestion() {
        configure(true, null);
        GoogleMapsCalloutMock m = mockGoogle();
        List<ogg__Location__c> locs = createLocations(20, 5);  // 15 not processed yet

        Test.startTest();
        Id jobId = AccountLocationGeocodeBatch.run(null);
        Test.stopTest();

        Assert.isNotNull(jobId);
        Assert.areEqual(15, countWithSuggestion(locs, SUGGESTED_LAT));
        Assert.areEqual(15, m.requests.size(), 'Records with isCoordsUpdated__c = true are skipped');
        Assert.areEqual(20, [SELECT COUNT() FROM ogg__Location__c WHERE Id IN :locs AND isCoordsUpdated__c = true],
            'Processed records are flagged');
        Assert.isTrue(new AccountLocationGeocodeBatch().isAllMissing());
        Assert.isTrue(new AccountLocationGeocodeBatch(new Set<Id>()).isAllMissing());
    }

    @IsTest
    static void flagDecidesWhatAutomaticRunsPickUp() {
        configure(true, null);
        GoogleMapsCalloutMock m = mockGoogle();
        List<ogg__Location__c> locs = createLocations(2, 0);
        // [0]: flagged but no suggestion (e.g. cleared by hand) -> skipped
        // [1]: has an old suggestion but flag unticked          -> processed again
        locs[0].isCoordsUpdated__c = true;
        locs[1].Suggested_Latitude__c = 1;
        locs[1].Suggested_Longtitude__c = 1;
        update locs;

        Test.startTest();
        AccountLocationGeocodeBatch.run(null);
        Test.stopTest();

        Map<Id, ogg__Location__c> after = new Map<Id, ogg__Location__c>(
            [SELECT Suggested_Latitude__c, isCoordsUpdated__c FROM ogg__Location__c WHERE Id IN :locs]);
        Assert.isNull(after.get(locs[0].Id).Suggested_Latitude__c, 'Flagged record is skipped');
        Assert.areEqual(SUGGESTED_LAT, after.get(locs[1].Id).Suggested_Latitude__c, 'Unflagged record is processed');
        Assert.isTrue(after.get(locs[1].Id).isCoordsUpdated__c);
        Assert.areEqual(1, m.requests.size());
    }

    @IsTest
    static void disabledFeatureCannotStart() {
        configure(false, null);
        try {
            AccountLocationGeocodeBatch.run(null);
            Assert.fail('Expected BatchException');
        } catch (AccountLocationGeocodeBatch.BatchException e) {
            Assert.isTrue(e.getMessage().contains('turned off'), e.getMessage());
        }
    }

    @IsTest
    static void openStreetMapRunIsCapped() {
        configure(true, 'OpenStreetMap');
        GoogleMapsCalloutMock m = new GoogleMapsCalloutMock();
        Test.setMock(HttpCalloutMock.class, m);
        createLocations(12, 0);

        String osmQuery = new AccountLocationGeocodeBatch().start(null).getQuery();
        Assert.isTrue(osmQuery.contains('LIMIT 200'), osmQuery);
        Assert.areEqual(10, GoogleMapsSettings.batchSize(), 'OpenStreetMap: 10 per execute');
        Assert.areEqual(200, AccountLocationGeocodeBatch.OSM_MAX_RECORDS_PER_RUN);
    }

    @IsTest
    static void googleRunIsNotCapped() {
        configure(true, null);
        String googleQuery = new AccountLocationGeocodeBatch().start(null).getQuery();
        Assert.isFalse(googleQuery.containsIgnoreCase('LIMIT'), googleQuery);
    }

    @IsTest
    static void scheduledRunStartsTheBatch() {
        configure(true, null);
        mockGoogle();
        List<ogg__Location__c> locs = createLocations(3, 0);

        Test.startTest();
        // Only one executeBatch is allowed per test method, so the scheduled entry point is called directly.
        new AccountLocationGeocodeBatch().execute((SchedulableContext) null);
        Test.stopTest();

        Assert.areEqual(3, countWithSuggestion(locs, SUGGESTED_LAT));
    }

    // ------------------------------------------------------------------ list view button

    @IsTest
    static void listButtonWithSelectionStartsBatch() {
        configure(true, null);
        mockGoogle();
        List<ogg__Location__c> locs = createLocations(4, 0);

        ApexPages.StandardSetController setCon = new ApexPages.StandardSetController(locs);
        setCon.setSelected(new List<ogg__Location__c>{ locs[0], locs[1] });
        AccountLocationGeocodeListController ctrl = new AccountLocationGeocodeListController(setCon);
        Assert.areEqual(2, ctrl.selectedCount);
        Assert.isTrue(ctrl.enabled);
        Assert.isFalse(ctrl.openStreetMap);

        Test.startTest();
        ctrl.start();
        Test.stopTest();

        Assert.isTrue(ctrl.started);
        Assert.isNotNull(ctrl.jobId);
        Assert.areEqual(2, countWithSuggestion(locs, SUGGESTED_LAT));
        Assert.isTrue(ApexPages.hasMessages(ApexPages.Severity.CONFIRM));
    }

    @IsTest
    static void listButtonWithoutSelectionProcessesAllMissing() {
        configure(true, null);
        mockGoogle();
        List<ogg__Location__c> locs = createLocations(4, 1);

        AccountLocationGeocodeListController ctrl =
            new AccountLocationGeocodeListController(new ApexPages.StandardSetController(locs));
        Assert.areEqual(0, ctrl.selectedCount);

        Test.startTest();
        ctrl.start();
        Test.stopTest();

        Assert.areEqual(3, countWithSuggestion(locs, SUGGESTED_LAT));
        ctrl.back();   // returns to the list view in the UI
    }

    @IsTest
    static void listButtonShowsErrorWhenDisabled() {
        configure(false, null);
        AccountLocationGeocodeListController ctrl =
            new AccountLocationGeocodeListController(new ApexPages.StandardSetController(new List<ogg__Location__c>()));

        Assert.isFalse(ctrl.enabled);
        ctrl.start();
        Assert.isFalse(ctrl.started);
        Assert.isTrue(ApexPages.hasMessages(ApexPages.Severity.ERROR));
        Assert.areEqual(200, ctrl.openStreetMapLimit);
    }
}
