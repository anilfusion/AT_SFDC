/**
 * Unit tests for {@link LoggerQueueable}.
 */
@IsTest
private class LoggerQueueableTest {
    @IsTest
    static void executeInsertsBufferedLogs() {
        List<System_Log__c> logs = new List<System_Log__c>{
            new System_Log__c(Transaction_ID__c = 'txn-1', Log_Type_Execution_Context__c = 'Generic Transaction', Message__c = 'one'),
            new System_Log__c(Transaction_ID__c = 'txn-1', Log_Type_Execution_Context__c = 'Generic Transaction', Message__c = 'two')
        };

        Test.startTest();
        System.enqueueJob(new LoggerQueueable(logs));
        Test.stopTest();

        System.assertEquals(2, [SELECT COUNT() FROM System_Log__c]);
    }

    @IsTest
    static void persistIsNullAndEmptySafe() {
        Test.startTest();
        LoggerQueueable.persist(null);
        LoggerQueueable.persist(new List<System_Log__c>());
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM System_Log__c]);
    }

    @IsTest
    static void constructorToleratesNull() {
        Test.startTest();
        System.enqueueJob(new LoggerQueueable(null));
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM System_Log__c]);
    }

    @IsTest
    static void partialSuccessKeepsGoodRecords() {
        // Force one bad row with a well-formed but non-existent User lookup (INVALID_CROSS_REFERENCE_KEY).
        System_Log__c good = new System_Log__c(Log_Type_Execution_Context__c = 'Generic Transaction', Message__c = 'ok');
        System_Log__c bad = new System_Log__c(
            Log_Type_Execution_Context__c = 'Generic Transaction',
            Executing_User__c = '005000000000000AAA'
        );

        Test.startTest();
        LoggerQueueable.persist(new List<System_Log__c>{ good, bad });
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM System_Log__c], 'Good row should survive the bad one');
    }
}