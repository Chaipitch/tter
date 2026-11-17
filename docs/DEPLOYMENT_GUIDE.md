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

### 1.1 AccountLocation object API name

Open the AccountLocation object and note its **API Name**.

* If it is `AccountLocation__c`, nothing needs to change.
* If it has a namespace (for example, `UPWARD__AccountLocation__c`) or a different name, rename the references in the project. Replace `ns__` with the real prefix:

  ```bash
  NS=ns__
  grep -rl --include=* -e 'AccountLocation__c' -e 'Account__c' -e 'Account__r' force-app manifest scripts \
    | xargs sed -i.bak -e "s/\bAccountLocation__c/${NS}AccountLocation__c/g" \
                       -e "s/\bAccount__c\b/${NS}Account__c/g" \
                       -e "s/\bAccount__r\b/${NS}Account__r/g"
  ```

  ```bash
  mv force-app/main/default/objects/AccountLocation__c "force-app/main/default/objects/${NS}AccountLocation__c"
  ```

  ```bash
  find . -name '*.bak' -delete
  ```

  > The **new** fields (`Suggested_Latitude__c` etc.) stay **without** a namespace. Fields you add to a managed object are always in your own namespace. Only the object name and the `Account__c` lookup get the prefix. In the field-meta XML and the permission set, the field reference becomes `ns__AccountLocation__c.Suggested_Latitude__c`. The `sed` above handles that.
  >
  > The command needs GNU sed. On macOS, install it with `brew install gnu-sed` and run `gsed` instead of `sed`.

### 1.2 Lookup to Account

On AccountLocation, confirm that the lookup to Account is `Account__c` (relationship name `Account__r`). If it has a different name, search and replace `Account__c` / `Account__r` the same way.

### 1.3 Account address field

On **Account**, confirm the address field is `Address__c`. Any text type works: Text, Text Area, or Long Text Area.

### 1.4 Original latitude / longitude fields

On AccountLocation, find the fields where UPWARD stores the original coordinates. Write down their **API names**, for example:

| Kind of field | Use these API names |
|---|---|
| Two number fields | `Latitude__c`, `Longitude__c` (the default) |
| One Geolocation field, e.g. `Location__c` | `Location__Latitude__s`, `Location__Longitude__s` |
| Managed package fields | `UPWARD__Latitude__c`, … |

You'll enter these names in the custom setting in step 4. No code change is needed. The test class also reads them from the setting.

### 1.5 Do the three target fields already exist?

Check AccountLocation for `Suggested_Latitude__c`, `Suggested_Longitude__c` and `Different_Distance__c`.

* **They don't exist:** deploy as-is. The project creates them as Number(3,7), Number(3,7) and Number(10,2).
* **They exist:** remove the three `AccountLocation__c.*` `CustomField` members from `manifest/package.xml`. Also delete `force-app/main/default/objects/AccountLocation__c/fields/`. This keeps the deployment from changing your field definitions. They must be **Number** (or Currency/Percent) fields with at least 7 decimal places for latitude/longitude.

### 1.6 Existing triggers on AccountLocation

Check **Object Manager → AccountLocation → Triggers**. A second trigger on the same object works, but the execution order between triggers is not guaranteed. If your org uses a trigger framework (one trigger per object), call `AccountLocationTriggerHandler.afterInsert(...)` and `.beforeUpdate(...)` from your existing trigger. Then remove `AccountLocationTrigger` from the manifest.

### 1.7 Required fields / validation rules

If Account or AccountLocation has required fields or validation rules, the tests may fail on insert. Add the required values in `AccountLocationGeocodingTest.newAccount()` and `newLocation()`.

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
  --wait 30
```

If the validation passed, you can quick-deploy it instead: `sf project deploy quick --job-id <validation job id> --target-org tterakit-sb`.

### 3.4 Assign the permission set

This gives users read access to the three new fields:

```bash
sf org assign permset --name AccountLocation_Geocoding --target-org tterakit-sb
```

To assign it to other users, add `--on-behalf-of user@example.com`, or assign it in Setup.

Also add the three fields to the **AccountLocation page layout / Lightning record page** so testers can see them.

---

## 4. Configure the custom setting

The feature is **off** until the Organization Default of `Google_Maps_Settings__c` has `Enabled__c = true` and an API key.

**Option A – script (recommended)**

1. Edit `scripts/apex/configure-settings.apex`. Set the API key and the original latitude/longitude field names from step 1.4. **Don't commit** the edited file.
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
| API Key | your key |
| Use Places Fallback | ✔ if Places API (New) is enabled |
| Country Code | `TH` (restricts Geocoding results to Thailand) |
| Region | `th` (biases results to Thailand) |
| Language | `th` (results come back in Thai, matching the Thai input) |
| Original Latitude Field | e.g. `Latitude__c` |
| Original Longitude Field | e.g. `Longitude__c` |
| Batch Size | `30` (max 30, because one address can take up to 3 callouts) |
| Timeout (ms) | `10000` |

The Remote Site Settings `Google_Maps_Geocoding_API` and `Google_Places_API` are deployed by the project. Check that they're active under **Setup → Remote Site Settings**.

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
| `Invalid type: AccountLocation__c` | The object name differs or has a namespace. See 1.1. |
| `No such column 'Account__r'` / `Address__c` | The lookup or address field name differs. See 1.2 / 1.3. |
| `Cannot change type of field` on Suggested_* | The fields already exist with another type. See 1.5. |
| Test failure `REQUIRED_FIELD_MISSING` / `FIELD_CUSTOM_VALIDATION_EXCEPTION` | Add the required values in the test helpers. See 1.7. |
| Test failure `Google_Maps_Settings__c: field "Latitude__c" does not exist` | The default original field names don't exist in this org. Change `DEFAULT_LATITUDE_FIELD` / `DEFAULT_LONGITUDE_FIELD` in `GoogleMapsSettings.cls` to your field names. The tests use the defaults because custom setting data isn't visible in tests. |
| Test assertion fails on `mock.requests.size()` | UPWARD may create its own AccountLocation when an Account with an address is inserted. That adds callouts. Relax the count assertions, or insert the Account in the test without `Address__c` and set it afterwards. |

---

## 7. Rollback

* **Quick off switch:** uncheck `Enabled__c` in the custom setting. The trigger then does nothing.
* **Full removal:** use a destructive deployment for the trigger and classes. Keep the fields if their data is needed.

  ```bash
  sf project delete source --metadata ApexTrigger:AccountLocationTrigger --target-org tterakit-sb
  ```

---

## 8. Promoting to production later

* Use `--test-level RunSpecifiedTests` with the four test classes (or `RunLocalTests`). Production requires 75% coverage overall and at least 1% for each trigger.
* Repeat steps 3.4 and 4 in production, using a **production** API key with its own quota.
* To back-fill records created before go-live, run `scripts/apex/regeocode-existing.apex`. The trigger only handles new records.
