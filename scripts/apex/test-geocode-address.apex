// Calls Google directly (no DML) to check the API key / settings and see what Google returns.
// Run:  sf apex run --file scripts/apex/test-geocode-address.apex --target-org <alias>
String address = '991 Rama I Rd, Pathum Wan, Bangkok 10330'; // <-- change me
GoogleGeocodingService.GeocodeResult r = new GoogleGeocodingService().findCoordinates(address);
if (r == null) {
    System.debug(LoggingLevel.ERROR, 'NO RESULT for: ' + address);
} else {
    System.debug(LoggingLevel.ERROR, 'source=' + r.source + ' lat=' + r.latitude + ' lng=' + r.longitude
        + ' locationType=' + r.locationType + ' partialMatch=' + r.partialMatch
        + ' formatted=' + r.formattedAddress);
}
