public without sharing class GoogleGeocodingService {

    public class GeocodingException extends Exception {}

    @TestVisible private static final String GEOCODE_ENDPOINT = 'https://maps.googleapis.com/maps/api/geocode/json';
    @TestVisible private static final String PLACES_ENDPOINT  = 'https://places.googleapis.com/v1/places:searchText';

    /** Upper bound of HTTP callouts for one address (2 Geocoding + 1 Places). */
    public static final Integer MAX_CALLOUTS_PER_ADDRESS = 3;

    public static final String SOURCE_GEOCODING = 'GEOCODING_API';
    public static final String SOURCE_PLACES    = 'PLACES_TEXT_SEARCH';
    public static final String SOURCE_OPENSTREETMAP = 'OPENSTREETMAP';

    public class GeocodeResult {
        public Decimal latitude;
        public Decimal longitude;
        public String  formattedAddress;
        public String  source;
        public String  query;            // the query string that produced this result
        public String  locationType;     // Geocoding API only: ROOFTOP, RANGE_INTERPOLATED, GEOMETRIC_CENTER, APPROXIMATE
        public Boolean partialMatch = false;
        public String  postcode;         // postcode of the result, if Google returned one
        public Boolean postcodeMatch;    // true / false, or null when either side has no postcode

        /** Not a partial match and more specific than APPROXIMATE (district / province level). */
        public Boolean isPrecise() {
            return partialMatch != true && locationType != 'APPROXIMATE';
        }

        /** Precise and the postcode does not contradict the input. */
        public Boolean isGood() {
            return isPrecise() && postcodeMatch != false;
        }

        /** Ranking when no result is good: postcode match > unknown > mismatch, then precision. */
        public Integer score() {
            Integer s = postcodeMatch == true ? 4 : (postcodeMatch == null ? 2 : 0);
            return s + (isPrecise() ? 1 : 0);
        }
    }

    /**
     * Best available coordinates for the address, or null if Google returns nothing.
     * Throws GeocodingException for configuration / API errors from the Geocoding API
     * (e.g. REQUEST_DENIED, OVER_QUERY_LIMIT). Places errors are logged and ignored.
     */
    public GeocodeResult findCoordinates(String address) {
        if (String.isBlank(address)) {
            return null;
        }
        ThaiAddressNormalizer.PreparedAddress prepared = ThaiAddressNormalizer.prepare(address);
        List<GeocodeResult> candidates = new List<GeocodeResult>();

        // Provider__c = OpenStreetMap: same queries and scoring, but Nominatim instead of Google (no Places step)
        Boolean osm = GoogleMapsSettings.useOpenStreetMap();

        for (String query : prepared.geocodingQueries()) {
            GeocodeResult r = osm ? OpenStreetMapGeocoder.search(query) : geocode(query);
            if (r != null) {
                evaluate(r, query, prepared.postcode);
                if (r.isGood()) {
                    return r;
                }
                candidates.add(r);
            }
        }

        if (!osm && GoogleMapsSettings.usePlacesFallback()) {
            try {
                GeocodeResult r = searchText(prepared.withoutUnit);
                if (r != null) {
                    evaluate(r, prepared.withoutUnit, prepared.postcode);
                    if (r.isGood()) {
                        return r;
                    }
                    candidates.add(r);
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Places Text Search fallback failed: ' + e.getMessage());
            }
        }
        return best(candidates);
    }

    private static void evaluate(GeocodeResult r, String query, String inputPostcode) {
        r.query = query;
        if (String.isNotBlank(inputPostcode) && String.isNotBlank(r.postcode)) {
            r.postcodeMatch = inputPostcode == r.postcode;
        }
    }

    /** Highest score wins; on a tie the earlier (cheaper / more specific query) candidate is kept. */
    private static GeocodeResult best(List<GeocodeResult> candidates) {
        GeocodeResult winner = null;
        for (GeocodeResult r : candidates) {
            if (winner == null || r.score() > winner.score()) {
                winner = r;
            }
        }
        return winner;
    }

    // ------------------------------------------------------------------ Geocoding API

    @TestVisible
    private GeocodeResult geocode(String address) {
        String url = GEOCODE_ENDPOINT
            + '?address=' + EncodingUtil.urlEncode(address, 'UTF-8')
            + '&key=' + EncodingUtil.urlEncode(GoogleMapsSettings.apiKey(), 'UTF-8');
        url += '&components=' + EncodingUtil.urlEncode('country:' + GoogleMapsSettings.countryCode(), 'UTF-8')
            + '&language=' + EncodingUtil.urlEncode(GoogleMapsSettings.language(), 'UTF-8');

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
        r.postcode         = findPostcode((List<Object>) first.get('address_components'), 'long_name');
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
        payload.put('languageCode', GoogleMapsSettings.language());
        payload.put('regionCode', GoogleMapsSettings.countryCode());

        HttpRequest req = new HttpRequest();
        req.setEndpoint(PLACES_ENDPOINT);
        req.setMethod('POST');
        req.setTimeout(GoogleMapsSettings.timeoutMs());
        req.setHeader('Content-Type', 'application/json; charset=UTF-8');
        req.setHeader('X-Goog-Api-Key', GoogleMapsSettings.apiKey());
        req.setHeader('X-Goog-FieldMask', 'places.location,places.formattedAddress,places.addressComponents');
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
        r.postcode         = findPostcode((List<Object>) first.get('addressComponents'), 'longText');
        r.source           = SOURCE_PLACES;
        return (r.latitude == null || r.longitude == null) ? null : r;
    }

    /** Value of the address component whose types contain 'postal_code'. */
    private static String findPostcode(List<Object> components, String valueKey) {
        if (components == null) {
            return null;
        }
        for (Object o : components) {
            Map<String, Object> c = (Map<String, Object>) o;
            List<Object> types = (List<Object>) c.get('types');
            if (types != null && types.contains('postal_code')) {
                return (String) c.get(valueKey);
            }
        }
        return null;
    }
}
