// Overwrites the UPWARD pin (ogg__Latitude__c / ogg__Longitude__c) of the GEO-TEST oggLocations with
// deliberate test pins, and clears the lookup results (Suggested_*, Different_Distance__c, isCoordsUpdated__c),
// so the cases can be run again with the Account list view button or the record button.
//
// Run it AFTER create-test-data.apex, once UPWARD has created the oggLocations.
// This is an update, so the on-create trigger doesn't fire: start the lookup yourself afterwards
// (Account list view button "Suggest Locations (Google)").
// Run it again any time to reset the GEO-TEST results to these pins.
//
// Run:  sf apex run --file scripts/apex/apply-test-pins.apex --target-org tterakit-sb

// Account name -> test pin { latitude, longitude }. null = no pin. Expected results: see create-test-data.apex.
Map<String, List<Decimal>> PINS = new Map<String, List<Decimal>>{
    'GEO-TEST 01 Emporium' => new List<Decimal>{ 13.7650, 100.5383 },
    'GEO-TEST 02 Siam Paragon' => new List<Decimal>{ 13.7462, 100.5347 },
    'GEO-TEST 03 CentralWorld' => new List<Decimal>{ 13.8000, 100.5500 },
    'GEO-TEST 04 Silom abbreviations' => new List<Decimal>{ 13.7563, 100.5018 },
    'GEO-TEST 05 English units' => new List<Decimal>{ 13.7280, 100.5340 },
    'GEO-TEST 06 Thai digits Nonthaburi' => new List<Decimal>{ 13.7563, 100.5018 },
    'GEO-TEST 07 Chiang Mai no pin' => new List<Decimal>{ null, null },
    'GEO-TEST 08 District only' => new List<Decimal>{ 13.7300, 100.5400 },
    'GEO-TEST 09 Nonsense' => new List<Decimal>{ 13.7563, 100.5018 },
    'GEO-TEST 10 Blank address' => new List<Decimal>{ 13.7563, 100.5018 },
    'GEO-TEST 11 Far pin other province' => new List<Decimal>{ 18.7883, 98.9853 },
    'GEO-TEST 12 Far pin other country' => new List<Decimal>{ 1.2903, 103.8519 },
    'GEO-TEST 13 Pin at zero' => new List<Decimal>{ 0.0, 0.0 },
    'GEO-TEST 14 Pin longitude sign flipped' => new List<Decimal>{ 13.7462, -100.5347 },
    'GEO-TEST 15 Pin at antipode' => new List<Decimal>{ -13.7462, -79.4653 },
    'GEO-TEST 16 Pin lat lng swapped' => new List<Decimal>{ 100.5347, 13.7462 },
    'GEO-TEST 17 Phuket address Bangkok pin' => new List<Decimal>{ 13.7462, 100.5347 },
    'GEO-TEST 18 Wrong postcode' => new List<Decimal>{ 13.7462, 100.5347 }
};

Map<String, Account> accountsById = new Map<String, Account>();
for (Account a : [SELECT Id, Name FROM Account WHERE Name IN :PINS.keySet()]) {
    accountsById.put(String.valueOf(a.Id), a);
}

Set<String> withLocation = new Set<String>();
List<ogg__Location__c> updates = new List<ogg__Location__c>();
for (ogg__Location__c l : [SELECT Id, Name, ogg__ObjectId__c FROM ogg__Location__c
                           WHERE ogg__ObjectId__c IN :accountsById.keySet()]) {
    Account a = accountsById.get(l.ogg__ObjectId__c);
    List<Decimal> pin = PINS.get(a.Name);
    withLocation.add(a.Name);
    updates.add(new ogg__Location__c(
        Id = l.Id,
        ogg__Latitude__c        = pin[0],
        ogg__Longitude__c       = pin[1],
        Suggested_Latitude__c   = null,
        Suggested_Longtitude__c = null,
        Different_Distance__c   = null,
        isCoordsUpdated__c      = false));
    System.debug(LoggingLevel.ERROR, a.Name + ' -> ' + l.Name + ': pin set to ' + pin[0] + ', ' + pin[1]);
}

// Partial success: UPWARD or a validation rule may reject an impossible pin (e.g. case 16)
List<Database.SaveResult> results = Database.update(updates, false);
for (Integer i = 0; i < results.size(); i++) {
    if (!results[i].isSuccess()) {
        System.debug(LoggingLevel.ERROR, 'Rejected ' + updates[i].Id + ': ' + results[i].getErrors());
    }
}

for (String name : PINS.keySet()) {
    if (!withLocation.contains(name)) {
        System.debug(LoggingLevel.ERROR, name + ': no oggLocation yet (UPWARD hasn\'t created one, or the Account is missing)');
    }
}
System.debug(LoggingLevel.ERROR, 'Applied test pins to ' + updates.size() + ' oggLocations. '
    + 'Now run the Account list view button "Suggest Locations (Google)".');
