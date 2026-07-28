public class TA_Account_SendChatterMessage implements TriggerAction.AfterInsert {

    public void afterInsert(List<Account> triggerNew) {
        Set<Id> naSalesOpsUserIds = new Set<Id>();
        Set<Id> emeaSalesOpsUserIds = new Set<Id>();
        List<FeedItem> feedsToInsert = new List<FeedItem>();

        User currentUser = [SELECT Profile.Name, Price_Book_Region__c FROM User WHERE Id = :UserInfo.getUserId()];
        Boolean hasValidRegion = ATFE_Utility.validateUserPriceBookRegion(currentUser, new Set<String>{'NA', 'EMEA'});

        if (!hasValidRegion) {
            return;
        }

        // Excludes a specific hardcoded profile from source (see original ATFE_SendChatterMessage trigger).
        if (UserInfo.getProfileId() == '00eg0000000DjuDAAS') {
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

        for (GroupMember gm : [
            SELECT UserOrGroupId, GroupId, Group.DeveloperName
            FROM GroupMember
            WHERE Group.DeveloperName IN ('NA_Account_Ops', 'EMEA_Account_Ops')
        ]) {
            if (gm.Group.DeveloperName == 'NA_Account_Ops') {
                naSalesOpsUserIds.add(gm.UserOrGroupId);
            } else if (gm.Group.DeveloperName == 'EMEA_Account_Ops') {
                emeaSalesOpsUserIds.add(gm.UserOrGroupId);
            }
        }

        for (Account acc : recordsToProcess) {
            if (acc.Region__c == 'NA') {
                for (Id userId : naSalesOpsUserIds) {
                    FeedItem post = new FeedItem();
                    post.ParentId = userId;
                    post.Body = 'A new account has been created. To view the account please click on the following link:';
                    post.LinkUrl = '/' + acc.Id;
                    post.Title = acc.Name;
                    feedsToInsert.add(post);
                }
            }

            if (acc.Region__c == 'EMEA') {
                for (Id userId : emeaSalesOpsUserIds) {
                    FeedItem post = new FeedItem();
                    post.ParentId = userId;
                    post.Body = 'A new account has been created. To view the account please click on the following link:';
                    post.LinkUrl = '/' + acc.Id;
                    post.Title = acc.Name;
                    feedsToInsert.add(post);
                }
            }
        }

        if (!feedsToInsert.isEmpty()) {
            insert feedsToInsert;
        }
    }
}
