// Bulk: looks up ALL ogg__Location__c records that don't have a suggestion yet (Suggested_Latitude__c empty),
// using Batch Apex (30 records per batch with Google, 10 with OpenStreetMap; OpenStreetMap runs are capped
// at 200 records). Same as the list view button "Suggest Locations (Google)" with no records selected.
// Progress: Setup > Apex Jobs > AccountLocationGeocodeBatch.
// Run:  sf apex run --file scripts/apex/regeocode-existing.apex --target-org tterakit-sb
Id jobId = AccountLocationGeocodeBatch.run(null);
System.debug(LoggingLevel.ERROR, 'AccountLocationGeocodeBatch started: ' + jobId);
