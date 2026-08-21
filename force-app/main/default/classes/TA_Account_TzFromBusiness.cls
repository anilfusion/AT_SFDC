public class TA_Account_TzFromBusiness implements TriggerAction.BeforeUpdate {

    public void beforeUpdate(List<Account> triggerNew, List<Account> triggerOld) {
        for (Account acc : TA_Account_TriggerHelper.excludeRecordTypes(triggerNew)) {
            if (acc.Business__c == null) {
                continue;
            }

            List<String> businessParts = acc.Business__c.split('\\(');
            if (businessParts.size() < 2) {
                continue;
            }

            String timeZoneName = businessParts[1].substring(0, businessParts[1].length() - 1);
            acc.TimeZoneName__c = timeZoneName;
        }
    }
}
