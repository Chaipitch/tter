trigger AccountLocationTrigger on ogg__Location__c (after insert) {
    AccountLocationTriggerHandler.afterInsert(Trigger.new);
}
