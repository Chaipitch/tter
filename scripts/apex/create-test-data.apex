// Creates test data for the location lookup: Accounts named "GEO-TEST ..." with Thai addresses chosen
// for specific test cases, each with an oggLocation (ogg__Location__c) carrying a deliberate "UPWARD pin".
//   01-10  everyday cases (building/room/floor, abbreviations, Thai digits, no pin, nonsense, blank)
//   11-18  edge cases: UPWARD pin far away or invalid (other province / country, 0,0, flipped or swapped
//          coordinates, antipode), address and postcode that contradict each other
//
//  - Safe to re-run: cases whose GEO-TEST Account already exists are skipped.
//
//  - Required Account / oggLocation fields (e.g. Tax_ID__c, Customer_Type__c, Company__c) are filled
//    automatically from their type: text -> 13 random digits, picklist -> first active value,
//    lookup -> an existing record of that object. If a validation rule needs a specific value,
//    put it in ACCOUNT_VALUES below.
//  - If UPWARD already created an oggLocation for an Account when it was inserted, that one is kept
//    and no extra one is created (the debug output says which).
//  - Remove everything again with scripts/apex/delete-test-data.apex.
//
// Run:  sf apex run --file scripts/apex/create-test-data.apex --target-org tterakit-sb

// ---- values you may need to set for your org's validation rules (field API name -> value) ----
Map<String, Object> ACCOUNT_VALUES = new Map<String, Object>{
    // 'Tax_ID__c' => '0105556000000',
    // 'Customer_Type__c' => 'Corporate'
};

