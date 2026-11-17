// Creates / updates the Organization Default of Google_Maps_Settings__c.
// 1. Replace the placeholder API key (do NOT commit a real key to git).
// 2. Adjust the original latitude/longitude field API names to match ogg__Location__c in your org.
// Run:  sf apex run --file scripts/apex/configure-settings.apex --target-org tterakit-sb
Google_Maps_Settings__c s = Google_Maps_Settings__c.getOrgDefaults();
if (s == null || s.Id == null) {
    s = new Google_Maps_Settings__c(SetupOwnerId = UserInfo.getOrganizationId());
}
s.Enabled__c                  = true;
s.API_Key__c                  = 'PASTE_YOUR_GOOGLE_API_KEY_HERE';
s.Country_Code__c             = 'TH';          // restrict Geocoding results to Thailand
s.Region__c                   = 'th';          // result bias, blank = none
s.Language__c                 = 'th';          // Thai addresses -> Thai results
s.Use_Places_Fallback__c      = true;          // requires "Places API (New)" enabled on the key; helps with building names
s.Original_Latitude_Field__c  = 'Latitude__c'; // <-- CHANGE to the real field API name
s.Original_Longitude_Field__c = 'Longitude__c';// <-- CHANGE to the real field API name
s.Batch_Size__c               = 30;          // max 30 (up to 3 callouts per address)
s.Timeout_Ms__c               = 10000;
upsert s;
System.debug('Google_Maps_Settings__c saved: ' + s.Id);
