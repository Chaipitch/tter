// Creates test Accounts for the location lookup: 18 Accounts named "GEO-TEST ..." with Thai addresses chosen
// for specific test cases, in both Address__c (used by the lookup) and the Billing Address (used by UPWARD to
// create the oggLocation). The oggLocations are left to UPWARD, as in real use:
//
//   1. Run this script. UPWARD creates the oggLocation for each Account (with its own pin), and the
//      on-create trigger then looks it up automatically.
//   2. Optional, for the pin test cases (11-16 especially): once UPWARD has created the oggLocations, run
//      scripts/apex/apply-test-pins.apex. It overwrites UPWARD's pins with deliberate test pins
//      (far away, 0,0, swapped, ...) and clears the results, so you can run the lookup again.
//
//   01-10  everyday cases (building/room/floor, abbreviations, Thai digits, upcountry, nonsense, blank)
//   11-18  edge cases (with apply-test-pins: pin far away or invalid; address and postcode contradicting)
//
//  - Safe to re-run: Accounts that already exist are skipped.
//  - Required Account fields (e.g. Tax_ID__c, Customer_Type__c, Company__c) are filled automatically from
//    their type: text -> 13 random digits, picklist -> first active value, lookup -> an existing record.
//    If a validation rule needs a specific value, put it in ACCOUNT_VALUES below.
//  - UPWARD may not create an oggLocation for case 10 (blank address) or 09 (nonsense).
//  - Remove everything again with scripts/apex/delete-test-data.apex.
//
// Run:  sf apex run --file scripts/apex/create-test-data.apex --target-org tterakit-sb

// ---- values you may need to set for your org's validation rules (field API name -> value) ----
Map<String, Object> ACCOUNT_VALUES = new Map<String, Object>{
    // 'Tax_ID__c' => '0105556000000',
    // 'Customer_Type__c' => 'Corporate'
};

