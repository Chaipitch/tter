/**
 * TEMPORARY no-key alternative to Google: OpenStreetMap Nominatim search
 * (GET https://nominatim.openstreetmap.org/search). Used when Google_Maps_Settings__c.Provider__c = "OpenStreetMap".
 *
 * Nominatim usage policy (https://operations.osmfoundation.org/policies/nominatim/):
 *   - at most 1 request per second   -> throttle() spaces requests MIN_INTERVAL_MS apart (busy wait),
 *                                       and GoogleMapsSettings caps the batch size at 10
 *   - identify the application        -> User-Agent header
 *   - no heavy / bulk use             -> for demos and testing only; switch back to Google for real use
 *
 * Thai coverage in OpenStreetMap is weaker than Google's, especially for house numbers: expect more
 * street- or district-level results.
 */
public without sharing class OpenStreetMapGeocoder {

    @TestVisible private static final String SEARCH_ENDPOINT = 'https://nominatim.openstreetmap.org/search';
    @TestVisible private static final Integer MIN_INTERVAL_MS = 1100;
    private static final String USER_AGENT = 'Salesforce-AccountLocationGeocoding/1.0';

    // Nominatim place_rank: 26 = street, 28-30 = house / building / POI. Lower = area (district, province).
    private static final Integer MIN_PRECISE_PLACE_RANK = 26;

    private static Long lastRequestMs;

    /** First Nominatim match for the query, or null if nothing is found. */
    public static GoogleGeocodingService.GeocodeResult search(String query) {
        String url = SEARCH_ENDPOINT
            + '?q=' + EncodingUtil.urlEncode(query, 'UTF-8')
            + '&format=jsonv2&limit=1&addressdetails=1';
        if (GoogleMapsSettings.countryCode() != null) {
            url += '&countrycodes=' + EncodingUtil.urlEncode(GoogleMapsSettings.countryCode().toLowerCase(), 'UTF-8');
        }
        if (GoogleMapsSettings.language() != null) {
            url += '&accept-language=' + EncodingUtil.urlEncode(GoogleMapsSettings.language(), 'UTF-8');
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(url);
        req.setMethod('GET');
        req.setTimeout(GoogleMapsSettings.timeoutMs());
        req.setHeader('User-Agent', USER_AGENT);
        req.setHeader('Accept', 'application/json');

        throttle();
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            // 403 = blocked by the usage policy, 429 = too many requests
            throw new GoogleGeocodingService.GeocodingException(
                'OpenStreetMap Nominatim HTTP ' + res.getStatusCode() + ': ' + res.getStatus());
        }

        List<Object> results = (List<Object>) JSON.deserializeUntyped(res.getBody());
        if (results == null || results.isEmpty()) {
            return null;
        }
        Map<String, Object> first = (Map<String, Object>) results[0];

        GoogleGeocodingService.GeocodeResult r = new GoogleGeocodingService.GeocodeResult();
        r.latitude         = GeoDistanceUtil.toDecimal(first.get('lat'));   // Nominatim returns strings
        r.longitude        = GeoDistanceUtil.toDecimal(first.get('lon'));
        r.formattedAddress = (String) first.get('display_name');
        r.source           = GoogleGeocodingService.SOURCE_OPENSTREETMAP;

        Integer placeRank = first.get('place_rank') == null ? 0 : Integer.valueOf(first.get('place_rank'));
        r.locationType = placeRank >= MIN_PRECISE_PLACE_RANK ? 'OSM_RANK_' + placeRank : 'APPROXIMATE';

        Map<String, Object> address = (Map<String, Object>) first.get('address');
        if (address != null && address.get('postcode') != null) {
            r.postcode = String.valueOf(address.get('postcode')).trim();
        }
        return (r.latitude == null || r.longitude == null) ? null : r;
    }

    /** Keeps at least MIN_INTERVAL_MS between requests in this transaction (Nominatim: max 1 request/second). */
    private static void throttle() {
        if (lastRequestMs != null && !Test.isRunningTest()) {
            Long waitUntil = lastRequestMs + MIN_INTERVAL_MS;
            while (System.currentTimeMillis() < waitUntil) {
                // busy wait: Apex has no sleep()
            }
        }
        lastRequestMs = System.currentTimeMillis();
    }
}
