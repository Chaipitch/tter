// Deletes the test data created by scripts/apex/create-test-data.apex:
// all Accounts named "GEO-TEST ..." and every oggLocation linked to them (ogg__ObjectId__c),
// including ones UPWARD created for them.
// Run:  sf apex run --file scripts/apex/delete-test-data.apex --target-org tterakit-sb
List<Account> accounts = [SELECT Id FROM Account WHERE Name LIKE 'GEO-TEST %'];
Set<String> accountIds = new Set<String>();
for (Account a : accounts) {
    accountIds.add(String.valueOf(a.Id));
}
List<ogg__Location__c> locations = [SELECT Id FROM ogg__Location__c WHERE ogg__ObjectId__c IN :accountIds];
delete locations;
delete accounts;
System.debug(LoggingLevel.ERROR, 'Deleted ' + locations.size() + ' oggLocations and ' + accounts.size() + ' GEO-TEST Accounts.');
