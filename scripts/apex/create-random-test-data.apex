// Creates EXTRA random test Accounts for the location lookup, inside and outside Bangkok. It never changes
// existing records: every run adds new Accounts named "GEO-TEST R<run stamp>-NN <BKK|UPC> <place> [variations]".
//
//  - Each Account gets a real, well-known address (13 in Bangkok, 13 upcountry / Bangkok metro provinces), so
//    the results can be checked in Google Maps, written in a randomly varied way:
//        abbr   abbreviations (ถ. ม. ต. อ. จ. กทม. / กรุงเทพฯ)      thai   Thai digits
//        floor  floor + room added ("ชั้น 12 ห้อง 1203")             eng    English "Unit 5A, 12th Floor," prefix
//        nopc   postcode left out
//  - The address goes into both Address__c (used by the lookup) and the Billing Address (used by UPWARD to
//    create the oggLocation), like create-test-data.apex. The oggLocations are left to UPWARD; the on-create
//    trigger then looks them up.
//  - Required Account fields are filled automatically (see create-test-data.apex); set specific values in
//    ACCOUNT_VALUES if a validation rule needs them.
//  - Remove them (with all other GEO-TEST data) with scripts/apex/delete-test-data.apex.
//
// Run:  sf apex run --file scripts/apex/create-random-test-data.apex --target-org tterakit-sb

Integer RECORD_COUNT          = 20;    // how many Accounts to create in this run
Integer INSIDE_BANGKOK_PERCENT = 50;   // chance that an Account is in Bangkok (the rest: outside Bangkok)
Integer VARIATION_PERCENT      = 30;   // chance for each variation (abbr / thai / floor / eng / nopc)

Map<String, Object> ACCOUNT_VALUES = new Map<String, Object>{
    // 'Tax_ID__c' => '0105556000000',
    // 'Customer_Type__c' => 'Corporate'
};

