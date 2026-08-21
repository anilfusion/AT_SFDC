public class TA_Account_LocTzUpdate implements TriggerAction.BeforeUpdate {

    public void beforeUpdate(List<Account> triggerNew, List<Account> triggerOld) {
        List<Id> accountIdsNeedingLocation = new List<Id>();

        for (Account acc : TA_Account_TriggerHelper.excludeRecordTypes(triggerNew)) {
            // Migrated as-is from locationTrigger: the original source only guarded
            // `uAccountIds.add(...)` with the Business__c/Timezone_Updated__c check (missing
            // braces meant the assignment below ran unconditionally for every updated record).
            // Preserved here for behavioral parity -- confirmed to keep as-is during this
            // optimization pass (2026-08-19); do not "fix" without a separate, explicit decision.
            if (acc.Business__c == null && acc.Timezone_Updated__c == false) {
                accountIdsNeedingLocation.add(acc.Id);
            }
            acc.Timezone_Updated__c = true;
        }

        if (!accountIdsNeedingLocation.isEmpty() && LocationCallouts.skipcallout == false) {
            LocationCallouts.getLocation(accountIdsNeedingLocation);
        }
    }
}
