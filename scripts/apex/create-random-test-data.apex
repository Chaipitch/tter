// Creates EXTRA random test Accounts for the location lookup, with obscure, messy business addresses inside and
// outside Bangkok. It never changes existing records: every run adds new Accounts named
// "GEO-TEST R<run stamp>-NN [variations]".
//
//  - Addresses use REAL sub-districts, districts, provinces, postcodes and roads, with made-up house numbers,
//    sois, villages, buildings, market stalls and warehouses. There is no exact "right" pin: this tests how
//    the lookup copes with ordinary, obscure business addresses.
//  - Random variations (shown in the name):
//        abbr     abbreviations (ถ. ซ. ม. ต. อ. จ. กทม. / กรุงเทพฯ)   thai     Thai digits
//        floor    floor + room                                         eng      English "Unit ..., ...th Floor," prefix
//        nopc     postcode left out                                    comma    parts separated by commas
//        nospace  parts run together without spaces
//  - The address goes into both Address__c (used by the lookup) and the Billing Address (used by UPWARD to
//    create the oggLocation). The oggLocations are left to UPWARD; the on-create trigger then looks them up.
//  - Required Account fields are filled automatically; set specific values in ACCOUNT_VALUES if needed.
//  - Remove them (with all other GEO-TEST data) with scripts/apex/delete-test-data.apex.
//
// Run:  sf apex run --file scripts/apex/create-random-test-data.apex --target-org tterakit-sb

Integer RECORD_COUNT           = 20;   // how many Accounts to create in this run
Integer INSIDE_BANGKOK_PERCENT = 50;   // chance that an Account is in Bangkok (the rest: outside Bangkok)
Integer VARIATION_PERCENT      = 30;   // chance for each variation

Map<String, Object> ACCOUNT_VALUES = new Map<String, Object>{
    // 'Tax_ID__c' => '0105556000000',
    // 'Customer_Type__c' => 'Corporate'
};