// { region, label, house no, moo, road (without ถนน), subdistrict, district, province, postcode }
List<List<String>> BANGKOK = new List<List<String>>{
    new List<String>{ 'BKK', 'CentralWorld', '999/9', '', 'พระรามที่ 1', 'ปทุมวัน', 'ปทุมวัน', 'กรุงเทพมหานคร', '10330' },
    new List<String>{ 'BKK', 'Siam Paragon', '991', '', 'พระรามที่ 1', 'ปทุมวัน', 'ปทุมวัน', 'กรุงเทพมหานคร', '10330' },
    new List<String>{ 'BKK', 'Emporium', '622', '', 'สุขุมวิท', 'คลองตัน', 'คลองเตย', 'กรุงเทพมหานคร', '10110' },
    new List<String>{ 'BKK', 'Silom Complex', '191', '', 'สีลม', 'สีลม', 'บางรัก', 'กรุงเทพมหานคร', '10500' },
    new List<String>{ 'BKK', 'Central Ladprao', '1693', '', 'พหลโยธิน', 'จตุจักร', 'จตุจักร', 'กรุงเทพมหานคร', '10900' },
    new List<String>{ 'BKK', 'Central Chidlom', '1027', '', 'เพลินจิต', 'ลุมพินี', 'ปทุมวัน', 'กรุงเทพมหานคร', '10330' },
    new List<String>{ 'BKK', 'ICONSIAM', '299', '', 'เจริญนคร', 'คลองต้นไทร', 'คลองสาน', 'กรุงเทพมหานคร', '10600' },
    new List<String>{ 'BKK', 'Grand Palace', '', '', 'หน้าพระลาน', 'พระบรมมหาราชวัง', 'พระนคร', 'กรุงเทพมหานคร', '10200' },
    new List<String>{ 'BKK', 'Chatuchak Market', '587/10', '', 'กำแพงเพชร 2', 'จตุจักร', 'จตุจักร', 'กรุงเทพมหานคร', '10900' },
    new List<String>{ 'BKK', 'Seacon Square', '55', '', 'ศรีนครินทร์', 'หนองบอน', 'ประเวศ', 'กรุงเทพมหานคร', '10250' },
    new List<String>{ 'BKK', 'Terminal 21', '88', '', 'สุขุมวิท', 'คลองเตยเหนือ', 'วัฒนา', 'กรุงเทพมหานคร', '10110' },
    new List<String>{ 'BKK', 'Don Mueang Airport', '222', '', 'วิภาวดีรังสิต', 'สนามบิน', 'ดอนเมือง', 'กรุงเทพมหานคร', '10210' },
    new List<String>{ 'BKK', 'Fashion Island', '587', '', 'รามอินทรา', 'คันนายาว', 'คันนายาว', 'กรุงเทพมหานคร', '10230' }
};
List<List<String>> OUTSIDE_BANGKOK = new List<List<String>>{
    new List<String>{ 'UPC', 'Central Festival Chiang Mai', '99/3', '4', 'ซุปเปอร์ไฮเวย์เชียงใหม่-ลำปาง', 'ฟ้าฮ่าม', 'เมืองเชียงใหม่', 'เชียงใหม่', '50000' },
    new List<String>{ 'UPC', 'MAYA Chiang Mai', '55', '', 'ห้วยแก้ว', 'ช้างเผือก', 'เมืองเชียงใหม่', 'เชียงใหม่', '50300' },
    new List<String>{ 'UPC', 'Central Phuket', '74', '5', 'วิชิตสงคราม', 'วิชิต', 'เมืองภูเก็ต', 'ภูเก็ต', '83000' },
    new List<String>{ 'UPC', 'Central Pattaya', '333/99', '9', 'พัทยาสาย 2', 'หนองปรือ', 'บางละมุง', 'ชลบุรี', '20150' },
    new List<String>{ 'UPC', 'Central Khon Kaen', '99', '', 'ศรีจันทร์', 'ในเมือง', 'เมืองขอนแก่น', 'ขอนแก่น', '40000' },
    new List<String>{ 'UPC', 'Central Hat Yai', '1518', '', 'กาญจนวณิชย์', 'หาดใหญ่', 'หาดใหญ่', 'สงขลา', '90110' },
    new List<String>{ 'UPC', 'Mega Bangna', '39', '6', 'บางนา-ตราด', 'บางแก้ว', 'บางพลี', 'สมุทรปราการ', '10540' },
    new List<String>{ 'UPC', 'Future Park Rangsit', '94', '', 'พหลโยธิน', 'ประชาธิปัตย์', 'ธัญบุรี', 'ปทุมธานี', '12130' },
    new List<String>{ 'UPC', 'Central Westgate', '199', '6', 'กาญจนาภิเษก', 'เสาธงหิน', 'บางใหญ่', 'นนทบุรี', '11140' },
    new List<String>{ 'UPC', 'Terminal 21 Korat', '99', '', 'มิตรภาพ-หนองคาย', 'ในเมือง', 'เมืองนครราชสีมา', 'นครราชสีมา', '30000' },
    new List<String>{ 'UPC', 'Wat Mahathat Ayutthaya', '', '', 'นเรศวร', 'ท่าวาสุกรี', 'พระนครศรีอยุธยา', 'พระนครศรีอยุธยา', '13000' },
    new List<String>{ 'UPC', 'Hua Hin Station', '', '', 'ดำเนินเกษม', 'หัวหิน', 'หัวหิน', 'ประจวบคีรีขันธ์', '77110' },
    new List<String>{ 'UPC', 'Central Udon Thani', '277/1', '', 'ประจักษ์ศิลปาคม', 'หมากแข้ง', 'เมืองอุดรธานี', 'อุดรธานี', '41000' }
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


Boolean chance(Integer percent) {
    return Math.random() * 100 < percent;
}

Integer pick(Integer size) {
    return Math.mod(Math.abs(Crypto.getRandomInteger()), size);
}

String thaiDigits(String s) {
    if (s == null) {
        return null;
    }
    List<String> digits = new List<String>{ '๐', '๑', '๒', '๓', '๔', '๕', '๖', '๗', '๘', '๙' };
    for (Integer d = 0; d < 10; d++) {
        s = s.replace(String.valueOf(d), digits[d]);
    }
    return s;
}

String joinParts(List<String> parts) {
    List<String> kept = new List<String>();
    for (String p : parts) {
        if (String.isNotBlank(p)) {
            kept.add(p.trim());
        }
    }
    return String.join(kept, ' ');
}

Map<Schema.SObjectType, Id> lookupCache = new Map<Schema.SObjectType, Id>();
Boolean statePicklists = Schema.SObjectType.Account.fields.getMap().containsKey('billingcountrycode');
String stamp = Datetime.now().format('yyMMddHHmmss');
List<Account> accounts = new List<Account>();
Integer inside = 0;

for (Integer n = 1; n <= RECORD_COUNT; n++) {
    Boolean bkk = chance(INSIDE_BANGKOK_PERCENT);
    List<String> p = bkk ? BANGKOK[pick(BANGKOK.size())] : OUTSIDE_BANGKOK[pick(OUTSIDE_BANGKOK.size())];
    if (bkk) {
        inside++;
    }

    Boolean abbr  = chance(VARIATION_PERCENT);
    Boolean thai  = chance(VARIATION_PERCENT);
    Boolean floor = chance(VARIATION_PERCENT);
    Boolean eng   = !floor && chance(VARIATION_PERCENT / 2);
    Boolean nopc  = chance(VARIATION_PERCENT / 2);

    Integer floorNo = 2 + pick(30);
    String room = String.valueOf(floorNo) + String.valueOf(1 + pick(9)).leftPad(2, '0');

    String houseNo = p[2];
    String moo = String.isBlank(p[3]) ? null : (abbr ? 'ม.' : 'หมู่ ') + p[3];
    String noise = floor ? 'ชั้น ' + floorNo + ' ห้อง ' + room : null;
    String prefix = eng ? 'Unit ' + room + ', ' + floorNo + 'th Floor,' : null;
    String road = (abbr ? 'ถ.' : 'ถนน') + p[4];
    String sub  = bkk ? 'แขวง' + p[5] : (abbr ? 'ต.' : 'ตำบล') + p[5];
    String dist = bkk ? 'เขต' + p[6] : (abbr ? 'อ.' : 'อำเภอ') + p[6];
    String prov = bkk ? (abbr ? (chance(50) ? 'กทม.' : 'กรุงเทพฯ') : 'กรุงเทพมหานคร')
                      : (abbr ? 'จ.' : 'จังหวัด') + p[7];
    String postcode = nopc ? null : p[8];

    String street = joinParts(new List<String>{ prefix, houseNo, moo, noise, road, sub });
    if (thai) {
        street = thaiDigits(street);
        dist = thaiDigits(dist);
        postcode = thaiDigits(postcode);
    }
    String fullAddress = joinParts(new List<String>{ street, dist, prov, postcode });

    List<String> tags = new List<String>();
    if (abbr)  { tags.add('abbr'); }
    if (thai)  { tags.add('thai'); }
    if (floor) { tags.add('floor'); }
    if (eng)   { tags.add('eng'); }
    if (nopc)  { tags.add('nopc'); }

    Account a = new Account(
        Name = 'GEO-TEST R' + stamp + '-' + String.valueOf(n).leftPad(2, '0') + ' ' + p[0] + ' ' + p[1]
            + (tags.isEmpty() ? '' : ' [' + String.join(tags, ',') + ']'),
        Address__c = fullAddress,
        BillingStreet = street,
        BillingPostalCode = postcode);
    if (statePicklists) {
        a.BillingCity = joinParts(new List<String>{ dist, prov });
        a.put('BillingCountryCode', 'TH');
    } else {
        a.BillingCity = dist;
        a.BillingState = prov;
        a.BillingCountry = 'Thailand';
    }
    for (String field : ACCOUNT_VALUES.keySet()) {
        a.put(field, ACCOUNT_VALUES.get(field));
    }
    fillRequired(a, lookupCache);
    accounts.add(a);
}
insert accounts;

for (Account a : accounts) {
    System.debug(LoggingLevel.ERROR, a.Name + '  |  ' + a.Address__c);
}
System.debug(LoggingLevel.ERROR, 'Created ' + accounts.size() + ' random GEO-TEST Accounts (run R' + stamp + '): '
    + inside + ' in Bangkok, ' + (accounts.size() - inside) + ' outside. State/Country picklists: '
    + (statePicklists ? 'on' : 'off') + '. UPWARD creates their oggLocations; the trigger looks them up.');
