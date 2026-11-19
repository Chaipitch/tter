# Deployment Guide – Sandbox

This guide takes the project from git to a working feature in a **sandbox**. Run the commands from the project root on a machine that can reach the org.

---

## 0. Prerequisites

| Item | Notes |
|---|---|
| Salesforce CLI (`sf`) v2 | `sf --version`. Install from https://developer.salesforce.com/tools/salesforcecli |
| Sandbox user | Needs "Modify All Data" / "Author Apex" or System Administrator |
| Google Cloud project | Billing must be enabled (Google Maps Platform requires it, even for the free tier) |
| Git | To pull this repository |

```bash
git clone <this-repo-url>
```

```bash
cd tter
```

```bash
git checkout claude/focused-babbage-51c5ir
```

---

## 1. Pre-deployment checks (in the sandbox)

These checks take about 10 minutes and prevent most deployment failures. Do them in **Setup → Object Manager**.

### 1.1 Org API names (already set in the project)

The project is built for these names in `tterakit-sb`. Check that production uses the same names before promoting.

| Item | API name |
|---|---|
| AccountLocation object (ogg package) | `ogg__Location__c` |
| Link to the Account | `ogg__ObjectId__c`: Text(18) holding the Account Id (`ogg__prefix__c` = `001`). There's **no** lookup field. |
| Address | `Account.Address__c`; if it's blank, the Account's Billing Address. No Account (`ogg__ObjectId__c` isn't an Account Id) or no address: the record is skipped. `ogg__RawAddress__c` is not used. |
| Original coordinates | `ogg__Latitude__c`, `ogg__Longitude__c`. These are the defaults in `GoogleMapsSettings.cls` and in the custom setting script. |

### 1.2 Target fields already exist (not deployed)

`Suggested_Latitude__c`, **`Suggested_Longtitude__c`** (that's the spelling in the org), `Different_Distance__c` and the checkbox `isCoordsUpdated__c` already exist on `ogg__Location__c`. The project only reads and writes them; it doesn't deploy them, so their definitions stay as they are. The permission set grants read access to the first three and read/edit access to `isCoordsUpdated__c`, so users can untick it to have a record processed again.

### 1.3 Required fields on Account

Account has required fields (for example `Tax_ID__c`, `Customer_Type__c`, `Company__c`). The tests don't name them: `TestRecordFactory` fills every database-level required field with a value that fits its type. If a **validation rule** needs a specific value, add it to the values map in `AccountLocationGeocodingTest.newAccount()`.

### 1.4 UPWARD in tests

When a test inserts an Account with an address, UPWARD may create its own `ogg__Location__c`, and may run its own logic. The tests check only their own records, so extra UPWARD records don't break them. If UPWARD itself throws during the test insert, send the error. It may need a value in `newAccount()`.

### 1.5 Field-level security

The running user needs no access to the target fields. The job runs in system mode. To see the fields on the page, give your users read access, either through the permission set in step 3.4 or through their profile.

### 1.6 The on-create trigger

`AccountLocationTrigger` (after insert on `ogg__Location__c`) is part of the deployment. It looks up every new oggLocation automatically.

* **Other triggers:** if your org or UPWARD has other triggers on `ogg__Location__c`, they keep working. This one only queues a background job and doesn't change the record during the insert.
* **Before a large data load:** uncheck *Enabled* in Google Maps Settings during the load (or set `AccountLocationTriggerHandler.bypass = true` if the load runs in Apex). Afterwards, check *Enabled* again and process the loaded records with the "Suggest Locations" global action or the nightly run, then uncheck it again.
* **The removed `destructiveChanges.xml`:** an earlier version of this project used it to delete the trigger. It has been removed, so the trigger can't be deleted by accident. Don't use an old copy.

---

## 2. Google Maps Platform setup

1. In https://console.cloud.google.com, select or create a project and **enable billing**.
2. Go to **APIs & Services → Library** and enable:
   * **Geocoding API** (required)
   * **Places API (New)** (recommended for Thai addresses; it finds building names like อาคารเอ็มโพเรียม ทาวเวอร์ when the Geocoding API can't)
3. Go to **APIs & Services → Credentials → Create credentials → API key**.
4. **Restrict the key:**
   * *API restrictions*: allow only Geocoding API and Places API (New).
   * *Application restrictions*: Salesforce callouts come from Salesforce's published IP ranges. You can use *IP addresses* with those ranges, or leave it at *None* and rely on the API restriction plus quotas.
5. Under **APIs & Services → Geocoding API → Quotas**, set a daily cap that fits the expected volume. This prevents surprise bills.

> Never commit the key to git. It goes only into the custom setting in the org (step 4).

---

## 3. Deploy

### 3.1 Authenticate to the sandbox

```bash
sf org login web --alias tterakit-sb --instance-url https://test.salesforce.com
```

For a sandbox with My Domain, you can use `--instance-url https://<mydomain>--<sandbox>.sandbox.my.salesforce.com`.

### 3.2 Validate first (check-only, nothing is saved)

```bash
sf project deploy validate \
  --manifest manifest/package.xml \
  --target-org tterakit-sb \
  --test-level RunSpecifiedTests \
  --tests AccountLocationGeocodingTest \
  --tests GoogleGeocodingServiceTest \
  --tests GeoDistanceUtilTest \
  --tests ThaiAddressNormalizerTest \
  --tests OpenStreetMapGeocoderTest \
  --tests AccountLocationGeocodeBatchTest \
  --wait 30
```

Fix any errors that come up. Section 6 lists the common ones.

### 3.3 Deploy

```bash
sf project deploy start \
  --manifest manifest/package.xml \
  --target-org tterakit-sb \
  --test-level RunSpecifiedTests \
  --tests AccountLocationGeocodingTest \
  --tests GoogleGeocodingServiceTest \
  --tests GeoDistanceUtilTest \
  --tests ThaiAddressNormalizerTest \
  --tests OpenStreetMapGeocoderTest \
  --tests AccountLocationGeocodeBatchTest \
  --wait 30
```

If the validation passed, you can quick-deploy it instead: `sf project deploy quick --job-id <validation job id> --target-org tterakit-sb`.

### 3.4 Assign the permission set

The permission set lets users use the record button and the "Suggest Locations" global action, and read the three suggested/distance fields. It grants access to the Apex classes `AccountLocationGeocodeAction` and `SuggestLocationsPanelController`.

```bash
sf org assign permset --name AccountLocation_Geocoding --target-org tterakit-sb
```

To assign it to other users, add `--on-behalf-of user@example.com`, or assign it in Setup. Users without it get an error when they click a button.

### 3.5 Add the "Suggest Locations" global action (bulk, floats over the Account list view)

A list view button can't open a floating window in Lightning, and the users' app is a managed app, so the bulk lookup is a **global action**. It's in the global actions menu (the **+** icon in the header) in every app, and it opens a modal over the current page, such as the Account list view.

1. Setup → **Publisher Layouts** → **Global Layout** → **Edit**.
2. **Mobile & Lightning Actions** → if the *Salesforce Mobile and Lightning Experience Actions* section shows predefined actions, click **override the predefined actions** first.
3. Drag **Suggest Locations** into *Salesforce Mobile and Lightning Experience Actions* → **Save**.
4. In the app, click **+** (Global Actions) in the header → **Suggest Locations**.

The modal shows how many oggLocations aren't processed yet (`isCoordsUpdated__c` unchecked). **Start** runs the bulk lookup for **all** of them; the modal shows a progress bar (every 5 s), and when the run finishes, a summary and a toast. Closing the modal doesn't stop the run. Opening **Suggest Locations** again picks it up and shows its progress. An oggLocation report filtered on *isCoordsUpdated equals False* is handy for checking what's left.

If the action isn't in the **+** menu, check *Publisher Layout Assignment*: the user's profile may use another global layout.

### 3.5b Put the record button on the oggLocation page (single record)

* **Page layout** (most orgs): Setup → Object Manager → **oggLocation** → Page Layouts → open the layout → **Mobile & Lightning Actions** → drag **Suggest Location (Google)** into *Salesforce Mobile and Lightning Experience Actions* → Save. If that section shows "predefined actions", click the wrench icon first to override them.
* **Lightning record page with Dynamic Actions:** Lightning App Builder → select the Highlights Panel → **Add Action** → *Suggest Location (Google)* → Save.

Also add `Suggested Latitude`, `Suggested Longtitude` and `Different Distance` to the layout and, if useful, to list views.

### 3.5c Remove leftovers from earlier versions (orgs that had them, e.g. `tterakit-sb`)

Earlier versions deployed components that are no longer part of the project. A normal deploy never deletes anything from the org, so they stay until this cleanup runs:
* the Account list view button **Suggest Locations (Google)**, page `SuggestLocationsFromAccounts` and class `SuggestLocationsFromAccountsController`
* the oggLocation list view button, page `AccountLocationGeocodeList` and class `AccountLocationGeocodeListController`
* the Google Maps Settings fields **Country Code**, **Language**, **Region**, **Use Places Fallback** and **Disable Lookup On Create** (now fixed in Apex, `GoogleMapsSettings`)

They're unused, but they stay in the org until deleted:
1. Setup → Object Manager → **Account** → **List View Button Layout** → remove **Suggest Locations (Google)** from *Selected Buttons* → Save. A button that's still on a layout can't be deleted.
2. Deploy the current project first, so no test class refers to them any more, then delete them:

   ```bash
   sf project deploy start --manifest manifest/cleanup/package.xml --post-destructive-changes manifest/cleanup/destructiveChanges.xml --target-org tterakit-sb --ignore-warnings --wait 30
   ```

   `--ignore-warnings` matters: components that are already gone (e.g. buttons deleted earlier) only produce a warning, but without the flag a warning makes the whole cleanup fail and nothing is deleted.
3. Check: Setup → Custom Settings → **Google Maps Settings**. The five fields are now under *Deleted Fields* (kept by Salesforce for 15 days; you can **Erase** them there).

### 3.6 Optional: nightly run

To fill in new records automatically every night (02:00, org time zone), for all records not processed yet (`isCoordsUpdated__c` unchecked):

```bash
sf apex run --file scripts/apex/schedule-nightly.apex --target-org tterakit-sb
```

To stop it: Setup → **Scheduled Jobs** → *Suggest locations nightly* → **Del**. Only schedule it with Google as the provider: OpenStreetMap is capped at 200 records per run and isn't meant for regular bulk use.

---

## 4. Configure the custom setting

The feature is **off** until the Organization Default of `Google_Maps_Settings__c` has `Enabled__c = true` and either an API key (Google) or *Provider* = `OpenStreetMap`.

**No Google API key yet? Use OpenStreetMap for now (temporary)**

```bash
sf apex run --file scripts/apex/configure-openstreetmap.apex --target-org tterakit-sb
```

This sets *Provider* = `OpenStreetMap` and *Enabled*, with no key. The button then uses the free OpenStreetMap Nominatim geocoder instead of Google. Keep in mind:
* **Testing and demos only.** Thai coverage in OpenStreetMap is weaker than Google's, especially for house numbers. Expect more street- or district-level pins and larger distances. Don't judge the feature's accuracy from these results.
* **Usage policy: at most 1 request per second, no bulk use.** The code spaces requests 1.1 s apart, processes 10 records per batch chunk, and caps a bulk run at **200 records**. Don't schedule nightly runs with OpenStreetMap.
* **Places fallback isn't used.** With OpenStreetMap the search is: address without room/floor, then street level.
* **Switching to Google later:** run Option A below. It sets *Provider* = `Google` and the key. Nothing else changes.


**Option A – script (recommended)**

1. Edit `scripts/apex/configure-settings.apex` and paste the API key. The field names are already set. **Don't commit** the edited file.
2. Run:

   ```bash
   sf apex run --file scripts/apex/configure-settings.apex --target-org tterakit-sb
   ```

3. Undo the edit:

   ```bash
   git checkout scripts/apex/configure-settings.apex
   ```

**Option B – Setup UI**

Go to **Setup → Custom Settings → Google Maps Settings → Manage → New** (in the *Default Organization Level Value* section).

| Field | Value |
|---|---|
| Enabled | ✔ |
| Provider | `Google` (or blank). `OpenStreetMap` = temporary no-key option, see above |
| API Key | your key (not needed for OpenStreetMap) |
| Original Latitude Field | `ogg__Latitude__c` |
| Original Longitude Field | `ogg__Longitude__c` |
| Batch Size | `30` (max 30, because one address can take up to 3 callouts) |
| Timeout (ms) | `10000` |

Fixed in Apex (`GoogleMapsSettings`), not settings: results restricted to Thailand (`TH`) and returned in Thai (`th`); the Places API fallback is on (Google only; if Places API isn't enabled on the key, the Geocoding result is used); new records are looked up automatically by the trigger.

The Remote Site Settings `Google_Maps_Geocoding_API`, `Google_Places_API` and `OpenStreetMap_Nominatim` are deployed by the project. Check that they're active under **Setup → Remote Site Settings**.

---

## 5. Smoke test

Check the key and settings with one direct call (this makes no DML):

```bash
sf apex run --file scripts/apex/test-geocode-address.apex --target-org tterakit-sb
```

A line like `source=GEOCODING_API lat=13.74... lng=100.53...` in the output means the setup is good. Then follow [TESTING_GUIDE.md](TESTING_GUIDE.md).

---

## 6. Troubleshooting deployment

| Error | Cause / fix |
|---|---|
| `Invalid type: ogg__Location__c` | The ogg package isn't installed in this sandbox, or the object name differs. See 1.1. |
| `No such column 'Address__c'` | The address field on Account has a different name. See 1.3. |
| Test failure `FIELD_CUSTOM_VALIDATION_EXCEPTION` | A validation rule needs a specific value. Add it in `newAccount()` / `newLocation()`. See 1.3. |
| Test failure `You have uncommitted work pending` | A test saved data and then called Google in the same transaction. Keep test settings in memory (`GoogleMapsSettings.cached = ...`) or make the callout after `Test.startTest()`. |
| Test failure `Google_Maps_Settings__c: field "Latitude__c" does not exist` | The default original field names don't exist in this org. Change `DEFAULT_LATITUDE_FIELD` / `DEFAULT_LONGITUDE_FIELD` in `GoogleMapsSettings.cls` to your field names. The tests use the defaults because custom setting data isn't visible in tests. |
| Test assertion fails on `mock.requests.size()` | UPWARD may create its own AccountLocation when an Account with an address is inserted. That adds callouts. Relax the count assertions, or insert the Account in the test without `Address__c` and set it afterwards. |

---

## 7. Rollback

* **Quick off switch:** uncheck `Enabled__c` in the custom setting. The trigger does nothing, the record button and the global action say the lookup is turned off, and a running batch stops making calls at its next chunk.
* **Only stop the automatic lookup on create:** set `AccountLocationTriggerHandler.bypass = true` in the Apex that inserts, or permanently set `lookupOnCreateOn = false` in `GoogleMapsSettings` and deploy.
* **Stop a running batch:** Setup → Apex Jobs → *Abort* on `AccountLocationGeocodeBatch`.
* **Stop the nightly run:** Setup → Scheduled Jobs → *Suggest locations nightly* → Del.
* **Hide the actions:** remove **Suggest Locations** from the Global Publisher Layout, and the record button from the oggLocation page layout / Lightning page.
* **Full removal:** delete the trigger, buttons, page, LWC and classes with a destructive deployment. Keep the fields if their data is needed.

---

## 8. Promoting to production later

* Use `--test-level RunSpecifiedTests` with the six test classes (or `RunLocalTests`). Production requires 75% coverage overall.
* Repeat steps 3.4, 3.5, 3.5b, 3.6 and 4 in production, using a **production** API key with its own quota.
* To fill in existing records after go-live, use the "Suggest Locations" global action, or run `scripts/apex/regeocode-existing.apex`.
