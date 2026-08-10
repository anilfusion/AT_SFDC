public class TA_Account_LocTzUpdate implements TriggerAction.BeforeUpdate {

    public void beforeUpdate(List<Account> triggerNew, List<Account> triggerOld) {
        List<Id> accountIdsNeedingLocation = new List<Id>();

        for (Account acc : recordsToProcess(triggerNew)) {
            // Migrated as-is from locationTrigger: the original source only guarded
            // `uAccountIds.add(...)` with the Business__c/Timezone_Updated__c check (missing
            // braces meant the assignment below ran unconditionally for every updated record).
            // Preserved here for behavioral parity -- flagged for confirmation in conversion notes.
            if (acc.Business__c == null && acc.Timezone_Updated__c == false) {
                accountIdsNeedingLocation.add(acc.Id);
            }
            acc.Timezone_Updated__c = true;
        }

        if (!accountIdsNeedingLocation.isEmpty() && LocationCallouts.skipcallout == false) {
            LocationCallouts.getLocation(accountIdsNeedingLocation);
        }
    }

    private List<Account> recordsToProcess(List<Account> triggerNew) {
        Map<String, Schema.RecordTypeInfo> acctRtMapByDeveloperName = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();
        Set<Id> excludedRecordTypeIds = new Set<Id>();
        for (String developerName : new Set<String>{'JP_Accounts', 'JP_AccountsBeforeCleansing'}) {
            if (acctRtMapByDeveloperName.containsKey(developerName)) {
                excludedRecordTypeIds.add(acctRtMapByDeveloperName.get(developerName).getRecordTypeId());
            }
        }

        List<Account> records = new List<Account>();
        for (Account acc : triggerNew) {
            if (!excludedRecordTypeIds.contains(acc.RecordTypeId)) {
                records.add(acc);
            }
        }
        return records;
    }
}
