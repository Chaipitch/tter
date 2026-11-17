// Schedules a nightly bulk run (02:00 in the org's time zone) over all ogg__Location__c records
// that don't have a suggestion yet. Use with Google as the provider (OpenStreetMap is for testing only).
// To stop it: Setup > Scheduled Jobs > "Suggest locations nightly" > Del.
// Run:  sf apex run --file scripts/apex/schedule-nightly.apex --target-org tterakit-sb
Id cronId = System.schedule('Suggest locations nightly', '0 0 2 * * ?', new AccountLocationGeocodeBatch());
System.debug(LoggingLevel.ERROR, 'Scheduled: ' + cronId);