// { region, subdistrict, district, province, postcode, roads (| separated, without ถนน) }
List<List<String>> BANGKOK = new List<List<String>>{
    new List<String>{ 'BKK', 'บางนาเหนือ', 'บางนา', 'กรุงเทพมหานคร', '10260', 'สุขุมวิท|บางนา-ตราด' },
    new List<String>{ 'BKK', 'บางซื่อ', 'บางซื่อ', 'กรุงเทพมหานคร', '10800', 'ประชาราษฎร์สาย 2|เตชะวณิช' },
    new List<String>{ 'BKK', 'คลองจั่น', 'บางกะปิ', 'กรุงเทพมหานคร', '10240', 'นวมินทร์|เสรีไทย|ลาดพร้าว' },
    new List<String>{ 'BKK', 'หนองแขม', 'หนองแขม', 'กรุงเทพมหานคร', '10160', 'เพชรเกษม' },
    new List<String>{ 'BKK', 'ลาดกระบัง', 'ลาดกระบัง', 'กรุงเทพมหานคร', '10520', 'ฉลองกรุง|ลาดกระบัง' },
    new List<String>{ 'BKK', 'มีนบุรี', 'มีนบุรี', 'กรุงเทพมหานคร', '10510', 'สีหบุรานุกิจ|รามอินทรา' },
    new List<String>{ 'BKK', 'บางพลัด', 'บางพลัด', 'กรุงเทพมหานคร', '10700', 'จรัญสนิทวงศ์' },
    new List<String>{ 'BKK', 'สัมพันธวงศ์', 'สัมพันธวงศ์', 'กรุงเทพมหานคร', '10100', 'เยาวราช|ทรงวาด' },
    new List<String>{ 'BKK', 'วังทองหลาง', 'วังทองหลาง', 'กรุงเทพมหานคร', '10310', 'ลาดพร้าว' },
    new List<String>{ 'BKK', 'ท่าข้าม', 'บางขุนเทียน', 'กรุงเทพมหานคร', '10150', 'พระรามที่ 2' },
    new List<String>{ 'BKK', 'หลักสอง', 'บางแค', 'กรุงเทพมหานคร', '10160', 'เพชรเกษม' },
    new List<String>{ 'BKK', 'ทุ่งวัดดอน', 'สาทร', 'กรุงเทพมหานคร', '10120', 'เจริญราษฎร์|จันทน์' },
    new List<String>{ 'BKK', 'สามเสนนอก', 'ห้วยขวาง', 'กรุงเทพมหานคร', '10310', 'ประชาราษฎร์บำเพ็ญ|สุทธิสารวินิจฉัย' }
};
List<List<String>> OUTSIDE_BANGKOK = new List<List<String>>{
    new List<String>{ 'UPC', 'บางปูใหม่', 'เมืองสมุทรปราการ', 'สมุทรปราการ', '10280', 'สุขุมวิท' },
    new List<String>{ 'UPC', 'บ้านเลน', 'บางปะอิน', 'พระนครศรีอยุธยา', '13160', 'อุดมสรยุทธ์' },
    new List<String>{ 'UPC', 'คลองหนึ่ง', 'คลองหลวง', 'ปทุมธานี', '12120', 'พหลโยธิน' },
    new List<String>{ 'UPC', 'บ่อวิน', 'ศรีราชา', 'ชลบุรี', '20230', 'ทางหลวงหมายเลข 331' },
    new List<String>{ 'UPC', 'มาบตาพุด', 'เมืองระยอง', 'ระยอง', '21150', 'สุขุมวิท' },
    new List<String>{ 'UPC', 'อ้อมน้อย', 'กระทุ่มแบน', 'สมุทรสาคร', '74130', 'เพชรเกษม' },
    new List<String>{ 'UPC', 'ท่าทราย', 'เมืองสมุทรสาคร', 'สมุทรสาคร', '74000', 'เศรษฐกิจ 1' },
    new List<String>{ 'UPC', 'หนองหาร', 'สันทราย', 'เชียงใหม่', '50290', 'เชียงใหม่-แม่โจ้' },
    new List<String>{ 'UPC', 'สันกำแพง', 'สันกำแพง', 'เชียงใหม่', '50130', 'เชียงใหม่-สันกำแพง' },
    new List<String>{ 'UPC', 'ในเมือง', 'เมืองขอนแก่น', 'ขอนแก่น', '40000', 'มิตรภาพ|หน้าเมือง' },
    new List<String>{ 'UPC', 'หาดใหญ่', 'หาดใหญ่', 'สงขลา', '90110', 'เพชรเกษม|นิพัทธ์อุทิศ 3' },
    new List<String>{ 'UPC', 'กะทู้', 'กะทู้', 'ภูเก็ต', '83120', 'วิชิตสงคราม' },
    new List<String>{ 'UPC', 'หนองปรือ', 'บางละมุง', 'ชลบุรี', '20150', 'สุขุมวิท|เทพประสิทธิ์' },
    new List<String>{ 'UPC', 'ในเมือง', 'เมืองนครราชสีมา', 'นครราชสีมา', '30000', 'มิตรภาพ|จอมพล' },
    new List<String>{ 'UPC', 'หมากแข้ง', 'เมืองอุดรธานี', 'อุดรธานี', '41000', 'โพศรี|อุดรดุษฎี' },
    new List<String>{ 'UPC', 'เวียง', 'เมืองเชียงราย', 'เชียงราย', '57000', 'พหลโยธิน|บรรพปราการ' },
    new List<String>{ 'UPC', 'ตลาด', 'เมืองสุราษฎร์ธานี', 'สุราษฎร์ธานี', '84000', 'ตลาดใหม่|ชนเกษม' },
    new List<String>{ 'UPC', 'บ้านใหม่', 'ปากเกร็ด', 'นนทบุรี', '11120', 'แจ้งวัฒนะ' }
};

// ---- parts for messy addresses ----
List<String> SOI_NAMES   = new List<String>{ 'ร่วมใจ', 'สุขใจ', 'วัดใหม่', 'ประชาร่วมใจ', 'เทศบาล 3', 'ร่วมมิตร' };
List<String> VILLAGES    = new List<String>{ 'หมู่บ้านพฤกษาวิลล์ 12', 'หมู่บ้านทวีสุข', 'หมู่บ้านชัยพฤกษ์', 'หมู่บ้านบ้านสวนเกษตร',
    'หมู่บ้านเอื้ออาทร', 'หมู่บ้านสินทรัพย์นคร' };
List<String> BUILDINGS   = new List<String>{ 'อาคารสินธรพลาซ่า', 'อาคารเจริญกิจ', 'อาคารพาณิชย์โชคชัย', 'ตึกแถวสามัคคี' };
List<String> MARKETS     = new List<String>{ 'ตลาดสดเทศบาล', 'ตลาดนัดสี่แยก', 'ตลาดเช้าบ้านใหม่' };

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

