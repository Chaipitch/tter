/**
 * Looks up coordinates for a free-text address using Google Maps Platform.
 *
 *  1. Geocoding API  (GET https://maps.googleapis.com/maps/api/geocode/json)
 *  2. Optional fallback: Places API (New) Text Search (POST https://places.googleapis.com/v1/places:searchText)
 *     used when the Geocoding API returns no result, a partial match, or only an APPROXIMATE location.
 *     Text Search copes better with addresses that do not exactly match Google's address data
 *     (typos, building/shop names, mixed languages).
 *
 * Callouts only - no DML - so it can be called repeatedly inside one transaction.
 */
public without sharing class GoogleGeocodingService {

    public class GeocodingException extends Exception {}

    @TestVisible private static final String GEOCODE_ENDPOINT = 'https://maps.googleapis.com/maps/api/geocode/json';
    @TestVisible private static final String PLACES_ENDPOINT  = 'https://places.googleapis.com/v1/places:searchText';

    public static final String SOURCE_GEOCODING = 'GEOCODING_API';
    public static final String SOURCE_PLACES    = 'PLACES_TEXT_SEARCH';

    public class GeocodeResult {
        public Decimal latitude;
        public Decimal longitude;
        public String  formattedAddress;
        public String  source;
        public String  locationType;     // Geocoding API only: ROOFTOP, RANGE_INTERPOLATED, GEOMETRIC_CENTER, APPROXIMATE
        public Boolean partialMatch = false;

        /** True when the Geocoding API result is an exact, non-approximate match. */
        public Boolean isPrecise() {
            return partialMatch != true && locationType != 'APPROXIMATE';
        }
    }

    /**
     * Best available coordinates for the address, or null if Google returns nothing.
     * Throws GeocodingException for configuration / API errors from the primary Geocoding call.
     */
    public GeocodeResult findCoordinates(String address) {
        if (String.isBlank(address)) {
            return null;
        }
        String query = address.normalizeSpace();

        GeocodeResult geo = geocode(query);
        if (geo != null && geo.isPrecise()) {
            return geo;
        }
        if (GoogleMapsSettings.usePlacesFallback()) {
            try {
                GeocodeResult place = searchText(query);
                if (place != null) {
                    return place;
                }
            } catch (Exception e) {
                // Fallback is best-effort; keep the Geocoding result (if any).
                System.debug(LoggingLevel.WARN, 'Places Text Search fallback failed: ' + e.getMessage());
            }
        }
        return geo;
    }

    // ------------------------------------------------------------------ Geocoding API

    @TestVisible
    private GeocodeResult geocode(String address) {
        String url = GEOCODE_ENDPOINT
            + '?address=' + EncodingUtil.urlEncode(address, 'UTF-8')
            + '&key=' + EncodingUtil.urlEncode(GoogleMapsSettings.apiKey(), 'UTF-8');
        if (GoogleMapsSettings.region() != null) {
            url += '&region=' + EncodingUtil.urlEncode(GoogleMapsSettings.region(), 'UTF-8');
        }
        if (GoogleMapsSettings.language() != null) {
            url += '&language=' + EncodingUtil.urlEncode(GoogleMapsSettings.language(), 'UTF-8');
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(url);
        req.setMethod('GET');
        req.setTimeout(GoogleMapsSettings.timeoutMs());

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new GeocodingException('Geocoding API HTTP ' + res.getStatusCode() + ': ' + res.getStatus());
        }

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        String status = (String) body.get('status');
        if (status == 'ZERO_RESULTS') {
            return null;
        }
        if (status != 'OK') {
            throw new GeocodingException('Geocoding API status ' + status
                + (body.containsKey('error_message') ? ': ' + body.get('error_message') : ''));
        }

        List<Object> results = (List<Object>) body.get('results');
        if (results == null || results.isEmpty()) {
            return null;
        }
        Map<String, Object> first    = (Map<String, Object>) results[0];
        Map<String, Object> geometry = (Map<String, Object>) first.get('geometry');
        Map<String, Object> location = (Map<String, Object>) geometry.get('location');

        GeocodeResult r = new GeocodeResult();
        r.latitude         = GeoDistanceUtil.toDecimal(location.get('lat'));
        r.longitude        = GeoDistanceUtil.toDecimal(location.get('lng'));
        r.formattedAddress = (String) first.get('formatted_address');
        r.locationType     = (String) geometry.get('location_type');
        r.partialMatch     = first.get('partial_match') == true;
        r.source           = SOURCE_GEOCODING;
        return (r.latitude == null || r.longitude == null) ? null : r;
    }

    // ------------------------------------------------------------------ Places API (New) Text Search

    @TestVisible
    private GeocodeResult searchText(String address) {
        Map<String, Object> payload = new Map<String, Object>{
            'textQuery' => address,
            'pageSize'  => 1
        };
        if (GoogleMapsSettings.language() != null) {
            payload.put('languageCode', GoogleMapsSettings.language());
        }
        if (GoogleMapsSettings.region() != null) {
            payload.put('regionCode', GoogleMapsSettings.region());
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(PLACES_ENDPOINT);
        req.setMethod('POST');
        req.setTimeout(GoogleMapsSettings.timeoutMs());
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('X-Goog-Api-Key', GoogleMapsSettings.apiKey());
        req.setHeader('X-Goog-FieldMask', 'places.location,places.formattedAddress');
        req.setBody(JSON.serialize(payload));

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new GeocodingException('Places API HTTP ' + res.getStatusCode() + ': ' + res.getBody());
        }

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> places = (List<Object>) body.get('places');
        if (places == null || places.isEmpty()) {
            return null;
        }
        Map<String, Object> first    = (Map<String, Object>) places[0];
        Map<String, Object> location = (Map<String, Object>) first.get('location');
        if (location == null) {
            return null;
        }

        GeocodeResult r = new GeocodeResult();
        r.latitude         = GeoDistanceUtil.toDecimal(location.get('latitude'));
        r.longitude        = GeoDistanceUtil.toDecimal(location.get('longitude'));
        r.formattedAddress = (String) first.get('formattedAddress');
        r.source           = SOURCE_PLACES;
        return (r.latitude == null || r.longitude == null) ? null : r;
    }
}