// ---- test cases: Account name, Account.Address__c (full address),
//      Billing Street, Billing City (district), Billing State (province), Billing Postal Code ----
// Billing Country is Thailand for all of them.
// "Expected" = roughly where Google should put it; verify in Google Maps.
// The pins mentioned are the test pins set by apply-test-pins.apex.
List<List<Object>> CASES = new List<List<Object>>{
    // 1. Building + room + floor (TC-01). Expected: Emporium, Sukhumvit ~13.730, 100.569. Pin: Victory Monument (~4 km off)
    new List<Object>{ 'GEO-TEST 01 Emporium',
        '622 อาคารเอ็มโพเรียม ทาวเวอร์ ห้องเลขที่ 91,96 ชั้นที่ 9 ถนนสุขุมวิท แขวงคลองตัน เขตคลองเตย กรุงเทพมหานคร 10110',
        '622 อาคารเอ็มโพเรียม ทาวเวอร์ ห้องเลขที่ 91,96 ชั้นที่ 9 ถนนสุขุมวิท แขวงคลองตัน', 'เขตคลองเตย', 'กรุงเทพมหานคร', '10110' },
    // 2. Clean address, pin already right (small distance expected). Expected: Siam Paragon ~13.746, 100.535
    new List<Object>{ 'GEO-TEST 02 Siam Paragon',
        '991 ถนนพระรามที่ 1 แขวงปทุมวัน เขตปทุมวัน กรุงเทพมหานคร 10330',
        '991 ถนนพระรามที่ 1 แขวงปทุมวัน', 'เขตปทุมวัน', 'กรุงเทพมหานคร', '10330' },
    // 3. Clean address, pin in the wrong district. Expected: CentralWorld ~13.747, 100.539. Pin: Chatuchak (~8 km off)
    new List<Object>{ 'GEO-TEST 03 CentralWorld',
        '999/9 ถนนพระรามที่ 1 แขวงปทุมวัน เขตปทุมวัน กรุงเทพมหานคร 10330',
        '999/9 ถนนพระรามที่ 1 แขวงปทุมวัน', 'เขตปทุมวัน', 'กรุงเทพมหานคร', '10330' },
    // 4. Abbreviations ถ. / กทม. (TC-02 style). Expected: Silom Road near Sala Daeng ~13.728, 100.534
    new List<Object>{ 'GEO-TEST 04 Silom abbreviations',
        '191 ถ.สีลม แขวงสีลม เขตบางรัก กทม. 10500',
        '191 ถ.สีลม แขวงสีลม', 'เขตบางรัก', 'กทม.', '10500' },
    // 5. English room / floor mixed with Thai. Expected: Silom Complex ~13.728, 100.534
    new List<Object>{ 'GEO-TEST 05 English units',
        'Room 1203, 12th Floor, 191 ถนนสีลม แขวงสีลม เขตบางรัก กรุงเทพมหานคร 10500',
        'Room 1203, 12th Floor, 191 ถนนสีลม แขวงสีลม', 'เขตบางรัก', 'กรุงเทพมหานคร', '10500' },
    // 6. Thai digits + ม./ต./อ./จ. outside Bangkok (TC-02). Expected: Bang Phut, Pak Kret (area level is fine)
    new List<Object>{ 'GEO-TEST 06 Thai digits Nonthaburi',
        'เลขที่ ๙๙/๑ ม.๓ ต.บางพูด อ.ปากเกร็ด จ.นนทบุรี ๑๑๑๒๐',
        'เลขที่ ๙๙/๑ ม.๓ ต.บางพูด', 'อ.ปากเกร็ด', 'จ.นนทบุรี', '๑๑๑๒๐' },
    // 7. Upcountry, no UPWARD pin (distance stays empty). Expected: Chiang Mai, Fa Ham area ~18.80, 99.02
    new List<Object>{ 'GEO-TEST 07 Chiang Mai no pin',
        '99/3 หมู่ 4 ถนนซุปเปอร์ไฮเวย์เชียงใหม่-ลำปาง ตำบลฟ้าฮ่าม อำเภอเมืองเชียงใหม่ จังหวัดเชียงใหม่ 50000',
        '99/3 หมู่ 4 ถนนซุปเปอร์ไฮเวย์เชียงใหม่-ลำปาง ตำบลฟ้าฮ่าม', 'อำเภอเมืองเชียงใหม่', 'จังหวัดเชียงใหม่', '50000' },
    // 8. Only district + postcode (approximate result expected, larger distance is normal)
    new List<Object>{ 'GEO-TEST 08 District only',
        'แขวงลุมพินี เขตปทุมวัน กรุงเทพมหานคร 10330',
        'แขวงลุมพินี', 'เขตปทุมวัน', 'กรุงเทพมหานคร', '10330' },
    // 9. Nonsense (TC-04). Expected: no suggestion, isCoordsUpdated__c stays unchecked
    new List<Object>{ 'GEO-TEST 09 Nonsense',
        'asdfgh qwerty 99999',
        'asdfgh qwerty', null, null, '99999' },
    // 10. Blank address (TC-05). Expected: skipped, no callout, isCoordsUpdated__c stays unchecked
    new List<Object>{ 'GEO-TEST 10 Blank address',
        null,
        null, null, null, null },
    // ---- edge cases: the UPWARD pin is far from the real address (Siam Paragon, ~13.746, 100.535) ----
    // 11. Pin in another province (Chiang Mai). Expected distance ~585 km
    new List<Object>{ 'GEO-TEST 11 Far pin other province',
        '991 ถนนพระรามที่ 1 แขวงปทุมวัน เขตปทุมวัน กรุงเทพมหานคร 10330',
        '991 ถนนพระรามที่ 1 แขวงปทุมวัน', 'เขตปทุมวัน', 'กรุงเทพมหานคร', '10330' },
    // 12. Pin in another country (Singapore). Expected distance ~1,430 km
    new List<Object>{ 'GEO-TEST 12 Far pin other country',
        '991 ถนนพระรามที่ 1 แขวงปทุมวัน เขตปทุมวัน กรุงเทพมหานคร 10330',
        '991 ถนนพระรามที่ 1 แขวงปทุมวัน', 'เขตปทุมวัน', 'กรุงเทพมหานคร', '10330' },
    // 13. Pin at 0,0 (a typical "default value" bug). Expected distance ~11,145 km
    new List<Object>{ 'GEO-TEST 13 Pin at zero',
        '991 ถนนพระรามที่ 1 แขวงปทุมวัน เขตปทุมวัน กรุงเทพมหานคร 10330',
        '991 ถนนพระรามที่ 1 แขวงปทุมวัน', 'เขตปทุมวัน', 'กรุงเทพมหานคร', '10330' },
    // 14. Longitude sign flipped (lands in Mexico). Expected distance ~16,180 km
    new List<Object>{ 'GEO-TEST 14 Pin longitude sign flipped',
        '991 ถนนพระรามที่ 1 แขวงปทุมวัน เขตปทุมวัน กรุงเทพมหานคร 10330',
        '991 ถนนพระรามที่ 1 แขวงปทุมวัน', 'เขตปทุมวัน', 'กรุงเทพมหานคร', '10330' },
    // 15. Opposite side of the earth (the largest possible distance). Expected ~20,015 km
    new List<Object>{ 'GEO-TEST 15 Pin at antipode',
        '991 ถนนพระรามที่ 1 แขวงปทุมวัน เขตปทุมวัน กรุงเทพมหานคร 10330',
        '991 ถนนพระรามที่ 1 แขวงปทุมวัน', 'เขตปทุมวัน', 'กรุงเทพมหานคร', '10330' },
    // 16. Latitude and longitude swapped (latitude 100.5 is impossible). Expected: suggestion filled in,
    //     Different Distance EMPTY (an invalid pin gives no distance)
    new List<Object>{ 'GEO-TEST 16 Pin lat lng swapped',
        '991 ถนนพระรามที่ 1 แขวงปทุมวัน เขตปทุมวัน กรุงเทพมหานคร 10330',
        '991 ถนนพระรามที่ 1 แขวงปทุมวัน', 'เขตปทุมวัน', 'กรุงเทพมหานคร', '10330' },
    // ---- edge cases on the address side ----
    // 17. Address in Phuket, pin in Bangkok. Expected: suggestion in Phuket Town (~7.88, 98.39), distance ~690 km
    new List<Object>{ 'GEO-TEST 17 Phuket address Bangkok pin',
        'ถนนถลาง ตำบลตลาดใหญ่ อำเภอเมืองภูเก็ต จังหวัดภูเก็ต 83000',
        'ถนนถลาง ตำบลตลาดใหญ่', 'อำเภอเมืองภูเก็ต', 'จังหวัดภูเก็ต', '83000' },
    // 18. Address and postcode contradict (Bangkok address, Chiang Mai postcode 50000). Pin correct.
    //     Expected: the postcode check rejects matches as "not good", all search steps are tried, and the
    //     best-scored result is used (most likely still Siam Paragon); the probe script shows postcodeMatch=false
    new List<Object>{ 'GEO-TEST 18 Wrong postcode',
        '991 ถนนพระรามที่ 1 แขวงปทุมวัน เขตปทุมวัน กรุงเทพมหานคร 50000',
        '991 ถนนพระรามที่ 1 แขวงปทุมวัน', 'เขตปทุมวัน', 'กรุงเทพมหานคร', '50000' }
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

// ---- Accounts (cases whose Account already exists are skipped) ----
Set<String> existingNames = new Set<String>();
for (Account a : [SELECT Name FROM Account WHERE Name LIKE 'GEO-TEST %']) {
    existingNames.add(a.Name);
}
Map<Schema.SObjectType, Id> lookupCache = new Map<Schema.SObjectType, Id>();
// State and Country/Territory Picklists enabled? Then Account has BillingCountryCode / BillingStateCode.
Boolean statePicklists = Schema.SObjectType.Account.fields.getMap().containsKey('billingcountrycode');
System.debug(LoggingLevel.ERROR, 'State and Country/Territory Picklists: ' + (statePicklists ? 'on' : 'off'));
List<Account> accounts = new List<Account>();
for (List<Object> c : CASES) {
    if (existingNames.contains((String) c[0])) {
        System.debug(LoggingLevel.ERROR, c[0] + ': already exists, skipped');
        continue;
    }
    Account a = new Account(Name = (String) c[0], Address__c = (String) c[1]);
    // Billing Address: UPWARD creates the oggLocation from it
    a.BillingStreet     = (String) c[2];
    a.BillingPostalCode = (String) c[5];
    if (c[1] != null) {
        if (statePicklists) {
            // State/Country picklists: Thai-script province names aren't valid states, so put the province
            // into the city and set only the country code
            a.BillingCity = ((c[3] == null ? '' : (String) c[3]) + ' ' + (c[4] == null ? '' : (String) c[4])).trim();
            a.put('BillingCountryCode', 'TH');
        } else {
            a.BillingCity    = (String) c[3];
            a.BillingState   = (String) c[4];
            a.BillingCountry = 'Thailand';
        }
    }
    for (String field : ACCOUNT_VALUES.keySet()) {
        a.put(field, ACCOUNT_VALUES.get(field));
    }
    fillRequired(a, lookupCache);
    accounts.add(a);
}
insert accounts;

for (Account a : accounts) {
    System.debug(LoggingLevel.ERROR, 'Created ' + a.Name + ' (' + a.Id + ')');
}
System.debug(LoggingLevel.ERROR, 'Created ' + accounts.size() + ' GEO-TEST Accounts. UPWARD creates their oggLocations; '
    + 'check with the query in docs/TESTING_GUIDE.md ("Test data"), then optionally run apply-test-pins.apex.');