// ---- test cases: name, Account.Address__c, UPWARD pin latitude, longitude (null = no pin) ----
// "Expected" = roughly where Google should put it; verify in Google Maps.
List<List<Object>> CASES = new List<List<Object>>{
    // 1. Building + room + floor (TC-01). Expected: Emporium, Sukhumvit ~13.730, 100.569. Pin: Victory Monument (~4 km off)
    new List<Object>{ 'GEO-TEST 01 Emporium',
        '622 อาคารเอ็มโพเรียม ทาวเวอร์ ห้องเลขที่ 91,96 ชั้นที่ 9 ถนนสุขุมวิท แขวงคลองตัน เขตคลองเตย กรุงเทพมหานคร 10110',
        13.7650, 100.5383 },
    // 2. Clean address, pin already right (small distance expected). Expected: Siam Paragon ~13.746, 100.535
    new List<Object>{ 'GEO-TEST 02 Siam Paragon',
        '991 ถนนพระรามที่ 1 แขวงปทุมวัน เขตปทุมวัน กรุงเทพมหานคร 10330',
        13.7462, 100.5347 },
    // 3. Clean address, pin in the wrong district. Expected: CentralWorld ~13.747, 100.539. Pin: Chatuchak (~8 km off)
    new List<Object>{ 'GEO-TEST 03 CentralWorld',
        '999/9 ถนนพระรามที่ 1 แขวงปทุมวัน เขตปทุมวัน กรุงเทพมหานคร 10330',
        13.8000, 100.5500 },
    // 4. Abbreviations ถ. / กทม. (TC-02 style). Expected: Silom Road near Sala Daeng ~13.728, 100.534
    new List<Object>{ 'GEO-TEST 04 Silom abbreviations',
        '191 ถ.สีลม แขวงสีลม เขตบางรัก กทม. 10500',
        13.7563, 100.5018 },
    // 5. English room / floor mixed with Thai. Expected: Silom Complex ~13.728, 100.534
    new List<Object>{ 'GEO-TEST 05 English units',
        'Room 1203, 12th Floor, 191 ถนนสีลม แขวงสีลม เขตบางรัก กรุงเทพมหานคร 10500',
        13.7280, 100.5340 },
    // 6. Thai digits + ม./ต./อ./จ. outside Bangkok (TC-02). Expected: Bang Phut, Pak Kret (area level is fine)
    new List<Object>{ 'GEO-TEST 06 Thai digits Nonthaburi',
        'เลขที่ ๙๙/๑ ม.๓ ต.บางพูด อ.ปากเกร็ด จ.นนทบุรี ๑๑๑๒๐',
        13.7563, 100.5018 },
    // 7. Upcountry, no UPWARD pin (distance stays empty). Expected: Chiang Mai, Fa Ham area ~18.80, 99.02
    new List<Object>{ 'GEO-TEST 07 Chiang Mai no pin',
        '99/3 หมู่ 4 ถนนซุปเปอร์ไฮเวย์เชียงใหม่-ลำปาง ตำบลฟ้าฮ่าม อำเภอเมืองเชียงใหม่ จังหวัดเชียงใหม่ 50000',
        null, null },
    // 8. Only district + postcode (approximate result expected, larger distance is normal)
    new List<Object>{ 'GEO-TEST 08 District only',
        'แขวงลุมพินี เขตปทุมวัน กรุงเทพมหานคร 10330',
        13.7300, 100.5400 },
    // 9. Nonsense (TC-04). Expected: no suggestion, isCoordsUpdated__c stays unchecked
    new List<Object>{ 'GEO-TEST 09 Nonsense',
        'asdfgh qwerty 99999',
        13.7563, 100.5018 },
    // 10. Blank address (TC-05). Expected: skipped, no callout, isCoordsUpdated__c stays unchecked
    new List<Object>{ 'GEO-TEST 10 Blank address',
        null,
        13.7563, 100.5018 },

    // ---- edge cases: the UPWARD pin is far from the real address (Siam Paragon, ~13.746, 100.535) ----
    // 11. Pin in another province (Chiang Mai). Expected distance ~585 km
    new List<Object>{ 'GEO-TEST 11 Far pin other province',
        '991 ถนนพระรามที่ 1 แขวงปทุมวัน เขตปทุมวัน กรุงเทพมหานคร 10330',
        18.7883, 98.9853 },
    // 12. Pin in another country (Singapore). Expected distance ~1,430 km
    new List<Object>{ 'GEO-TEST 12 Far pin other country',
        '991 ถนนพระรามที่ 1 แขวงปทุมวัน เขตปทุมวัน กรุงเทพมหานคร 10330',
        1.2903, 103.8519 },
    // 13. Pin at 0,0 (a typical "default value" bug). Expected distance ~11,145 km
    new List<Object>{ 'GEO-TEST 13 Pin at zero',
        '991 ถนนพระรามที่ 1 แขวงปทุมวัน เขตปทุมวัน กรุงเทพมหานคร 10330',
        0.0, 0.0 },
    // 14. Longitude sign flipped (lands in Mexico). Expected distance ~16,180 km
    new List<Object>{ 'GEO-TEST 14 Pin longitude sign flipped',
        '991 ถนนพระรามที่ 1 แขวงปทุมวัน เขตปทุมวัน กรุงเทพมหานคร 10330',
        13.7462, -100.5347 },
    // 15. Opposite side of the earth (the largest possible distance). Expected ~20,015 km
    new List<Object>{ 'GEO-TEST 15 Pin at antipode',
        '991 ถนนพระรามที่ 1 แขวงปทุมวัน เขตปทุมวัน กรุงเทพมหานคร 10330',
        -13.7462, -79.4653 },
    // 16. Latitude and longitude swapped (latitude 100.5 is impossible). Expected: suggestion filled in,
    //     Different Distance EMPTY (an invalid pin gives no distance)
    new List<Object>{ 'GEO-TEST 16 Pin lat lng swapped',
        '991 ถนนพระรามที่ 1 แขวงปทุมวัน เขตปทุมวัน กรุงเทพมหานคร 10330',
        100.5347, 13.7462 },

    // ---- edge cases on the address side ----
    // 17. Address in Phuket, pin in Bangkok. Expected: suggestion in Phuket Town (~7.88, 98.39), distance ~690 km
    new List<Object>{ 'GEO-TEST 17 Phuket address Bangkok pin',
        'ถนนถลาง ตำบลตลาดใหญ่ อำเภอเมืองภูเก็ต จังหวัดภูเก็ต 83000',
        13.7462, 100.5347 },
    // 18. Address and postcode contradict (Bangkok address, Chiang Mai postcode 50000). Pin correct.
    //     Expected: the postcode check rejects matches as "not good", all search steps are tried, and the
    //     best-scored result is used (most likely still Siam Paragon); the probe script shows postcodeMatch=false
    new List<Object>{ 'GEO-TEST 18 Wrong postcode',
        '991 ถนนพระรามที่ 1 แขวงปทุมวัน เขตปทุมวัน กรุงเทพมหานคร 50000',
        13.7462, 100.5347 }
};

// Fills database-required fields that are still empty (same idea as TestRecordFactory, for anonymous Apex)
void fillRequired(SObject rec, Map<Schema.SObjectType, Id> lookupCache) {
    for (Schema.SObjectField f : rec.getSObjectType().getDescribe().fields.getMap().values()) {
        Schema.DescribeFieldResult d = f.getDescribe();
        if (d.isNillable() || !d.isCreateable() || d.isDefaultedOnCreate() || d.isCalculated()
                || d.isAutoNumber() || rec.get(d.getName()) != null) {
            continue;
        }
        Schema.DisplayType t = d.getType();
        if (t == Schema.DisplayType.STRING || t == Schema.DisplayType.TEXTAREA) {
            String digits = String.valueOf(Math.abs(Crypto.getRandomLong())).leftPad(13, '1').left(13);
            rec.put(d.getName(), digits.left(Math.max(1, d.getLength())));
        } else if (t == Schema.DisplayType.PICKLIST || t == Schema.DisplayType.MULTIPICKLIST) {
            for (Schema.PicklistEntry e : d.getPicklistValues()) {
                if (e.isActive()) { rec.put(d.getName(), e.getValue()); break; }
            }
        } else if (t == Schema.DisplayType.EMAIL) {
            rec.put(d.getName(), 'geo.test@example.com');
        } else if (t == Schema.DisplayType.PHONE) {
            rec.put(d.getName(), '0812345678');
        } else if (t == Schema.DisplayType.DOUBLE || t == Schema.DisplayType.INTEGER
                || t == Schema.DisplayType.CURRENCY || t == Schema.DisplayType.PERCENT) {
            rec.put(d.getName(), 1);
        } else if (t == Schema.DisplayType.DATE) {
            rec.put(d.getName(), Date.today());
        } else if (t == Schema.DisplayType.REFERENCE && !d.getReferenceTo().isEmpty()) {
            Schema.SObjectType target = d.getReferenceTo()[0];
            if (!lookupCache.containsKey(target)) {
                List<SObject> found = Database.query('SELECT Id FROM ' + target.getDescribe().getName() + ' LIMIT 1');
                lookupCache.put(target, found.isEmpty() ? null : found[0].Id);
            }
            if (lookupCache.get(target) != null) {
                rec.put(d.getName(), lookupCache.get(target));
            } else {
                System.debug(LoggingLevel.ERROR, 'No ' + target + ' record found for required field '
                    + d.getName() + ': set it in ACCOUNT_VALUES.');
            }
        }
    }
}

