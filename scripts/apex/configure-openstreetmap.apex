// TEMPORARY: turns the feature on with the free OpenStreetMap (Nominatim) geocoder - no Google API key needed.
// For testing / demos only: weaker Thai coverage than Google, max 1 request per second, no bulk use.
// Switch to Google later with scripts/apex/configure-settings.apex (sets Provider__c = 'Google' and the key).
// Run:  sf apex run --file scripts/apex/configure-openstreetmap.apex --target-org tterakit-sb
Google_Maps_Settings__c s = Google_Maps_Settings__c.getOrgDefaults();
if (s == null || s.Id == null) {
    s = new Google_Maps_Settings__c(SetupOwnerId = UserInfo.getOrganizationId());
}
s.Enabled__c                  = true;
s.Provider__c                 = 'OpenStreetMap';
s.Original_Latitude_Field__c  = 'ogg__Latitude__c';
s.Original_Longitude_Field__c = 'ogg__Longitude__c';
s.Batch_Size__c               = 10;          // capped at 10 for OpenStreetMap anyway
s.Timeout_Ms__c               = 10000;
upsert s;
System.debug(LoggingLevel.ERROR, 'Google_Maps_Settings__c saved with Provider = OpenStreetMap: ' + s.Id);
