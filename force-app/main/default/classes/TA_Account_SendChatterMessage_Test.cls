@isTest
private class TA_Account_SendChatterMessage_Test {

    @isTest(SeeAllData=true)
    static void test_postsChatterFeedForNaAccountOpsOnAccountInsert() {
        User testSystemAdmin = ATFE_TestMethodUtility.getTestUserWithProfileAndRole('System Administrator', 'ATI');
        insert testSystemAdmin;

        User testSalesUser = ATFE_TestMethodUtility.getTestUserWithProfileAndRole('Sales User', 'NA Sales');
        insert testSalesUser;

        Account testAccount = ATFE_TestMethodUtility.getTestAccountWithRecordType('ATI Accounts');
        testAccount.Region__c = 'NA';

        Test.startTest();
        System.runAs(testSalesUser) {
            insert testAccount;
        }
        Test.stopTest();

        Set<Id> naAccountOpsUserIds = new Set<Id>();
        for (GroupMember gm : [SELECT UserOrGroupId FROM GroupMember WHERE Group.DeveloperName = 'NA_Account_Ops']) {
            naAccountOpsUserIds.add(gm.UserOrGroupId);
        }

        if (!naAccountOpsUserIds.isEmpty()) {
            List<FeedItem> posts = [
                SELECT Title, LinkUrl
                FROM FeedItem
                WHERE ParentId IN :naAccountOpsUserIds AND Title = :testAccount.Name
            ];
            System.assertEquals(naAccountOpsUserIds.size(), posts.size(), 'Expected one Chatter post per NA_Account_Ops member');
        }
    }
}