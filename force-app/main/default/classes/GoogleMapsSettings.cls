/**
 * Read-only accessor for the Google_Maps_Settings__c hierarchy custom setting (Organization Default).
 * Centralises defaults and validates the configurable "original coordinate" field names.
 */
public without sharing class GoogleMapsSettings {

    public class ConfigurationException extends Exception {}

    @TestVisible private static final String DEFAULT_LATITUDE_FIELD  = 'ogg__Latitude__c';
    @TestVisible private static final String DEFAULT_LONGITUDE_FIELD = 'ogg__Longitude__c';
    @TestVisible private static final Integer DEFAULT_BATCH_SIZE = 30;
    @TestVisible private static final Integer MAX_BATCH_SIZE     = 30;     // up to 3 callouts per record -> 90 of 100 callouts
    @TestVisible private static final Integer OSM_MAX_BATCH_SIZE = 10;     // Nominatim: max 1 request / second
    @TestVisible private static final Integer DEFAULT_TIMEOUT_MS = 10000;
    @TestVisible private static final Integer MAX_TIMEOUT_MS     = 120000;

    @TestVisible private static Google_Maps_Settings__c cached;

    public static Google_Maps_Settings__c get() {
        if (cached == null) {
            cached = Google_Maps_Settings__c.getOrgDefaults();
            if (cached == null) {
                cached = new Google_Maps_Settings__c();
            }
        }
        return cached;
    }

    /**
     * Feature is active only when explicitly enabled AND it can call its provider:
     * Google needs an API key, OpenStreetMap does not.
     */
    public static Boolean isEnabled() {
        Google_Maps_Settings__c s = get();
        return s.Enabled__c == true && (useOpenStreetMap() || String.isNotBlank(s.API_Key__c));
    }

    /**
     * True when Provider__c is "OpenStreetMap" (or "OSM"): use the free Nominatim geocoder instead of
     * Google. Temporary option for testing without a Google API key; blank or anything else = Google.
     */
    public static Boolean useOpenStreetMap() {
        String provider = trimToNull(get().Provider__c);
        return provider != null
            && (provider.equalsIgnoreCase('OpenStreetMap') || provider.equalsIgnoreCase('OSM'));
    }

    public static String apiKey()   { return get().API_Key__c; }
    public static String region()   { return trimToNull(get().Region__c); }
    public static String countryCode() { return trimToNull(get().Country_Code__c); }
    public static String language() { return trimToNull(get().Language__c); }
    public static Boolean usePlacesFallback() { return get().Use_Places_Fallback__c == true; }

    public static Integer batchSize() {
        Decimal v = get().Batch_Size__c;
        if (v == null || v < 1) {
            return useOpenStreetMap() ? OSM_MAX_BATCH_SIZE : DEFAULT_BATCH_SIZE;
        }
        Integer size = Math.min(v.intValue(), MAX_BATCH_SIZE);
        return useOpenStreetMap() ? Math.min(size, OSM_MAX_BATCH_SIZE) : size;
    }

    public static Integer timeoutMs() {
        Decimal v = get().Timeout_Ms__c;
        if (v == null || v < 1) {
            return DEFAULT_TIMEOUT_MS;
        }
        return Math.min(v.intValue(), MAX_TIMEOUT_MS);
    }

    public static String originalLatitudeField() {
        return validatedField(get().Original_Latitude_Field__c, DEFAULT_LATITUDE_FIELD);
    }

    public static String originalLongitudeField() {
        return validatedField(get().Original_Longitude_Field__c, DEFAULT_LONGITUDE_FIELD);
    }

    /** Ensures the configured API name is a real field on ogg__Location__c (also prevents SOQL injection). */
    private static String validatedField(String configured, String fallback) {
        String name = String.isBlank(configured) ? fallback : configured.trim();
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.ogg__Location__c.fields.getMap();
        Schema.SObjectField f = fields.get(name.toLowerCase());
        if (f == null) {
            throw new ConfigurationException(
                'Google_Maps_Settings__c: field "' + name + '" does not exist on ogg__Location__c.');
        }
        return f.getDescribe().getName();
    }

    private static String trimToNull(String s) {
        return String.isBlank(s) ? null : s.trim();
    }
}
