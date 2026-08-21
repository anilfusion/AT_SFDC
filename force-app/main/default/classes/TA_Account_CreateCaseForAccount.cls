public class TA_Account_CreateCaseForAccount implements TriggerAction.AfterInsert {

    // Region__c 'NA' and 'EMEA'/'CSA' take precedence; everything else is routed by
    // Sub_Region__c. Preserves the exact ownership precedence from the original
    // if/else chain while avoiding 17 loose Id variables.
    private static final Map<String, String> GROUP_DEVELOPER_NAME_BY_OWNER_KEY = new Map<String, String>{
        'NA' => 'NA_Sales_Ops_Queue',
        'EMEA' => 'EMEA_Sales_Ops_Queue',
        'APAC' => 'APAC_Sales_Ops_Queue',
        'Korea' => 'APAC_Korea_Support_New_Account_Owner',
        'Taiwan' => 'APAC_Taiwan_Support_New_Account_Owner',
        'Vietnam' => 'APAC_Vietnam_Support_New_Account_Owner',
        'India' => 'APAC_India_Support_New_Account_Owner',
        'Thailand' => 'APAC_Thailand_Support_New_Account_Owner',
        'Malaysia' => 'APAC_Malaysia_Support_New_Account_Owner',
        'Myanmar' => 'APAC_Myanmar_Support_New_Account_Owner',
        'Cambodia' => 'APAC_Cambodia_Support_New_Account_Owner',
        'Singapore' => 'APAC_Singapore_Support_New_Account_Owner',
        'Philippines' => 'APAC_Philippin_Support_New_Account_Owner',
        'Indonesia' => 'APAC_Indonesia_Support_New_Account_Owner',
        'New Zealand' => 'APAC_NewZealan_Support_New_Account_Owner',
        'Australia' => 'APAC_Australia_Support_New_Account_Owner',
        'China' => 'APAC_China_Support_New_Account_Owner'
    };

    public void afterInsert(List<Account> triggerNew) {
        if (UtilSODOFlags.skip_caseTrigges) {
            return;
        }

        User currentUser = [SELECT Profile.Name, Price_Book_Region__c FROM User WHERE Id = :UserInfo.getUserId()];
        Boolean hasValidRegion = ATFE_Utility.validateUserPriceBookRegion(currentUser, new Set<String>{'NA', 'EMEA', 'APAC'});

        if (!hasValidRegion && currentUser.Profile.Name != 'Customer Support Profile') {
            return;
        }

        List<Account> recordsToProcess = TA_Account_TriggerHelper.excludeRecordTypes(triggerNew);
        if (recordsToProcess.isEmpty()) {
            return;
        }

        Id americasAccountsRtId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('ATI Accounts').getRecordTypeId();
        Id americasCaseRtId = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Validate New Account Case').getRecordTypeId();

        Map<String, Id> ownerIdByGroupDeveloperName = new Map<String, Id>();
        for (GroupMember gm : [
            SELECT UserOrGroupId, Group.DeveloperName
            FROM GroupMember
            WHERE Group.DeveloperName IN :GROUP_DEVELOPER_NAME_BY_OWNER_KEY.values()
        ]) {
            ownerIdByGroupDeveloperName.put(gm.Group.DeveloperName, gm.UserOrGroupId);
        }

        List<Case> casesToCreate = new List<Case>();
        for (Account acc : recordsToProcess) {
            if (acc.RecordTypeId != americasAccountsRtId) {
                continue;
            }

            Case salesOpsCase = new Case(
                AccountId = acc.Id,
                ATFE_is_Case_Create_From_Account__c = true,
                Type = 'New Account',
                Status = 'New',
                Priority = 'High',
                Description = acc.Description,
                RecordTypeId = americasCaseRtId,
                ATFE_Submitted_By__c = UserInfo.getUserId(),
                Subject = 'New Account Created for Sales Ops Review',
                Origin = 'Salesforce',
                Reason = 'New Account'
            );

            String ownerKey;
            if (acc.Region__c == 'NA') {
                ownerKey = 'NA';
            } else if (acc.Region__c == 'EMEA' || acc.Region__c == 'CSA') {
                ownerKey = 'EMEA';
            } else {
                ownerKey = acc.Sub_Region__c;
            }

            if (GROUP_DEVELOPER_NAME_BY_OWNER_KEY.containsKey(ownerKey)) {
                salesOpsCase.OwnerId = ownerIdByGroupDeveloperName.get(GROUP_DEVELOPER_NAME_BY_OWNER_KEY.get(ownerKey));
            }

            casesToCreate.add(salesOpsCase);
        }

        if (!casesToCreate.isEmpty()) {
            try {
                insert casesToCreate;
            } catch (Exception e) {
                System.debug('While creating cases from Account:' + e.getMessage());
            }
        }
    }
}