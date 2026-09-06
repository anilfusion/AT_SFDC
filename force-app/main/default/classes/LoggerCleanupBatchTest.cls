/**
 * Unit tests for {@link LoggerCleanupBatch}.
 */
@IsTest
private class LoggerCleanupBatchTest {
    @IsTest
    static void deletesOnlyLogsOlderThanRetentionWindow() {
        List<System_Log__c> logs = new List<System_Log__c>{
            new System_Log__c(Log_Type_Execution_Context__c = 'Generic Transaction', Message__c = 'old'),
            new System_Log__c(Log_Type_Execution_Context__c = 'Generic Transaction', Message__c = 'recent')
        };
        insert logs;

        Test.setCreatedDate(logs[0].Id, Datetime.now().addMonths(-4));
        Test.setCreatedDate(logs[1].Id, Datetime.now().addMonths(-1));

        Test.startTest();
        Database.executeBatch(new LoggerCleanupBatch(), 200);
        Test.stopTest();

        List<System_Log__c> remaining = [SELECT Message__c FROM System_Log__c];
        System.assertEquals(1, remaining.size(), 'Only the log inside the retention window should remain');
        System.assertEquals('recent', remaining[0].Message__c);
    }

    @IsTest
    static void customRetentionWindowIsHonored() {
        System_Log__c log = new System_Log__c(Log_Type_Execution_Context__c = 'Generic Transaction', Message__c = 'six weeks old');
        insert log;
        Test.setCreatedDate(log.Id, Datetime.now().addDays(-45));

        Test.startTest();
        Database.executeBatch(new LoggerCleanupBatch(1), 200); // 1-month retention
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM System_Log__c], '45-day-old log should be purged at 1-month retention');
    }

    @IsTest
    static void invalidRetentionFallsBackToDefault() {
        System_Log__c log = new System_Log__c(Log_Type_Execution_Context__c = 'Generic Transaction', Message__c = 'two months old');
        insert log;
        Test.setCreatedDate(log.Id, Datetime.now().addMonths(-2));

        Test.startTest();
        Database.executeBatch(new LoggerCleanupBatch(0), 200); // invalid -> default 3 months
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM System_Log__c], '2-month-old log should survive the default 3-month window');
    }

    @IsTest
    static void schedulableEntryPointRunsTheBatch() {
        System_Log__c log = new System_Log__c(Log_Type_Execution_Context__c = 'Generic Transaction', Message__c = 'ancient');
        insert log;
        Test.setCreatedDate(log.Id, Datetime.now().addMonths(-6));

        Test.startTest();
        new LoggerCleanupBatch().execute((SchedulableContext) null); // enqueues the batch; runs at stopTest
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM System_Log__c], 'Scheduled run should purge the 6-month-old log');
    }
}