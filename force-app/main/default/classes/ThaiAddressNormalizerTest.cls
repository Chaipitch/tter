@IsTest
private class ThaiAddressNormalizerTest {

    @IsTest
    static void emporiumTowerExample() {
        ThaiAddressNormalizer.PreparedAddress p = ThaiAddressNormalizer.prepare(
            '622 อาคารเอ็มโพเรียม ทาวเวอร์ ห้องเลขที่ 91,96 ชั้นที่ 9 ถนนสุขุมวิท แขวงคลองตัน เขตคลองเตย กรุงเทพมหานคร 10110');

        Assert.areEqual('622 อาคารเอ็มโพเรียม ทาวเวอร์ ถนนสุขุมวิท แขวงคลองตัน เขตคลองเตย กรุงเทพมหานคร 10110', p.withoutUnit);
        Assert.areEqual('622 ถนนสุขุมวิท แขวงคลองตัน เขตคลองเตย กรุงเทพมหานคร 10110', p.streetLevel);
        Assert.areEqual('10110', p.postcode);
        Assert.areEqual(2, p.geocodingQueries().size());
    }

    @IsTest
    static void thaiDigitsAndAbbreviations() {
        ThaiAddressNormalizer.PreparedAddress p = ThaiAddressNormalizer.prepare(
            'เลขที่ ๙๙/๑ ม.๓ ต.บางพูด อ.ปากเกร็ด จ.นนทบุรี ๑๑๑๒๐');

        Assert.areEqual('เลขที่ 99/1 หมู่ 3 ตำบลบางพูด อำเภอปากเกร็ด จังหวัดนนทบุรี 11120', p.normalized);
        Assert.areEqual('99/1 หมู่ 3 ตำบลบางพูด อำเภอปากเกร็ด จังหวัดนนทบุรี 11120', p.withoutUnit);
        Assert.areEqual('11120', p.postcode);
        Assert.areEqual(1, p.geocodingQueries().size(), 'Identical variants must not be queried twice');
    }

    @IsTest
    static void bangkokAbbreviations() {
        Assert.areEqual('1 ซอยสุขุมวิท 24 ถนนสุขุมวิท คลองตัน คลองเตย กรุงเทพมหานคร 10110',
            ThaiAddressNormalizer.normalize('1 ซ.สุขุมวิท 24 ถ.สุขุมวิท คลองตัน คลองเตย กทม. 10110'));
        Assert.areEqual('98 ถนนสาทรเหนือ กรุงเทพมหานคร 10500',
            ThaiAddressNormalizer.normalize('98 ถนนสาทรเหนือ  กรุงเทพฯ\n10500'));
    }

    @IsTest
    static void buildingBeforeHouseNumber() {
        ThaiAddressNormalizer.PreparedAddress p = ThaiAddressNormalizer.prepare(
            'อาคารสาทรสแควร์ ชั้น 20 98 ถนนสาทรเหนือ แขวงสีลม เขตบางรัก กรุงเทพฯ 10500');

        Assert.areEqual('อาคารสาทรสแควร์ 98 ถนนสาทรเหนือ แขวงสีลม เขตบางรัก กรุงเทพมหานคร 10500', p.withoutUnit);
        Assert.areEqual('98 ถนนสาทรเหนือ แขวงสีลม เขตบางรัก กรุงเทพมหานคร 10500', p.streetLevel);
    }

    @IsTest
    static void englishUnitsKeepHouseNumber() {
        ThaiAddressNormalizer.PreparedAddress p = ThaiAddressNormalizer.prepare(
            'Room 1203, 12th Floor, 999 Rama I Rd, Bangkok 10330');
        Assert.areEqual('999 Rama I Rd, Bangkok 10330', p.withoutUnit);
        Assert.areEqual('10330', p.postcode);
    }

    @IsTest
    static void wordsStartingWithChanAreKept() {
        // "ชั้นนำ" (leading) and "ห้องสมุด" (library) are not floor / room numbers
        String s = ThaiAddressNormalizer.prepare('ห้องสมุดชั้นนำ 5 ถนนพระราม 4 กรุงเทพมหานคร').withoutUnit;
        Assert.areEqual('ห้องสมุดชั้นนำ 5 ถนนพระราม 4 กรุงเทพมหานคร', s);
    }

    @IsTest
    static void blankAndNoPostcode() {
        ThaiAddressNormalizer.PreparedAddress p = ThaiAddressNormalizer.prepare('  ');
        Assert.isTrue(p.geocodingQueries().isEmpty());
        Assert.isNull(ThaiAddressNormalizer.extractPostcode('ถนนสุขุมวิท กรุงเทพมหานคร'));
        Assert.isNull(ThaiAddressNormalizer.normalize(null));
    }
}
