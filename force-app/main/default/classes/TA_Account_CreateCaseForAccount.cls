public class TA_Account_CreateCaseForAccount implements TriggerAction.AfterInsert {

    public void afterInsert(List<Account> triggerNew) {
        if (UtilSODOFlags.skip_caseTrigges) {
            return;
        }

        User currentUser = [SELECT Profile.Name, Price_Book_Region__c FROM User WHERE Id = :UserInfo.getUserId()];
        Boolean hasValidRegion = ATFE_Utility.validateUserPriceBookRegion(currentUser, new Set<String>{'NA', 'EMEA', 'APAC'});

        if (!hasValidRegion && currentUser.Profile.Name != 'Customer Support Profile') {
            return;
        }

        Map<String, Schema.RecordTypeInfo> acctRtMapByDeveloperName = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();
        Set<Id> excludedRecordTypeIds = new Set<Id>();
        for (String developerName : new Set<String>{'JP_Accounts', 'JP_AccountsBeforeCleansing'}) {
            if (acctRtMapByDeveloperName.containsKey(developerName)) {
                excludedRecordTypeIds.add(acctRtMapByDeveloperName.get(developerName).getRecordTypeId());
            }
        }

        List<Account> recordsToProcess = new List<Account>();
        for (Account acc : triggerNew) {
            if (!excludedRecordTypeIds.contains(acc.RecordTypeId)) {
                recordsToProcess.add(acc);
            }
        }
        if (recordsToProcess.isEmpty()) {
            return;
        }

        List<Case> casesToCreate = new List<Case>();
        Set<Id> accountRtIds = new Set<Id>();

        Schema.DescribeSObjectResult accountDescribe = Schema.SObjectType.Account;
        Map<String, Schema.RecordTypeInfo> acctRtMapByName = accountDescribe.getRecordTypeInfosByName();
        Id americasAccountsRtId = acctRtMapByName.get('ATI Accounts').getRecordTypeId();
        accountRtIds.add(americasAccountsRtId);

        Schema.DescribeSObjectResult caseDescribe = Schema.SObjectType.Case;
        Map<String, Schema.RecordTypeInfo> caseRtMapByName = caseDescribe.getRecordTypeInfosByName();
        Id americasCaseRtId = caseRtMapByName.get('Validate New Account Case').getRecordTypeId();

        Id naAccountOpsId = null;
        Id emeaAccountOpsId = null;
        Id apacAccountOpsId = null;
        Id koreaAccountOpsId = null;
        Id taiwanAccountOpsId = null;
        Id vietnamAccountOpsId = null;
        Id indiaAccountOpsId = null;
        Id thailandAccountOpsId = null;
        Id malaysiaAccountOpsId = null;
        Id myanmarAccountOpsId = null;
        Id cambodiaAccountOpsId = null;
        Id singaporeAccountOpsId = null;
        Id philippinAccountOpsId = null;
        Id indonesiaAccountOpsId = null;
        Id newZealanAccountOpsId = null;
        Id australiaAccountOpsId = null;
        Id chinaAccountOpsId = null;

        for (GroupMember gm : [
            SELECT UserOrGroupId, GroupId, Group.DeveloperName
            FROM GroupMember
            WHERE Group.DeveloperName IN (
                'NA_Sales_Ops_Queue',
                'EMEA_Sales_Ops_Queue',
                'APAC_Sales_Ops_Queue',
                'APAC_Korea_Support_New_Account_Owner',
                'APAC_Taiwan_Support_New_Account_Owner',
                'APAC_Vietnam_Support_New_Account_Owner',
                'APAC_India_Support_New_Account_Owner',
                'APAC_Thailand_Support_New_Account_Owner',
                'APAC_Malaysia_Support_New_Account_Owner',
                'APAC_Myanmar_Support_New_Account_Owner',
                'APAC_Cambodia_Support_New_Account_Owner',
                'APAC_Singapore_Support_New_Account_Owner',
                'APAC_Philippin_Support_New_Account_Owner',
                'APAC_Indonesia_Support_New_Account_Owner',
                'APAC_NewZealan_Support_New_Account_Owner',
                'APAC_Australia_Support_New_Account_Owner',
                'APAC_China_Support_New_Account_Owner'
            )
        ]) {
            if (gm.Group.DeveloperName == 'NA_Sales_Ops_Queue') {
                naAccountOpsId = gm.UserOrGroupId;
            } else if (gm.Group.DeveloperName == 'EMEA_Sales_Ops_Queue') {
                emeaAccountOpsId = gm.UserOrGroupId;
            } else if (gm.Group.DeveloperName == 'APAC_Sales_Ops_Queue') {
                apacAccountOpsId = gm.UserOrGroupId;
            } else if (gm.Group.DeveloperName == 'APAC_Korea_Support_New_Account_Owner') {
                koreaAccountOpsId = gm.UserOrGroupId;
            } else if (gm.Group.DeveloperName == 'APAC_Taiwan_Support_New_Account_Owner') {
                taiwanAccountOpsId = gm.UserOrGroupId;
            } else if (gm.Group.DeveloperName == 'APAC_Vietnam_Support_New_Account_Owner') {
                vietnamAccountOpsId = gm.UserOrGroupId;
            } else if (gm.Group.DeveloperName == 'APAC_India_Support_New_Account_Owner') {
                indiaAccountOpsId = gm.UserOrGroupId;
            } else if (gm.Group.DeveloperName == 'APAC_Thailand_Support_New_Account_Owner') {
                thailandAccountOpsId = gm.UserOrGroupId;
            } else if (gm.Group.DeveloperName == 'APAC_Malaysia_Support_New_Account_Owner') {
                malaysiaAccountOpsId = gm.UserOrGroupId;
            } else if (gm.Group.DeveloperName == 'APAC_Myanmar_Support_New_Account_Owner') {
                myanmarAccountOpsId = gm.UserOrGroupId;
            } else if (gm.Group.DeveloperName == 'APAC_Cambodia_Support_New_Account_Owner') {
                cambodiaAccountOpsId = gm.UserOrGroupId;
            } else if (gm.Group.DeveloperName == 'APAC_Singapore_Support_New_Account_Owner') {
                singaporeAccountOpsId = gm.UserOrGroupId;
            } else if (gm.Group.DeveloperName == 'APAC_Philippin_Support_New_Account_Owner') {
                philippinAccountOpsId = gm.UserOrGroupId;
            } else if (gm.Group.DeveloperName == 'APAC_Indonesia_Support_New_Account_Owner') {
                indonesiaAccountOpsId = gm.UserOrGroupId;
            } else if (gm.Group.DeveloperName == 'APAC_NewZealan_Support_New_Account_Owner') {
                newZealanAccountOpsId = gm.UserOrGroupId;
            } else if (gm.Group.DeveloperName == 'APAC_Australia_Support_New_Account_Owner') {
                australiaAccountOpsId = gm.UserOrGroupId;
            } else if (gm.Group.DeveloperName == 'APAC_China_Support_New_Account_Owner') {
                chinaAccountOpsId = gm.UserOrGroupId;
            }
        }

        for (Account acc : recordsToProcess) {
            if (!accountRtIds.contains(acc.RecordTypeId)) {
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

            if (acc.Region__c == 'NA') {
                salesOpsCase.OwnerId = naAccountOpsId;
            } else if (acc.Region__c == 'EMEA' || acc.Region__c == 'CSA') {
                salesOpsCase.OwnerId = emeaAccountOpsId;
            } else if (acc.Sub_Region__c == 'APAC') {
                salesOpsCase.OwnerId = apacAccountOpsId;
            } else if (acc.Sub_Region__c == 'Australia') {
                salesOpsCase.OwnerId = australiaAccountOpsId;
            } else if (acc.Sub_Region__c == 'Cambodia') {
                salesOpsCase.OwnerId = cambodiaAccountOpsId;
            } else if (acc.Sub_Region__c == 'China') {
                salesOpsCase.OwnerId = chinaAccountOpsId;
            } else if (acc.Sub_Region__c == 'India') {
                salesOpsCase.OwnerId = indiaAccountOpsId;
            } else if (acc.Sub_Region__c == 'Indonesia') {
                salesOpsCase.OwnerId = indonesiaAccountOpsId;
            } else if (acc.Sub_Region__c == 'Korea') {
                salesOpsCase.OwnerId = koreaAccountOpsId;
            } else if (acc.Sub_Region__c == 'Malaysia') {
                salesOpsCase.OwnerId = malaysiaAccountOpsId;
            } else if (acc.Sub_Region__c == 'Myanmar') {
                salesOpsCase.OwnerId = myanmarAccountOpsId;
            } else if (acc.Sub_Region__c == 'New Zealand') {
                salesOpsCase.OwnerId = newZealanAccountOpsId;
            } else if (acc.Sub_Region__c == 'Philippines') {
                salesOpsCase.OwnerId = philippinAccountOpsId;
            } else if (acc.Sub_Region__c == 'Singapore') {
                salesOpsCase.OwnerId = singaporeAccountOpsId;
            } else if (acc.Sub_Region__c == 'Taiwan') {
                salesOpsCase.OwnerId = taiwanAccountOpsId;
            } else if (acc.Sub_Region__c == 'Thailand') {
                salesOpsCase.OwnerId = thailandAccountOpsId;
            } else if (acc.Sub_Region__c == 'Vietnam') {
                salesOpsCase.OwnerId = vietnamAccountOpsId;
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