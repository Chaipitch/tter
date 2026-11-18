@IsTest
private class OpenStreetMapGeocoderTest {

    private static final String EMPORIUM =
        '622 อาคารเอ็มโพเรียม ทาวเวอร์ ห้องเลขที่ 91,96 ชั้นที่ 9 ถนนสุขุมวิท แขวงคลองตัน เขตคลองเตย กรุงเทพมหานคร 10110';

    /** OpenStreetMap provider, no API key, settings in memory (no DML before the mocked callouts). */
    private static void configureOsm() {
        GoogleMapsSettings.cached = new Google_Maps_Settings__c(
            Enabled__c = true,
            Provider__c = 'OpenStreetMap',
            Country_Code__c = 'TH',
            Language__c = 'th',
            Batch_Size__c = 30,
            Use_Places_Fallback__c = true);
    }

    private static GoogleMapsCalloutMock mock() {
        GoogleMapsCalloutMock m = new GoogleMapsCalloutMock();
        Test.setMock(HttpCalloutMock.class, m);
        return m;
    }

    @IsTest
    static void providerSwitchAndLimits() {
        configureOsm();
        Assert.isTrue(GoogleMapsSettings.useOpenStreetMap());
        Assert.isTrue(GoogleMapsSettings.isEnabled(), 'OpenStreetMap needs no API key');
        Assert.areEqual(GoogleMapsSettings.OSM_MAX_BATCH_SIZE, GoogleMapsSettings.batchSize(),
            'Batch is capped for Nominatim (1 request / second)');

        GoogleMapsSettings.cached = new Google_Maps_Settings__c(Enabled__c = true, Provider__c = 'osm');
        Assert.isTrue(GoogleMapsSettings.useOpenStreetMap(), 'Case-insensitive short form');
        Assert.areEqual(GoogleMapsSettings.OSM_MAX_BATCH_SIZE, GoogleMapsSettings.batchSize());

        GoogleMapsSettings.cached = new Google_Maps_Settings__c(Enabled__c = true, Provider__c = 'Google');
        Assert.isFalse(GoogleMapsSettings.useOpenStreetMap());
        Assert.isFalse(GoogleMapsSettings.isEnabled(), 'Google still needs an API key');

        GoogleMapsSettings.cached = new Google_Maps_Settings__c(Enabled__c = true);
        Assert.isFalse(GoogleMapsSettings.useOpenStreetMap(), 'Blank provider = Google');
    }

    @IsTest
    static void preciseResultOnFirstQuery() {
        configureOsm();
        GoogleMapsCalloutMock m = mock();
        m.osmBodies.add(GoogleMapsCalloutMock.osmOk(13.7305, 100.5696, 30, '10110'));

        GoogleGeocodingService.GeocodeResult r = new GoogleGeocodingService().findCoordinates(EMPORIUM);

        Assert.areEqual(GoogleGeocodingService.SOURCE_OPENSTREETMAP, r.source);
        Assert.areEqual(13.7305, r.latitude);
        Assert.areEqual(100.5696, r.longitude);
        Assert.areEqual(true, r.postcodeMatch);
        Assert.areEqual(1, m.requests.size());

        HttpRequest req = m.requests[0];
        String url = req.getEndpoint();
        Assert.isTrue(url.startsWith('https://nominatim.openstreetmap.org/search?q='), url);
        Assert.isTrue(url.contains('format=jsonv2'), url);
        Assert.isTrue(url.contains('countrycodes=th'), url);
        Assert.isTrue(url.contains('accept-language=th'), url);
        Assert.isFalse(url.contains('key='), 'No API key is sent');
        Assert.isTrue(String.isNotBlank(req.getHeader('User-Agent')), 'Nominatim requires a User-Agent');
        Assert.areEqual(ThaiAddressNormalizer.prepare(EMPORIUM).withoutUnit,
            EncodingUtil.urlDecode(url.substringAfter('q=').substringBefore('&'), 'UTF-8'));
    }

