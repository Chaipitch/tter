/**
 * Builds test records that satisfy the org's required fields (e.g. Account.Tax_ID__c, Customer_Type__c,
 * Company__c) without hard-coding them: every field that is required at the database level
 * (not nillable, createable, no default) and not supplied by the caller gets a value based on its type.
 * Lookup fields get a newly inserted parent record, built the same way (two levels deep).
 *
 * If a validation rule needs a specific value, pass it in the "values" map.
 */
@IsTest
public class TestRecordFactory {

    private static final Integer MAX_DEPTH = 2;

    /** Builds (does not insert) a record with the given values plus generated values for required fields. */
    public static SObject build(Schema.SObjectType type, Map<String, Object> values) {
        return build(type, values, 0);
    }

    private static SObject build(Schema.SObjectType type, Map<String, Object> values, Integer depth) {
        SObject rec = type.newSObject(null, true);   // true = load field defaults
        Set<String> provided = new Set<String>();
        if (values != null) {
            for (String field : values.keySet()) {
                rec.put(field, values.get(field));
                provided.add(field.toLowerCase());
            }
        }

        for (Schema.SObjectField f : type.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult d = f.getDescribe();
            if (provided.contains(d.getName().toLowerCase())
                    || d.isNillable() || !d.isCreateable() || d.isDefaultedOnCreate()
                    || d.isCalculated() || d.isAutoNumber()
                    || rec.get(d.getName()) != null) {
                continue;
            }
            Object v = valueFor(d, depth);
            if (v != null) {
                rec.put(d.getName(), v);
            }
        }
        return rec;
    }

    private static Object valueFor(Schema.DescribeFieldResult d, Integer depth) {
        switch on d.getType() {
            when STRING, TEXTAREA, ENCRYPTEDSTRING {
                // 13 random digits (fits Thai tax-id style formats), cut to the field length
                String digits = String.valueOf(Math.abs(Crypto.getRandomLong())).leftPad(13, '1').left(13);
                return digits.left(Math.max(1, d.getLength()));
            }
            when EMAIL {
                return 'test' + Math.abs(Crypto.getRandomInteger()) + '@example.com';
            }
            when PHONE {
                return '0812345678';
            }
            when URL {
                return 'https://example.com';
            }
            when PICKLIST, MULTIPICKLIST {
                for (Schema.PicklistEntry e : d.getPicklistValues()) {
                    if (e.isActive()) {
                        return e.getValue();
                    }
                }
                return null;
            }
            when INTEGER, DOUBLE, CURRENCY, PERCENT, LONG {
                return 1;
            }
            when DATE {
                return Date.today();
            }
            when DATETIME {
                return System.now();
            }
            when TIME {
                return Time.newInstance(9, 0, 0, 0);
            }
            when BOOLEAN {
                return false;
            }
            when REFERENCE {
                return parentId(d, depth);
            }
            when else {
                return null;
            }
        }
    }

    private static Id parentId(Schema.DescribeFieldResult d, Integer depth) {
        List<Schema.SObjectType> targets = d.getReferenceTo();
        if (targets.isEmpty()) {
            return null;
        }
        Schema.SObjectType target = targets[0];
        if (target == User.SObjectType) {
            return UserInfo.getUserId();
        }
        if (depth >= MAX_DEPTH) {
            return null;
        }
        SObject parent = build(target, null, depth + 1);
        insert parent;
        return parent.Id;
    }
}
