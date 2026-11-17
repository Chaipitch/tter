/**
 * HttpCalloutMock for Google Geocoding API and Places API (New) Text Search.
 * Routes by endpoint host and records every request for assertions.
 */
@IsTest
public class GoogleMapsCalloutMock implements HttpCalloutMock {

    public Integer geocodeStatusCode = 200;
    public String  geocodeBody;
    public Integer placesStatusCode  = 200;
    public String  placesBody;
    public List<HttpRequest> requests = new List<HttpRequest>();

    public HttpResponse respond(HttpRequest req) {
        requests.add(req);
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        if (req.getEndpoint().startsWith('https://places.googleapis.com')) {
            res.setStatusCode(placesStatusCode);
            res.setBody(placesBody == null ? '{}' : placesBody);
        } else {
            res.setStatusCode(geocodeStatusCode);
            res.setBody(geocodeBody == null ? zeroResults() : geocodeBody);
        }
        return res;
    }

    public Integer countRequests(String hostPrefix) {
        Integer n = 0;
        for (HttpRequest r : requests) {
            if (r.getEndpoint().startsWith(hostPrefix)) {
                n++;
            }
        }
        return n;
    }

    // ------------------------------------------------------------ canned responses

    public static String geocodeOk(Decimal lat, Decimal lng, String locationType, Boolean partialMatch) {
        Map<String, Object> result = new Map<String, Object>{
            'formatted_address' => 'Mock Address',
            'geometry' => new Map<String, Object>{
                'location' => new Map<String, Object>{ 'lat' => lat, 'lng' => lng },
                'location_type' => locationType
            }
        };
        if (partialMatch) {
            result.put('partial_match', true);
        }
        return JSON.serialize(new Map<String, Object>{
            'status'  => 'OK',
            'results' => new List<Object>{ result }
        });
    }

    public static String zeroResults() {
        return '{"status":"ZERO_RESULTS","results":[]}';
    }

    public static String geocodeError(String status, String message) {
        return JSON.serialize(new Map<String, Object>{
            'status' => status, 'error_message' => message, 'results' => new List<Object>()
        });
    }

    public static String placesOk(Decimal lat, Decimal lng) {
        return JSON.serialize(new Map<String, Object>{
            'places' => new List<Object>{
                new Map<String, Object>{
                    'formattedAddress' => 'Mock Place',
                    'location' => new Map<String, Object>{ 'latitude' => lat, 'longitude' => lng }
                }
            }
        });
    }
}
