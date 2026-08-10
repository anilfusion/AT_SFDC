public class TA_Account_TzFromBusiness implements TriggerAction.BeforeUpdate {

    public void beforeUpdate(List<Account> triggerNew, List<Account> triggerOld) {
        for (Account acc : recordsToProcess(triggerNew)) {
            if (acc.Business__c != null) {
                List<String> businessParts = acc.Business__c.split('\\(');
                String timeZoneName = businessParts[1].substring(0, businessParts[1].length() - 1);
                acc.TimeZoneName__c = timeZoneName;
            }
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
