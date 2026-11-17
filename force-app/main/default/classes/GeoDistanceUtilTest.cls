@IsTest
private class GeoDistanceUtilTest {

    @IsTest
    static void oneDegreeOfLongitudeAtEquatorIsAbout111Km() {
        Decimal d = GeoDistanceUtil.distanceInMeters(0, 0, 0, 1);
        // Great-circle distance with mean Earth radius ~ 111.19 km
        Assert.isTrue(d > 111000 && d < 111400, 'Unexpected distance: ' + d);
    }

    @IsTest
    static void bangkokLandmarksDistance() {
        // Grand Palace -> Siam Paragon, roughly 4.7 km apart
        Decimal d = GeoDistanceUtil.distanceInMeters(13.7500, 100.4913, 13.7462, 100.5347);
        Assert.isTrue(d > 4000 && d < 5200, 'Unexpected distance: ' + d);
    }

    @IsTest
    static void samePointIsZero() {
        Assert.isTrue(GeoDistanceUtil.distanceInMeters(13.7563, 100.5018, 13.7563, 100.5018) == 0);
    }

    @IsTest
    static void missingOrInvalidCoordinatesReturnNull() {
        Assert.isNull(GeoDistanceUtil.distanceInMeters(null, 100.5, 13.7, 100.5));
        Assert.isNull(GeoDistanceUtil.distanceInMeters(13.7, 100.5, 13.7, null));
        Assert.isNull(GeoDistanceUtil.distanceInMeters(95, 100.5, 13.7, 100.5));
        Assert.isNull(GeoDistanceUtil.distanceInMeters(13.7, 190, 13.7, 100.5));
    }

    @IsTest
    static void toDecimalHandlesTypes() {
        Assert.areEqual(1.5, GeoDistanceUtil.toDecimal(1.5));
        Assert.isTrue(GeoDistanceUtil.toDecimal(2) == 2);
        Assert.areEqual(13.75, GeoDistanceUtil.toDecimal(' 13.75 '));
        Assert.isNull(GeoDistanceUtil.toDecimal('abc'));
        Assert.isNull(GeoDistanceUtil.toDecimal(''));
        Assert.isNull(GeoDistanceUtil.toDecimal(null));
    }
}
