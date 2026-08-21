public class TA_Account_TriggerHelper {

    private static Set<Id> excludedRecordTypeIds;

    // JP_Accounts and JP_AccountsBeforeCleansing are excluded from these Account
    // trigger actions across the board; cached per-transaction so each TriggerAction
    // that calls this doesn't repeat the same RecordType describe.
    public static Set<Id> getExcludedRecordTypeIds() {
        if (excludedRecordTypeIds == null) {
            excludedRecordTypeIds = new Set<Id>();
            Map<String, Schema.RecordTypeInfo> acctRtMapByDeveloperName = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();
            for (String developerName : new Set<String>{ 'JP_Accounts', 'JP_AccountsBeforeCleansing' }) {
                if (acctRtMapByDeveloperName.containsKey(developerName)) {
                    excludedRecordTypeIds.add(acctRtMapByDeveloperName.get(developerName).getRecordTypeId());
                }
            }
        }
        return excludedRecordTypeIds;
    }

    public static List<Account> excludeRecordTypes(List<Account> accounts) {
        Set<Id> excludedIds = getExcludedRecordTypeIds();
        List<Account> recordsToProcess = new List<Account>();
        for (Account acc : accounts) {
            if (!excludedIds.contains(acc.RecordTypeId)) {
                recordsToProcess.add(acc);
            }
        }
        return recordsToProcess;
    }
}
