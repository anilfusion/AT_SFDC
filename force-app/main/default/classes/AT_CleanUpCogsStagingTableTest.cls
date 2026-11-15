@IsTest
private class AT_CleanUpCogsStagingTableTest {

    private static final List<String> ALL_STATUSES = new List<String>{ 'Holding', 'Running', 'Success', 'Failed', 'Skipped' };
    private static final Integer RECORDS_PER_STATUS = 5;

    @TestSetup
    static void setup() {
        List<COGSUpdateStagingRecord__c> records = new List<COGSUpdateStagingRecord__c>();
        for (String status : ALL_STATUSES) {
            for (Integer i = 0; i < RECORDS_PER_STATUS; i++) {
                records.add(new COGSUpdateStagingRecord__c(ProcessingStatus__c = status));
            }
        }
        insert records;
    }

    @IsTest
    static void batchDeletesOnlySuccessAndSkippedRecords() {
        Test.startTest();
        Database.executeBatch(new AT_CleanUpCogsStagingTable(), AT_CleanUpCogsStagingTable.DEFAULT_BATCH_SIZE);
        Test.stopTest();

        assertOnlyUnprocessedRecordsRemain();
    }

    @IsTest
    static void batchTracksDeletedCount() {
        AT_CleanUpCogsStagingTable job = new AT_CleanUpCogsStagingTable();
        List<COGSUpdateStagingRecord__c> scope = [
            SELECT Id FROM COGSUpdateStagingRecord__c
            WHERE ProcessingStatus__c IN :AT_CleanUpCogsStagingTable.STATUSES_TO_DELETE
        ];

        Test.startTest();
        job.execute(null, scope);
        job.finish(null);
        Test.stopTest();

        Assert.areEqual(RECORDS_PER_STATUS * 2, job.deletedCount, 'All Success and Skipped records should be counted as deleted');
        Assert.areEqual(0, job.failureCount, 'No failures expected');
        assertOnlyUnprocessedRecordsRemain();
    }

    @IsTest
    static void batchCapturesFailuresForAlreadyDeletedRecords() {
        AT_CleanUpCogsStagingTable job = new AT_CleanUpCogsStagingTable();
        List<COGSUpdateStagingRecord__c> scope = [
            SELECT Id FROM COGSUpdateStagingRecord__c WHERE ProcessingStatus__c = 'Success'
        ];
        delete scope; // deleting again inside the batch forces per-record failures

        Test.startTest();
        job.execute(null, scope);
        job.finish(null);
        Test.stopTest();

        Assert.areEqual(0, job.deletedCount, 'Nothing should be deleted');
        Assert.areEqual(scope.size(), job.failureCount, 'Each already-deleted record should be a failure');
        Assert.isFalse(job.failureMessages.isEmpty(), 'Failure messages should be captured');
    }

    @IsTest
    static void batchHandlesUnexpectedExceptionInExecute() {
        AT_CleanUpCogsStagingTable job = new AT_CleanUpCogsStagingTable();
        // A null element makes Database.delete throw, exercising the catch block
        List<COGSUpdateStagingRecord__c> scope = new List<COGSUpdateStagingRecord__c>{ null };

        Test.startTest();
        job.execute(null, scope);
        job.finish(null);
        Test.stopTest();

        Assert.areEqual(0, job.deletedCount, 'Nothing should be deleted');
        Assert.areEqual(scope.size(), job.failureCount, 'Whole scope should be counted as failed');
        Assert.isTrue(job.failureMessages[0].startsWith('execute: '), 'Exception message should be captured');
        Assert.areEqual(RECORDS_PER_STATUS * ALL_STATUSES.size(), [SELECT COUNT() FROM COGSUpdateStagingRecord__c],
            'No staging records should be deleted');
    }

    @IsTest
    static void batchDoesNothingWhenNoEligibleRecords() {
        delete [SELECT Id FROM COGSUpdateStagingRecord__c WHERE ProcessingStatus__c IN ('Success', 'Skipped')];

        Test.startTest();
        Database.executeBatch(new AT_CleanUpCogsStagingTable());
        Test.stopTest();

        Assert.areEqual(RECORDS_PER_STATUS * 3, [SELECT COUNT() FROM COGSUpdateStagingRecord__c],
            'Holding, Running and Failed records should remain untouched');
    }

    @IsTest
    static void schedulerEnqueuesCleanUpBatch() {
        String cronExpression = '0 0 2 * * ?';

        Test.startTest();
        String jobId = System.schedule('COGS Staging Clean Up Test', cronExpression, new AT_CleanUpCogsStagingTableScheduler());
        Test.stopTest();

        CronTrigger ct = [SELECT Id, CronExpression FROM CronTrigger WHERE Id = :jobId];
        Assert.areEqual(cronExpression, ct.CronExpression, 'Cron expression should match');

        Assert.areEqual(1, [
            SELECT COUNT() FROM AsyncApexJob
            WHERE JobType = 'BatchApex' AND ApexClass.Name = 'AT_CleanUpCogsStagingTable'
        ], 'Scheduler should enqueue the clean-up batch');
    }

    private static void assertOnlyUnprocessedRecordsRemain() {
        Assert.areEqual(0, [
            SELECT COUNT() FROM COGSUpdateStagingRecord__c
            WHERE ProcessingStatus__c IN ('Success', 'Skipped')
        ], 'Success and Skipped records should be deleted');
        Assert.areEqual(RECORDS_PER_STATUS * 3, [
            SELECT COUNT() FROM COGSUpdateStagingRecord__c
            WHERE ProcessingStatus__c IN ('Holding', 'Running', 'Failed')
        ], 'Holding, Running and Failed records should remain');
    }
}
