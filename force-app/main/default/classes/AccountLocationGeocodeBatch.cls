/**
 * Bulk processing: geocodes many ogg__Location__c records with Batch Apex.
 *
 * Which records:
 *   new AccountLocationGeocodeBatch(ids)    the given records (e.g. selected in a list view)
 *   new AccountLocationGeocodeBatch()       all records not processed yet (isCoordsUpdated__c = false)
 *
 * Start it with AccountLocationGeocodeBatch.run(ids or null): it checks the feature is enabled and uses the
 * configured batch size (max 30 per execute = up to 90 callouts of the 100 allowed). It is also Schedulable,
 * e.g. nightly over all records not processed yet:
 *   System.schedule('Suggest locations nightly', '0 0 2 * * ?', new AccountLocationGeocodeBatch());
 *
 * With Provider__c = OpenStreetMap a run is capped at OSM_MAX_RECORDS_PER_RUN records: the Nominatim
 * usage policy does not allow bulk geocoding. Use Google for real volumes.
 */
public without sharing class AccountLocationGeocodeBatch
        implements Database.Batchable<SObject>, Database.AllowsCallouts, Schedulable {

    public class BatchException extends Exception {}

    public static final Integer OSM_MAX_RECORDS_PER_RUN = 200;

    private final Set<Id> recordIds;   // null = all records not processed yet (isCoordsUpdated__c = false)

    public AccountLocationGeocodeBatch() {
        this(null);
    }

    public AccountLocationGeocodeBatch(Set<Id> recordIds) {
        this.recordIds = (recordIds == null || recordIds.isEmpty()) ? null : recordIds;
    }

    /** Starts the batch. ids = null or empty: all records not processed yet. Returns the batch job Id. */
    public static Id run(Set<Id> ids) {
        if (!GoogleMapsSettings.isEnabled()) {
            throw new BatchException('Location lookup is turned off. Enable Google Maps Settings '
                + '(and add an API key, or set Provider to OpenStreetMap).');
        }
        return Database.executeBatch(new AccountLocationGeocodeBatch(ids), GoogleMapsSettings.batchSize());
    }

    /** True when this run processes all records not processed yet (no Ids given). */
    public Boolean isAllMissing() {
        return recordIds == null;
    }

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        String soql = 'SELECT Id FROM ogg__Location__c WHERE '
            + (recordIds != null ? 'Id IN :recordIds' : 'isCoordsUpdated__c = false')
            + ' ORDER BY CreatedDate DESC';
        if (GoogleMapsSettings.useOpenStreetMap()) {
            soql += ' LIMIT ' + OSM_MAX_RECORDS_PER_RUN;   // Nominatim: no bulk geocoding
        }
        return Database.getQueryLocatorWithBinds(
            soql, new Map<String, Object>{ 'recordIds' => recordIds }, AccessLevel.SYSTEM_MODE);
    }

    public void execute(Database.BatchableContext ctx, List<ogg__Location__c> scope) {
        if (!GoogleMapsSettings.isEnabled()) {
            return;   // switched off while the batch was running
        }
        List<Id> ids = new List<Id>(new Map<Id, ogg__Location__c>(scope).keySet());
        List<Id> deferred = AccountLocationGeocodeProcessor.process(ids);
        if (!deferred.isEmpty()) {
            // Only possible with a batch size above 30; these records keep no suggestion and are
            // picked up by the next "all records not processed yet" run.
            System.debug(LoggingLevel.ERROR, 'Callout limit reached; not processed in this run: ' + deferred);
        }
    }

    public void finish(Database.BatchableContext ctx) {
        System.debug(LoggingLevel.INFO, 'AccountLocationGeocodeBatch finished: ' + ctx.getJobId());
    }

    /** Scheduled run: all records not processed yet. */
    public void execute(SchedulableContext ctx) {
        if (GoogleMapsSettings.isEnabled()) {
            Database.executeBatch(new AccountLocationGeocodeBatch(), GoogleMapsSettings.batchSize());
        }
    }
}