// ---- 1. Accounts (cases whose Account already exists are skipped) ----
Set<String> existingNames = new Set<String>();
for (Account a : [SELECT Name FROM Account WHERE Name LIKE 'GEO-TEST %']) {
    existingNames.add(a.Name);
}
Map<Schema.SObjectType, Id> lookupCache = new Map<Schema.SObjectType, Id>();
List<Account> accounts = new List<Account>();
List<List<Object>> created = new List<List<Object>>();   // the case behind each new Account
for (List<Object> c : CASES) {
    if (existingNames.contains((String) c[0])) {
        System.debug(LoggingLevel.ERROR, c[0] + ': already exists, skipped');
        continue;
    }
    created.add(c);
    Account a = new Account(Name = (String) c[0], Address__c = (String) c[1]);
    for (String field : ACCOUNT_VALUES.keySet()) {
        a.put(field, ACCOUNT_VALUES.get(field));
    }
    fillRequired(a, lookupCache);
    accounts.add(a);
}
if (accounts.isEmpty()) {
    System.debug(LoggingLevel.ERROR, 'All GEO-TEST cases already exist; nothing to create.');
}
insert accounts;

// ---- 2. oggLocations (only where UPWARD didn't create one already) ----
Set<String> accountIds = new Set<String>();
for (Account a : accounts) {
    accountIds.add(String.valueOf(a.Id));
}
Set<String> existing = new Set<String>();
for (ogg__Location__c l : [SELECT ogg__ObjectId__c FROM ogg__Location__c WHERE ogg__ObjectId__c IN :accountIds]) {
    existing.add(l.ogg__ObjectId__c);
}

List<ogg__Location__c> locations = new List<ogg__Location__c>();
List<String> locationCase = new List<String>();   // case name per entry in locations
for (Integer i = 0; i < accounts.size(); i++) {
    String accId = String.valueOf(accounts[i].Id);
    if (existing.contains(accId)) {
        System.debug(LoggingLevel.ERROR, accounts[i].Name + ': UPWARD already created an oggLocation, kept as is');
        continue;
    }
    ogg__Location__c loc = new ogg__Location__c(
        ogg__ObjectId__c   = accId,
        ogg__prefix__c     = accId.left(3),
        ogg__RawAddress__c = (String) created[i][1],
        ogg__Latitude__c   = (Decimal) created[i][2],
        ogg__Longitude__c  = (Decimal) created[i][3],
        isCoordsUpdated__c = false);
    fillRequired(loc, lookupCache);
    locations.add(loc);
    locationCase.add((String) created[i][0]);
}
// Partial success: if UPWARD / a validation rule rejects an impossible pin (e.g. case 16), the others are kept
List<Database.SaveResult> results = Database.insert(locations, false);
for (Integer i = 0; i < results.size(); i++) {
    if (!results[i].isSuccess()) {
        System.debug(LoggingLevel.ERROR, 'oggLocation for ' + locationCase[i] + ' was rejected: ' + results[i].getErrors());
    }
}

// ---- 3. Summary ----
for (ogg__Location__c l : [
        SELECT Id, Name, ogg__ObjectId__c, ogg__Latitude__c, ogg__Longitude__c
        FROM ogg__Location__c WHERE ogg__ObjectId__c IN :accountIds ORDER BY Name]) {
    System.debug(LoggingLevel.ERROR, 'oggLocation ' + l.Name + ' (' + l.Id + ') -> Account ' + l.ogg__ObjectId__c
        + ', UPWARD pin ' + l.ogg__Latitude__c + ', ' + l.ogg__Longitude__c);
}
System.debug(LoggingLevel.ERROR, 'Created ' + accounts.size() + ' GEO-TEST Accounts and ' + locations.size()
    + ' oggLocations. Open the oggLocation list view and use "Suggest Locations (Google)".');
