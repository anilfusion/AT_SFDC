public class TA_Account_LocTzInsert implements TriggerAction.BeforeInsert, TriggerAction.AfterInsert {

    public void beforeInsert(List<Account> triggerNew) {
        if (hasSansanAccount(triggerNew)) {
            return;
        }

        for (Account acc : recordsToProcess(triggerNew)) {
            acc.Timezone_Updated__c = true;
        }
    }

    public void afterInsert(List<Account> triggerNew) {
        if (hasSansanAccount(triggerNew)) {
            return;
        }

        List<Id> accountIds = new List<Id>();
        for (Account acc : recordsToProcess(triggerNew)) {
            accountIds.add(acc.Id);
        }

        if (!accountIds.isEmpty() && LocationCallouts.skipcallout == false) {
            LocationCallouts.getLocation(accountIds);
        }
    }

    // Migrated from locationTrigger: skips this action for the entire insert batch (not just
    // the matching record) whenever any Account in it was created by the Sansan integration.
    private Boolean hasSansanAccount(List<Account> triggerNew) {
        for (Account acc : triggerNew) {
            if (String.isNotBlank(acc.Sansan_CI__Sansan_CompanyId_FK__c)) {
                return true;
            }
        }
        return false;
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
