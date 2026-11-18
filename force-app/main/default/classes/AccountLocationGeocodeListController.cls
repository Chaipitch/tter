/**
 * Controller extension for the list view button "Suggest Locations (Google)"
 * (Visualforce page AccountLocationGeocodeList).
 *
 *  - records ticked in the list view  -> geocode those records
 *  - nothing ticked                   -> geocode all records not processed yet (isCoordsUpdated__c = false)
 *
 * Starts AccountLocationGeocodeBatch and shows the job Id; progress is in Setup -> Apex Jobs.
 */
public with sharing class AccountLocationGeocodeListController {

    private final ApexPages.StandardSetController setController;
    private final Set<Id> selectedIds = new Set<Id>();

    public Integer selectedCount { get; private set; }
    public Boolean started { get; private set; }
    public Id jobId { get; private set; }

    public AccountLocationGeocodeListController(ApexPages.StandardSetController setController) {
        this.setController = setController;
        for (SObject rec : setController.getSelected()) {
            selectedIds.add(rec.Id);
        }
        selectedCount = selectedIds.size();
        started = false;
    }

    public Boolean enabled {
        get { return GoogleMapsSettings.isEnabled(); }
    }

    public Boolean openStreetMap {
        get { return GoogleMapsSettings.useOpenStreetMap(); }
    }

    public Integer openStreetMapLimit {
        get { return AccountLocationGeocodeBatch.OSM_MAX_RECORDS_PER_RUN; }
    }

    public PageReference start() {
        try {
            jobId = AccountLocationGeocodeBatch.run(selectedIds);
            started = true;
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.CONFIRM,
                'Location lookup started (batch job ' + jobId + '). It runs in the background; '
                + 'progress is in Setup > Apex Jobs. Refresh the list view when it has finished.'));
        } catch (Exception e) {
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, e.getMessage()));
        }
        return null;
    }

    /** Back to the list view. */
    public PageReference back() {
        return setController.cancel();
    }
}
