/**
 * ogg__Location__c trigger: after insert, queue the location lookup for the new records.
 * All logic lives in AccountLocationTriggerHandler. The list view button, record button and nightly
 * batch work independently of this trigger.
 */
trigger AccountLocationTrigger on ogg__Location__c (after insert) {
    AccountLocationTriggerHandler.afterInsert(Trigger.new);
}
