public without sharing class ThaiAddressNormalizer {

    public class PreparedAddress {
        public String original;
        public String normalized;
        public String withoutUnit;
        public String streetLevel;
        public String postcode;

        /** Distinct, non-blank query variants in the order they should be tried with the Geocoding API. */
        public List<String> geocodingQueries() {
            List<String> result = new List<String>();
            for (String q : new List<String>{ withoutUnit, streetLevel }) {
                if (String.isNotBlank(q) && !result.contains(q)) {
                    result.add(q);
                }
            }
            return result;
        }
    }

    private static final String THAI_DIGITS = '๐๑๒๓๔๕๖๗๘๙';

    // Room / unit. Thai keyword allows a list "91,96" or "91, 96"; English keywords take a single token
    // so "Room 1203, 12th Floor, 999 Rama I Rd" does not swallow the house number.
    @TestVisible private static final String ROOM_PATTERN =
          '(?:ห้อง(?:เลขที่)?|ยูนิต)\\s*[0-9A-Za-z][0-9A-Za-z/\\-]*(?:\\s*,\\s*[0-9A-Za-z][0-9A-Za-z/\\-]*)*'
        + '|(?i:room|unit|suite)\\s*[0-9A-Za-z][0-9A-Za-z/\\-]*';

    // Floor: "ชั้น 9", "ชั้นที่ 9-10", "ชั้น 2, 3", "Floor 9", "Fl. 9", "12th Floor".
    // "ชั้น" followed by Thai letters (e.g. ชั้นนำ) is not matched.
    @TestVisible private static final String FLOOR_PATTERN =
          'ชั้น(?:ที่)?\\s*[0-9A-Za-z][0-9A-Za-z\\-]*(?:\\s*,\\s*[0-9A-Za-z][0-9A-Za-z\\-]*)*'
        + '|(?i:floor|fl\\.)\\s*[0-9A-Za-z][0-9A-Za-z\\-]*'
        + '|(?i:\\d+(?:st|nd|rd|th)\\s+floor)';

    // Building name: from อาคาร/ตึก up to the next address component or a house number.
    @TestVisible private static final String BUILDING_PATTERN =
        '(?:อาคาร|ตึก)\\s*\\S.*?(?=\\s(?:\\d|ถนน|ซอย|หมู่|แขวง|ตำบล|เขต|อำเภอ|จังหวัด|กรุงเทพ)|$)';

    private static final Pattern POSTCODE = Pattern.compile('(?<!\\d)\\d{5}(?!\\d)');

    public static PreparedAddress prepare(String address) {
        PreparedAddress p = new PreparedAddress();
        p.original = address;
        if (String.isBlank(address)) {
            return p;
        }
        p.normalized  = normalize(address);
        p.withoutUnit = tidy(p.normalized
            .replaceAll(ROOM_PATTERN, ' ')
            .replaceAll(FLOOR_PATTERN, ' ')
            .replaceAll('เลขที่\\s*(?=\\d)', ''));
        p.streetLevel = tidy(p.withoutUnit.replaceAll(BUILDING_PATTERN, ' '));
        p.postcode    = extractPostcode(p.normalized);

        // Safety net: never send an empty query because a pattern removed everything.
        if (String.isBlank(p.withoutUnit)) {
            p.withoutUnit = p.normalized;
        }
        if (String.isBlank(p.streetLevel)) {
            p.streetLevel = p.withoutUnit;
        }
        return p;
    }

    /** Thai digits -> Arabic digits, expand common abbreviations, collapse whitespace. */
    public static String normalize(String address) {
        if (address == null) {
            return null;
        }
        String s = address;
        for (Integer i = 0; i < 10; i++) {
            s = s.replace(THAI_DIGITS.substring(i, i + 1), String.valueOf(i));
        }
        s = s.replaceAll('[\\r\\n\\t]+', ' ')
             .replaceAll('(^|\\s)ถ\\.\\s*', '$1ถนน')
             .replaceAll('(^|\\s)ซ\\.\\s*', '$1ซอย')
             .replaceAll('(^|\\s)ต\\.\\s*', '$1ตำบล')
             .replaceAll('(^|\\s)อ\\.\\s*', '$1อำเภอ')
             .replaceAll('(^|\\s)จ\\.\\s*', '$1จังหวัด')
             .replaceAll('(^|\\s)ม\\.\\s*', '$1หมู่ ')
             .replaceAll('กทม\\.?|กรุงเทพฯ', 'กรุงเทพมหานคร');
        return tidy(s);
    }

    /** Last 5-digit number in the address (Thai postcodes are at the end), or null. */
    public static String extractPostcode(String address) {
        if (String.isBlank(address)) {
            return null;
        }
        Matcher m = POSTCODE.matcher(address);
        String last = null;
        while (m.find()) {
            last = m.group();
        }
        return last;
    }

    private static String tidy(String s) {
        if (s == null) {
            return null;
        }
        s = s.replaceAll('\\s+', ' ').trim();
        s = s.replaceAll('(\\s*,)+\\s*', ', ');
        s = s.replaceAll('^[,\\s]+|[,\\s]+$', '');
        return s;
    }
}
