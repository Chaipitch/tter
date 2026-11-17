/**
 * ogg__Location__c trigger.
 *  - after insert  : queue a Google Maps lookup for ogg__Account__r.Address__c (callouts are not allowed in triggers).
 *  - before update : recalculate Different_Distance__c whenever the original or suggested coordinates change.
 * All logic lives in AccountLocationTriggerHandler.
 */
trigger AccountLocationTrigger on ogg__Location__c (after insert, before update) {
    if (Trigger.isAfter && Trigger.isInsert) {
        AccountLocationTriggerHandler.afterInsert(Trigger.new);
    } else if (Trigger.isBefore && Trigger.isUpdate) {
        AccountLocationTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
    }
}
