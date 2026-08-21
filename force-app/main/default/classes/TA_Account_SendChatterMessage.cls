public class TA_Account_SendChatterMessage implements TriggerAction.AfterInsert {

    private static final String FEED_BODY = 'A new account has been created. To view the account please click on the following link:';

    private static final Map<String, String> GROUP_DEVELOPER_NAME_BY_REGION = new Map<String, String>{
        'NA' => 'NA_Account_Ops',
        'EMEA' => 'EMEA_Account_Ops'
    };

    public void afterInsert(List<Account> triggerNew) {
        User currentUser = [SELECT Profile.Name, Price_Book_Region__c FROM User WHERE Id = :UserInfo.getUserId()];
        Boolean hasValidRegion = ATFE_Utility.validateUserPriceBookRegion(currentUser, new Set<String>{'NA', 'EMEA'});

        if (!hasValidRegion) {
            return;
        }
        
        List<Account> recordsToProcess = TA_Account_TriggerHelper.excludeRecordTypes(triggerNew);
        if (recordsToProcess.isEmpty()) {
            return;
        }

        Map<String, Set<Id>> userIdsByRegion = new Map<String, Set<Id>>();
        for (GroupMember gm : [
            SELECT UserOrGroupId, Group.DeveloperName
            FROM GroupMember
            WHERE Group.DeveloperName IN :GROUP_DEVELOPER_NAME_BY_REGION.values()
        ]) {
            for (String region : GROUP_DEVELOPER_NAME_BY_REGION.keySet()) {
                if (GROUP_DEVELOPER_NAME_BY_REGION.get(region) == gm.Group.DeveloperName) {
                    if (!userIdsByRegion.containsKey(region)) {
                        userIdsByRegion.put(region, new Set<Id>());
                    }
                    userIdsByRegion.get(region).add(gm.UserOrGroupId);
                }
            }
        }

        List<FeedItem> feedsToInsert = new List<FeedItem>();
        for (Account acc : recordsToProcess) {
            Set<Id> userIds = userIdsByRegion.get(acc.Region__c);
            if (userIds == null) {
                continue;
            }

            for (Id userId : userIds) {
                feedsToInsert.add(new FeedItem(
                    ParentId = userId,
                    Body = FEED_BODY,
                    LinkUrl = '/' + acc.Id,
                    Title = acc.Name
                ));
            }
        }

        if (!feedsToInsert.isEmpty()) {
            insert feedsToInsert;
        }
    }
}