    @IsTest
    static void areaResultTriesStreetLevelAndNeverCallsGoogle() {
        configureOsm();   // Use_Places_Fallback__c is on, but must be ignored for OpenStreetMap
        GoogleMapsCalloutMock m = mock();
        m.osmBodies.add(GoogleMapsCalloutMock.osmOk(13.72, 100.57, 16, '10110'));     // district level
        m.osmBodies.add(GoogleMapsCalloutMock.osmOk(13.7301, 100.5690, 26, '10110')); // street level

        GoogleGeocodingService.GeocodeResult r = new GoogleGeocodingService().findCoordinates(EMPORIUM);

        Assert.areEqual(13.7301, r.latitude);
        Assert.areEqual(ThaiAddressNormalizer.prepare(EMPORIUM).streetLevel, r.query);
        Assert.areEqual(2, m.requests.size());
        Assert.areEqual(0, m.countRequests('https://maps.googleapis.com'));
        Assert.areEqual(0, m.countRequests('https://places.googleapis.com'));
    }

    @IsTest
    static void onlyAreaResultsReturnsBestOne() {
        configureOsm();
        GoogleMapsCalloutMock m = mock();
        m.osmBodies.add(GoogleMapsCalloutMock.osmOk(13.72, 100.57, 16, '10110'));
        m.osmBodies.add(GoogleMapsCalloutMock.osmOk(13.80, 100.60, 16, null));

        GoogleGeocodingService.GeocodeResult r = new GoogleGeocodingService().findCoordinates(EMPORIUM);

        Assert.areEqual(13.72, r.latitude, 'Postcode match ranks above unknown postcode');
        Assert.isFalse(r.isPrecise());
    }

    @IsTest
    static void nothingFoundReturnsNull() {
        configureOsm();
        GoogleMapsCalloutMock m = mock();   // empty array for every request

        Assert.isNull(new GoogleGeocodingService().findCoordinates(EMPORIUM));
        Assert.areEqual(2, m.requests.size());
    }

    @IsTest
    static void httpErrorThrows() {
        configureOsm();
        GoogleMapsCalloutMock m = mock();
        m.osmStatusCode = 429;

        try {
            new GoogleGeocodingService().findCoordinates(EMPORIUM);
            Assert.fail('Expected GeocodingException');
        } catch (GoogleGeocodingService.GeocodingException e) {
            Assert.isTrue(e.getMessage().contains('429'), e.getMessage());
        }
    }

    @IsTest
    static void buttonWorksWithOpenStreetMap() {
        insert new Google_Maps_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Enabled__c = true,
            Provider__c = 'OpenStreetMap',
            Country_Code__c = 'TH');
        GoogleMapsSettings.cached = null;
        AccountLocationTriggerHandler.bypass = true;   // this test drives the record button
        GoogleMapsCalloutMock m = mock();
        m.osmBodies.add(GoogleMapsCalloutMock.osmOk(13.7305, 100.5696, 30, '10110'));

        Account acc = (Account) TestRecordFactory.build(Account.SObjectType, new Map<String, Object>{
            'Name' => 'OSM Test ' + Crypto.getRandomInteger(),
            'Address__c' => EMPORIUM
        });
        insert acc;
        ogg__Location__c loc = (ogg__Location__c) TestRecordFactory.build(ogg__Location__c.SObjectType,
            new Map<String, Object>{
                'ogg__ObjectId__c' => String.valueOf(acc.Id),
                'ogg__prefix__c' => String.valueOf(acc.Id).left(3),
                'ogg__Latitude__c' => 13.7280,
                'ogg__Longitude__c' => 100.5650
            });
        insert loc;

        Test.startTest();
        AccountLocationGeocodeAction.enqueue(loc.Id);
        Test.stopTest();

        ogg__Location__c rec = [
            SELECT Suggested_Latitude__c, Suggested_Longtitude__c, Different_Distance__c
            FROM ogg__Location__c WHERE Id = :loc.Id
        ];
        Assert.areEqual(13.7305000, rec.Suggested_Latitude__c);
        Assert.areEqual(100.5696000, rec.Suggested_Longtitude__c);
        Assert.isNotNull(rec.Different_Distance__c);
        Assert.areEqual(0, m.countRequests('https://maps.googleapis.com'));
    }
}
