@IsTest
private class GoogleGeocodingServiceTest {

    private static final String EMPORIUM =
        '622 อาคารเอ็มโพเรียม ทาวเวอร์ ห้องเลขที่ 91,96 ชั้นที่ 9 ถนนสุขุมวิท แขวงคลองตัน เขตคลองเตย กรุงเทพมหานคร 10110';
    private static final String EMPORIUM_WITHOUT_UNIT =
        '622 อาคารเอ็มโพเรียม ทาวเวอร์ ถนนสุขุมวิท แขวงคลองตัน เขตคลองเตย กรุงเทพมหานคร 10110';
    private static final String EMPORIUM_STREET_LEVEL =
        '622 ถนนสุขุมวิท แขวงคลองตัน เขตคลองเตย กรุงเทพมหานคร 10110';

    private static void configure(Boolean placesFallback) {
        insert new Google_Maps_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Enabled__c = true,
            API_Key__c = 'TEST_KEY',
            Country_Code__c = 'TH',
            Region__c = 'th',
            Language__c = 'th',
            Use_Places_Fallback__c = placesFallback);
        GoogleMapsSettings.cached = null;
    }

    private static GoogleMapsCalloutMock mock() {
        GoogleMapsCalloutMock m = new GoogleMapsCalloutMock();
        Test.setMock(HttpCalloutMock.class, m);
        return m;
    }

    @IsTest
    static void firstQueryDropsRoomAndFloorAndStopsWhenGood() {
        configure(true);
        GoogleMapsCalloutMock m = mock();
        m.geocodeBodies.add(GoogleMapsCalloutMock.geocodeOk(13.7307, 100.5694, 'ROOFTOP', false, '10110'));

        Test.startTest();
        GoogleGeocodingService.GeocodeResult r = new GoogleGeocodingService().findCoordinates(EMPORIUM);
        Test.stopTest();

        Assert.areEqual(13.7307, r.latitude);
        Assert.areEqual(100.5694, r.longitude);
        Assert.areEqual(GoogleGeocodingService.SOURCE_GEOCODING, r.source);
        Assert.areEqual(true, r.postcodeMatch);
        Assert.areEqual(1, m.requests.size(), 'Good first result -> no further callouts');
        Assert.areEqual(EMPORIUM_WITHOUT_UNIT, m.geocodeAddressParam(0));

        String url = m.requests[0].getEndpoint();
        Assert.isTrue(url.contains('components=country%3ATH'), url);
        Assert.isTrue(url.contains('region=th'), url);
        Assert.isTrue(url.contains('language=th'), url);
        Assert.isTrue(url.contains('key=TEST_KEY'), url);
    }

    @IsTest
    static void partialMatchTriesStreetLevelQuery() {
        configure(true);
        GoogleMapsCalloutMock m = mock();
        m.geocodeBodies.add(GoogleMapsCalloutMock.geocodeOk(13.72, 100.55, 'GEOMETRIC_CENTER', true, '10110'));
        m.geocodeBodies.add(GoogleMapsCalloutMock.geocodeOk(13.7307, 100.5694, 'ROOFTOP', false, '10110'));

        GoogleGeocodingService.GeocodeResult r = new GoogleGeocodingService().findCoordinates(EMPORIUM);

        Assert.areEqual(13.7307, r.latitude);
        Assert.areEqual(EMPORIUM_STREET_LEVEL, r.query);
        Assert.areEqual(EMPORIUM_STREET_LEVEL, m.geocodeAddressParam(1));
        Assert.areEqual(0, m.countRequests('https://places.googleapis.com'));
    }

    @IsTest
    static void postcodeMismatchFallsBackToPlaces() {
        configure(true);
        GoogleMapsCalloutMock m = mock();
        // Geocoding finds a precise point, but in another postcode area -> not trusted
        m.geocodeBodies.add(GoogleMapsCalloutMock.geocodeOk(13.80, 100.60, 'ROOFTOP', false, '10240'));
        m.geocodeBodies.add(GoogleMapsCalloutMock.geocodeOk(13.80, 100.60, 'ROOFTOP', false, '10240'));
        m.placesBody = GoogleMapsCalloutMock.placesOk(13.7307, 100.5694, '10110');

        GoogleGeocodingService.GeocodeResult r = new GoogleGeocodingService().findCoordinates(EMPORIUM);

        Assert.areEqual(GoogleGeocodingService.SOURCE_PLACES, r.source);
        Assert.areEqual(13.7307, r.latitude);
        Assert.areEqual(3, m.requests.size(), 'Never more than MAX_CALLOUTS_PER_ADDRESS');

        HttpRequest placesReq = m.requests[2];
        Assert.areEqual('POST', placesReq.getMethod());
        Assert.areEqual('TEST_KEY', placesReq.getHeader('X-Goog-Api-Key'));
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(placesReq.getBody());
        Assert.areEqual(EMPORIUM_WITHOUT_UNIT, body.get('textQuery'), 'Places search keeps the building name');
        Assert.areEqual('th', body.get('languageCode'));
    }

    @IsTest
    static void noGoodResultReturnsBestScored() {
        configure(false);
        GoogleMapsCalloutMock m = mock();
        // 1st: precise but wrong postcode (score 1); 2nd: partial but right postcode (score 4)
        m.geocodeBodies.add(GoogleMapsCalloutMock.geocodeOk(13.80, 100.60, 'ROOFTOP', false, '10240'));
        m.geocodeBodies.add(GoogleMapsCalloutMock.geocodeOk(13.73, 100.57, 'GEOMETRIC_CENTER', true, '10110'));

        GoogleGeocodingService.GeocodeResult r = new GoogleGeocodingService().findCoordinates(EMPORIUM);

        Assert.areEqual(13.73, r.latitude);
        Assert.areEqual(true, r.postcodeMatch);
        Assert.areEqual(0, m.countRequests('https://places.googleapis.com'), 'Fallback disabled');
    }

    @IsTest
    static void addressWithoutPostcodeAcceptsPreciseResult() {
        configure(true);
        GoogleMapsCalloutMock m = mock();
        m.geocodeBodies.add(GoogleMapsCalloutMock.geocodeOk(13.75, 100.49, 'ROOFTOP', false, '10200'));

        GoogleGeocodingService.GeocodeResult r =
            new GoogleGeocodingService().findCoordinates('พระบรมมหาราชวัง ถนนหน้าพระลาน กรุงเทพมหานคร');

        Assert.isNull(r.postcodeMatch);
        Assert.isTrue(r.isGood());
        Assert.areEqual(1, m.requests.size());
    }

    @IsTest
    static void placesFailureKeepsGeocodeResult() {
        configure(true);
        GoogleMapsCalloutMock m = mock();
        m.geocodeBody = GoogleMapsCalloutMock.geocodeOk(13.72, 100.55, 'APPROXIMATE', true, '10110');
        m.placesStatusCode = 403;
        m.placesBody = '{"error":{"code":403,"message":"API not enabled"}}';

        GoogleGeocodingService.GeocodeResult r = new GoogleGeocodingService().findCoordinates(EMPORIUM);

        Assert.areEqual(GoogleGeocodingService.SOURCE_GEOCODING, r.source);
        Assert.areEqual(13.72, r.latitude);
    }

    @IsTest
    static void nothingFoundReturnsNull() {
        configure(true);
        GoogleMapsCalloutMock m = mock();
        m.geocodeBody = GoogleMapsCalloutMock.zeroResults();
        m.placesBody  = '{}';

        Assert.isNull(new GoogleGeocodingService().findCoordinates(EMPORIUM));
        Assert.areEqual(3, m.requests.size());
    }

    @IsTest
    static void apiErrorStatusThrows() {
        configure(false);
        GoogleMapsCalloutMock m = mock();
        m.geocodeBody = GoogleMapsCalloutMock.geocodeError('REQUEST_DENIED', 'The provided API key is invalid.');

        try {
            new GoogleGeocodingService().findCoordinates(EMPORIUM);
            Assert.fail('Expected GeocodingException');
        } catch (GoogleGeocodingService.GeocodingException e) {
            Assert.isTrue(e.getMessage().contains('REQUEST_DENIED'), e.getMessage());
        }
    }

    @IsTest
    static void httpErrorThrows() {
        configure(false);
        GoogleMapsCalloutMock m = mock();
        m.geocodeStatusCode = 500;
        m.geocodeBody = 'Server error';

        try {
            new GoogleGeocodingService().findCoordinates(EMPORIUM);
            Assert.fail('Expected GeocodingException');
        } catch (GoogleGeocodingService.GeocodingException e) {
            Assert.isTrue(e.getMessage().contains('500'), e.getMessage());
        }
    }

    @IsTest
    static void blankAddressMakesNoCallout() {
        configure(true);
        GoogleMapsCalloutMock m = mock();

        Assert.isNull(new GoogleGeocodingService().findCoordinates('   '));
        Assert.isNull(new GoogleGeocodingService().findCoordinates(null));
        Assert.areEqual(0, m.requests.size());
    }

    @IsTest
    static void settingsDefaultsAndValidation() {
        GoogleMapsSettings.cached = null;
        Assert.isFalse(GoogleMapsSettings.isEnabled(), 'Disabled when no org default exists');
        Assert.areEqual(GoogleMapsSettings.DEFAULT_BATCH_SIZE, GoogleMapsSettings.batchSize());
        Assert.areEqual(GoogleMapsSettings.DEFAULT_TIMEOUT_MS, GoogleMapsSettings.timeoutMs());
        Assert.isNull(GoogleMapsSettings.countryCode());

        GoogleMapsSettings.cached = new Google_Maps_Settings__c(
            Batch_Size__c = 500, Timeout_Ms__c = 999999, Original_Latitude_Field__c = 'Does_Not_Exist__c');
        Assert.areEqual(GoogleMapsSettings.MAX_BATCH_SIZE, GoogleMapsSettings.batchSize());
        Assert.areEqual(GoogleMapsSettings.MAX_TIMEOUT_MS, GoogleMapsSettings.timeoutMs());
        try {
            GoogleMapsSettings.originalLatitudeField();
            Assert.fail('Expected ConfigurationException');
        } catch (GoogleMapsSettings.ConfigurationException e) {
            Assert.isTrue(e.getMessage().contains('Does_Not_Exist__c'));
        }

        // Account lookup: auto-detected when blank, validated when configured
        GoogleMapsSettings.cached = new Google_Maps_Settings__c();
        String lookup = GoogleMapsSettings.accountLookupField();
        Assert.isNotNull(lookup);
        Assert.isNotNull(GoogleMapsSettings.accountRelationshipName());

        GoogleMapsSettings.cached = new Google_Maps_Settings__c(Account_Lookup_Field__c = 'Does_Not_Exist__c');
        try {
            GoogleMapsSettings.accountLookupField();
            Assert.fail('Expected ConfigurationException');
        } catch (GoogleMapsSettings.ConfigurationException e) {
            Assert.isTrue(e.getMessage().contains('is not a lookup to Account'));
        }
    }
}
