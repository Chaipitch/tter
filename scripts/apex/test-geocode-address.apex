// Calls the configured provider (Google or OpenStreetMap) directly, without DML, to check the settings
// and see what comes back for one address.
// Run:  sf apex run --file scripts/apex/test-geocode-address.apex --target-org tterakit-sb
String address = '622 อาคารเอ็มโพเรียม ทาวเวอร์ ห้องเลขที่ 91,96 ชั้นที่ 9 ถนนสุขุมวิท แขวงคลองตัน เขตคลองเตย กรุงเทพมหานคร 10110'; // <-- change me

System.debug(LoggingLevel.ERROR, 'provider    = ' + (GoogleMapsSettings.useOpenStreetMap() ? 'OpenStreetMap' : 'Google'));
ThaiAddressNormalizer.PreparedAddress p = ThaiAddressNormalizer.prepare(address);
System.debug(LoggingLevel.ERROR, 'withoutUnit = ' + p.withoutUnit);
System.debug(LoggingLevel.ERROR, 'streetLevel = ' + p.streetLevel);
System.debug(LoggingLevel.ERROR, 'postcode    = ' + p.postcode);

GoogleGeocodingService.GeocodeResult r = new GoogleGeocodingService().findCoordinates(address);
if (r == null) {
    System.debug(LoggingLevel.ERROR, 'NO RESULT for: ' + address);
} else {
    System.debug(LoggingLevel.ERROR, 'source=' + r.source + ' lat=' + r.latitude + ' lng=' + r.longitude
        + ' locationType=' + r.locationType + ' partialMatch=' + r.partialMatch
        + ' postcode=' + r.postcode + ' postcodeMatch=' + r.postcodeMatch + ' query=' + r.query
        + ' formatted=' + r.formattedAddress);
}
