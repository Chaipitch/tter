/**
 * HttpCalloutMock for Google Geocoding API and Places API (New) Text Search.
 * Routes by endpoint host, can return a sequence of Geocoding responses, and records every request.
 */
@IsTest
public class GoogleMapsCalloutMock implements HttpCalloutMock {

    public Integer geocodeStatusCode = 200;
    public String  geocodeBody;                                  // used when geocodeBodies is empty
    public List<String> geocodeBodies = new List<String>();      // consumed in order, one per Geocoding call
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
            if (!geocodeBodies.isEmpty()) {
                res.setBody(geocodeBodies.remove(0));
            } else {
                res.setBody(geocodeBody == null ? zeroResults() : geocodeBody);
            }
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

    /** Decoded "address" query parameter of the n-th Geocoding request. */
    public String geocodeAddressParam(Integer n) {
        Integer seen = 0;
        for (HttpRequest r : requests) {
            if (r.getEndpoint().startsWith('https://maps.googleapis.com')) {
                if (seen == n) {
                    String url = r.getEndpoint();
                    String part = url.substringAfter('address=').substringBefore('&');
                    return EncodingUtil.urlDecode(part, 'UTF-8');
                }
                seen++;
            }
        }
        return null;
    }

    // ------------------------------------------------------------ canned responses

    public static String geocodeOk(Decimal lat, Decimal lng, String locationType, Boolean partialMatch) {
        return geocodeOk(lat, lng, locationType, partialMatch, null);
    }

    public static String geocodeOk(Decimal lat, Decimal lng, String locationType, Boolean partialMatch, String postcode) {
        Map<String, Object> result = new Map<String, Object>{
            'formatted_address' => 'Mock Address',
            'geometry' => new Map<String, Object>{
                'location' => new Map<String, Object>{ 'lat' => lat, 'lng' => lng },
                'location_type' => locationType
            },
            'address_components' => postcode == null ? new List<Object>() : new List<Object>{
                new Map<String, Object>{
                    'long_name' => postcode, 'short_name' => postcode, 'types' => new List<Object>{ 'postal_code' }
                }
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
        return placesOk(lat, lng, null);
    }

    public static String placesOk(Decimal lat, Decimal lng, String postcode) {
        return JSON.serialize(new Map<String, Object>{
            'places' => new List<Object>{
                new Map<String, Object>{
                    'formattedAddress' => 'Mock Place',
                    'location' => new Map<String, Object>{ 'latitude' => lat, 'longitude' => lng },
                    'addressComponents' => postcode == null ? new List<Object>() : new List<Object>{
                        new Map<String, Object>{
                            'longText' => postcode, 'shortText' => postcode, 'types' => new List<Object>{ 'postal_code' }
                        }
                    }
                }
            }
        });
    }
}
