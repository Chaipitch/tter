@IsTest
private class GoogleGeocodingServiceTest {

    private static void configure(Boolean placesFallback) {
        insert new Google_Maps_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Enabled__c = true,
            API_Key__c = 'TEST_KEY',
            Region__c = 'th',
            Language__c = 'en',
            Use_Places_Fallback__c = placesFallback);
        GoogleMapsSettings.cached = null;
    }

    @IsTest
    static void preciseGeocodeResultIsReturned() {
        configure(true);
        GoogleMapsCalloutMock mock = new GoogleMapsCalloutMock();
        mock.geocodeBody = GoogleMapsCalloutMock.geocodeOk(13.7462, 100.5347, 'ROOFTOP', false);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        GoogleGeocodingService.GeocodeResult r = new GoogleGeocodingService().findCoordinates('991 Rama I Rd, Bangkok');
        Test.stopTest();

        Assert.areEqual(13.7462, r.latitude);
        Assert.areEqual(100.5347, r.longitude);
        Assert.areEqual(GoogleGeocodingService.SOURCE_GEOCODING, r.source);
        Assert.areEqual(0, mock.countRequests('https://places.googleapis.com'), 'Fallback must not be called');

        String url = mock.requests[0].getEndpoint();
        Assert.isTrue(url.contains('address=991+Rama+I+Rd%2C+Bangkok'), url);
        Assert.isTrue(url.contains('key=TEST_KEY'), url);
        Assert.isTrue(url.contains('region=th'), url);
        Assert.isTrue(url.contains('language=en'), url);
    }

    @IsTest
    static void zeroResultsFallsBackToPlaces() {
        configure(true);
        GoogleMapsCalloutMock mock = new GoogleMapsCalloutMock();
        mock.geocodeBody = GoogleMapsCalloutMock.zeroResults();
        mock.placesBody  = GoogleMapsCalloutMock.placesOk(13.7, 100.5);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        GoogleGeocodingService.GeocodeResult r = new GoogleGeocodingService().findCoordinates('Some shop name Bangkok');
        Test.stopTest();

        Assert.areEqual(GoogleGeocodingService.SOURCE_PLACES, r.source);
        Assert.areEqual(13.7, r.latitude);
        HttpRequest placesReq = mock.requests[1];
        Assert.areEqual('POST', placesReq.getMethod());
        Assert.areEqual('TEST_KEY', placesReq.getHeader('X-Goog-Api-Key'));
        Assert.isTrue(placesReq.getBody().contains('"textQuery":"Some shop name Bangkok"'));
    }

    @IsTest
    static void partialMatchPrefersPlacesResult() {
        configure(true);
        GoogleMapsCalloutMock mock = new GoogleMapsCalloutMock();
        mock.geocodeBody = GoogleMapsCalloutMock.geocodeOk(13.0, 100.0, 'APPROXIMATE', true);
        mock.placesBody  = GoogleMapsCalloutMock.placesOk(13.7, 100.5);
        Test.setMock(HttpCalloutMock.class, mock);

        GoogleGeocodingService.GeocodeResult r = new GoogleGeocodingService().findCoordinates('addr');
        Assert.areEqual(GoogleGeocodingService.SOURCE_PLACES, r.source);
    }

    @IsTest
    static void placesFailureKeepsGeocodeResult() {
        configure(true);
        GoogleMapsCalloutMock mock = new GoogleMapsCalloutMock();
        mock.geocodeBody = GoogleMapsCalloutMock.geocodeOk(13.0, 100.0, 'APPROXIMATE', true);
        mock.placesStatusCode = 403;
        mock.placesBody = '{"error":{"code":403,"message":"API not enabled"}}';
        Test.setMock(HttpCalloutMock.class, mock);

        GoogleGeocodingService.GeocodeResult r = new GoogleGeocodingService().findCoordinates('addr');
        Assert.areEqual(GoogleGeocodingService.SOURCE_GEOCODING, r.source);
        Assert.areEqual(13.0, r.latitude);
    }

    @IsTest
    static void noFallbackWhenDisabled() {
        configure(false);
        GoogleMapsCalloutMock mock = new GoogleMapsCalloutMock();
        mock.geocodeBody = GoogleMapsCalloutMock.zeroResults();
        Test.setMock(HttpCalloutMock.class, mock);

        Assert.isNull(new GoogleGeocodingService().findCoordinates('addr'));
        Assert.areEqual(0, mock.countRequests('https://places.googleapis.com'));
    }

    @IsTest
    static void apiErrorStatusThrows() {
        configure(false);
        GoogleMapsCalloutMock mock = new GoogleMapsCalloutMock();
        mock.geocodeBody = GoogleMapsCalloutMock.geocodeError('REQUEST_DENIED', 'The provided API key is invalid.');
        Test.setMock(HttpCalloutMock.class, mock);

        try {
            new GoogleGeocodingService().findCoordinates('addr');
            Assert.fail('Expected GeocodingException');
        } catch (GoogleGeocodingService.GeocodingException e) {
            Assert.isTrue(e.getMessage().contains('REQUEST_DENIED'), e.getMessage());
        }
    }

    @IsTest
    static void httpErrorThrows() {
        configure(false);
        GoogleMapsCalloutMock mock = new GoogleMapsCalloutMock();
        mock.geocodeStatusCode = 500;
        mock.geocodeBody = 'Server error';
        Test.setMock(HttpCalloutMock.class, mock);

        try {
            new GoogleGeocodingService().findCoordinates('addr');
            Assert.fail('Expected GeocodingException');
        } catch (GoogleGeocodingService.GeocodingException e) {
            Assert.isTrue(e.getMessage().contains('500'), e.getMessage());
        }
    }

    @IsTest
    static void blankAddressMakesNoCallout() {
        configure(true);
        GoogleMapsCalloutMock mock = new GoogleMapsCalloutMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Assert.isNull(new GoogleGeocodingService().findCoordinates('   '));
        Assert.isNull(new GoogleGeocodingService().findCoordinates(null));
        Assert.areEqual(0, mock.requests.size());
    }

    @IsTest
    static void settingsDefaultsAndValidation() {
        GoogleMapsSettings.cached = null;
        Assert.isFalse(GoogleMapsSettings.isEnabled(), 'Disabled when no org default exists');
        Assert.areEqual(GoogleMapsSettings.DEFAULT_BATCH_SIZE, GoogleMapsSettings.batchSize());
        Assert.areEqual(GoogleMapsSettings.DEFAULT_TIMEOUT_MS, GoogleMapsSettings.timeoutMs());

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
    }
}
