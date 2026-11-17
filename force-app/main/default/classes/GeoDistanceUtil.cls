/**
 * Distance helpers. Uses the platform System.Location.getDistance (great-circle / Haversine).
 */
public without sharing class GeoDistanceUtil {

    /**
     * @return distance in meters (2 decimals) between two coordinates, or null if any value is missing / out of range.
     */
    public static Decimal distanceInMeters(Decimal lat1, Decimal lon1, Decimal lat2, Decimal lon2) {
        if (!isValid(lat1, lon1) || !isValid(lat2, lon2)) {
            return null;
        }
        Location a = Location.newInstance(lat1, lon1);
        Location b = Location.newInstance(lat2, lon2);
        Double km = Location.getDistance(a, b, 'km');
        return Decimal.valueOf(km * 1000).setScale(2, RoundingMode.HALF_UP);
    }

    /** Converts a field value (Decimal, Double, Integer or numeric String) to Decimal; null if not numeric. */
    public static Decimal toDecimal(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        try {
            String s = String.valueOf(value).trim();
            return String.isBlank(s) ? null : Decimal.valueOf(s);
        } catch (Exception e) {
            return null;
        }
    }

    private static Boolean isValid(Decimal lat, Decimal lon) {
        return lat != null && lon != null
            && lat >= -90 && lat <= 90
            && lon >= -180 && lon <= 180;
    }
}
