@isTest
private class TA_Account_CreateCaseForAccount_Test {

    @isTest(SeeAllData=true)
    static void test_createsSalesOpsCaseForNewAtiAccount() {
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

        List<Case> salesOpsCases = [
            SELECT OwnerId, Subject, Reason, AccountId
            FROM Case
            WHERE AccountId = :testAccount.Id AND Reason = 'New Account'
        ];
        System.assertEquals(1, salesOpsCases.size(), 'Expected one Sales Ops case to be created for the new ATI Account');
        System.assertEquals('New Account Created for Sales Ops Review', salesOpsCases[0].Subject);
    }

    @isTest
    static void test_bypassFlagSkipsCaseCreation() {
        User testSystemAdmin = ATFE_TestMethodUtility.getTestUserWithProfileAndRole('System Administrator', 'ATI');
        insert testSystemAdmin;

        User testSalesUser = ATFE_TestMethodUtility.getTestUserWithProfileAndRole('Sales User', 'NA Sales');
        insert testSalesUser;

        Account testAccount = ATFE_TestMethodUtility.getTestAccountWithRecordType('ATI Accounts');
        testAccount.Region__c = 'NA';

        UtilSODOFlags.skip_caseTrigges = true;

        Test.startTest();
        System.runAs(testSalesUser) {
            insert testAccount;
        }
        Test.stopTest();

        List<Case> salesOpsCases = [SELECT Id FROM Case WHERE AccountId = :testAccount.Id];
        System.assertEquals(0, salesOpsCases.size(), 'Bypass flag should prevent Sales Ops case creation');
    }
}