String oneOf(List<String> values) {
    return values[pick(values.size())];
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

String joinParts(List<String> parts, String separator) {
    List<String> kept = new List<String>();
    for (String p : parts) {
        if (String.isNotBlank(p)) {
            kept.add(p.trim());
        }
    }
    return String.join(kept, separator);
}

Map<Schema.SObjectType, Id> lookupCache = new Map<Schema.SObjectType, Id>();
Boolean statePicklists = Schema.SObjectType.Account.fields.getMap().containsKey('billingcountrycode');
String stamp = Datetime.now().format('yyMMddHHmmss');
List<Account> accounts = new List<Account>();
Integer inside = 0;

for (Integer n = 1; n <= RECORD_COUNT; n++) {
    Boolean bkk = chance(INSIDE_BANGKOK_PERCENT);
    List<String> area = bkk ? BANGKOK[pick(BANGKOK.size())] : OUTSIDE_BANGKOK[pick(OUTSIDE_BANGKOK.size())];
    if (bkk) {
        inside++;
    }

    // ---- variations ----
    Boolean abbr    = chance(VARIATION_PERCENT);
    Boolean thai    = chance(VARIATION_PERCENT);
    Boolean floor   = chance(VARIATION_PERCENT);
    Boolean eng     = !floor && chance(VARIATION_PERCENT / 2);
    Boolean nopc    = chance(VARIATION_PERCENT / 2);
    Boolean comma   = chance(VARIATION_PERCENT / 2);
    Boolean nospace = !comma && chance(VARIATION_PERCENT / 3);

    // ---- messy address ----
    Integer floorNo = 2 + pick(15);
    String room = String.valueOf(floorNo) + String.valueOf(1 + pick(20)).leftPad(2, '0');
    String houseNo = String.valueOf(1 + pick(999)) + (chance(40) ? '/' + String.valueOf(1 + pick(150)) : '');
    String moo = (!bkk && chance(60)) ? (abbr ? 'ม.' : 'หมู่ ') + String.valueOf(1 + pick(12)) : null;
    String village = chance(25) ? oneOf(VILLAGES) : null;
    String place = null;
    Integer kind = pick(10);
    if (kind == 0) {
        place = oneOf(MARKETS) + ' แผงที่ ' + String.valueOf(1 + pick(200));
    } else if (kind == 1 && !bkk) {
        place = 'โกดัง ' + String.valueOf(1 + pick(30));
    } else if (kind == 2) {
        place = oneOf(BUILDINGS);
    }
    String noise = floor ? 'ชั้น ' + floorNo + ' ห้อง ' + room : null;
    String prefix = eng ? 'Unit ' + room + ', ' + floorNo + 'th Floor,' : null;
    List<String> roads = area[5].split('\\|');
    String roadName = roads[pick(roads.size())];
    String soi = null;
    if (chance(50)) {
        soi = (abbr ? 'ซ.' : 'ซอย') + (chance(50) ? roadName + ' ' + String.valueOf(1 + pick(120)) : oneOf(SOI_NAMES));
    }
    String road = (abbr ? 'ถ.' : 'ถนน') + roadName;
    String sub  = bkk ? 'แขวง' + area[1] : (abbr ? 'ต.' : 'ตำบล') + area[1];
    String dist = bkk ? 'เขต' + area[2] : (abbr ? 'อ.' : 'อำเภอ') + area[2];
    String prov = bkk ? (abbr ? (chance(50) ? 'กทม.' : 'กรุงเทพฯ') : 'กรุงเทพมหานคร')
                      : (abbr ? 'จ.' : 'จังหวัด') + area[3];
    String postcode = nopc ? null : area[4];

    String separator = comma ? ', ' : (nospace ? '' : ' ');
    String street = joinParts(new List<String>{ prefix, houseNo, moo, village, place, noise, soi, road, sub }, separator);
    if (thai) {
        street = thaiDigits(street);
        dist = thaiDigits(dist);
        postcode = thaiDigits(postcode);
    }
    String fullAddress = joinParts(new List<String>{ street, dist, prov, postcode }, separator);

    List<String> tags = new List<String>{ bkk ? 'BKK' : 'UPC' };
    if (abbr)    { tags.add('abbr'); }
    if (thai)    { tags.add('thai'); }
    if (floor)   { tags.add('floor'); }
    if (eng)     { tags.add('eng'); }
    if (nopc)    { tags.add('nopc'); }
    if (comma)   { tags.add('comma'); }
    if (nospace) { tags.add('nospace'); }

    Account a = new Account(
        Name = 'GEO-TEST R' + stamp + '-' + String.valueOf(n).leftPad(2, '0') + ' [' + String.join(tags, ',') + ']',
        Address__c = fullAddress,
        BillingStreet = street,
        BillingPostalCode = postcode);
    if (statePicklists) {
        a.BillingCity = joinParts(new List<String>{ dist, prov }, ' ');
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
