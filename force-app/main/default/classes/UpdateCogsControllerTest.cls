/**
 * Unit tests for UpdateCogsController (Apex backing the Update COGS UI).
 */
@isTest
private class UpdateCogsControllerTest {

    private static Integer idSeq = 1;

    /** A syntactically valid (but non-existent) Product2 id. */
    private static String fakeProductId() {
        String suffix = String.valueOf(idSeq++);
        return Product2.SObjectType.getDescribe().getKeyPrefix() + '0'.repeat(12 - suffix.length()) + suffix;
    }

    private static void createStaging(String status, Integer count) {
        List<COGSUpdateStagingRecord__c> records = new List<COGSUpdateStagingRecord__c>();
        for (Integer i = 0; i < count; i++) {
            records.add(new COGSUpdateStagingRecord__c(
                ProductId__c = fakeProductId(),
                ProcessingStatus__c = status
            ));
        }
        insert records;
    }

    @isTest
    static void getStatus_returnsCountsAndNoJob() {
        createStaging('Holding', 3);
        createStaging('Running', 2);
        createStaging('Failed', 1);
        createStaging('Success', 4);

        Test.startTest();
        Map<String, String> status = UpdateCogsController.getStatus();
        Test.stopTest();

        System.assertEquals('3', status.get('pendingCount'), 'Holding records are reported as pending');
        System.assertEquals('2', status.get('runningCount'), 'Running records count');
        System.assertEquals('1', status.get('failedCount'), 'Failed records count');
        System.assertEquals('false', status.get('isJobRunning'), 'No batch job has been started');
        System.assertEquals('No Jobs Running', status.get('jobStatus'), 'Default job status text');
    }

    @isTest
    static void doUpdate_launchesBatchAndReportsJob() {
        createStaging('Holding', 2);

        Test.startTest();
        UpdateCogsController.doUpdate();
        // While the job is still queued (before stopTest runs it) the UI should report it.
        Map<String, String> statusWhileQueued = UpdateCogsController.getStatus();
        Test.stopTest();

        System.assertEquals(1, [SELECT count() FROM AsyncApexJob WHERE ApexClass.Name = 'AT_ProductCogsBatch'],
            'doUpdate should enqueue AT_ProductCogsBatch');
        System.assertEquals('0', statusWhileQueued.get('pendingCount'),
            'Starting the batch moves Holding records to Running');
        System.assertEquals('2', statusWhileQueued.get('runningCount'), 'Records are Running while the job is queued');
        System.assertEquals('true', statusWhileQueued.get('isJobRunning'), 'A queued job is reported as running');
        System.assert(statusWhileQueued.get('jobStatus').startsWith('A job is'), 'Job status text names the job state');

        // No quote lines exist for these products, so the batch finishes and skips them.
        Map<String, String> statusAfter = UpdateCogsController.getStatus();
        System.assertEquals('0', statusAfter.get('runningCount'), 'No records remain Running after the job finishes');
        System.assertEquals(2, [SELECT count() FROM COGSUpdateStagingRecord__c WHERE ProcessingStatus__c = 'Skipped'],
            'Records with no open quote lines are marked Skipped');
    }

    /** Database.executeBatch can't be called from a future method - forces the AsyncException path. */
    @future
    private static void callDoUpdateFromFuture() {
        UpdateCogsController.doUpdate();
    }

    @isTest
    static void doUpdate_asyncException_isLoggedAndRethrown() {
        createStaging('Holding', 1);

        Exception thrown;
        try {
            Test.startTest();
            callDoUpdateFromFuture();
            Test.stopTest();
        } catch (Exception e) {
            thrown = e;
        }

        System.assertNotEquals(null, thrown, 'The AsyncException should be rethrown to the caller');
        System.assert(thrown instanceof System.AsyncException, 'Expected AsyncException but got ' + thrown.getTypeName());
        System.assertEquals(0, [SELECT count() FROM AsyncApexJob WHERE ApexClass.Name = 'AT_ProductCogsBatch'],
            'No batch job should be enqueued when executeBatch fails');
    }

    @isTest
    static void updateToReadyForRetry_movesFailedToHolding() {
        createStaging('Failed', 3);
        createStaging('Success', 1);

        Test.startTest();
        UpdateCogsController.updateToReadyForRetry();
        Test.stopTest();

        System.assertEquals(0, [SELECT count() FROM COGSUpdateStagingRecord__c WHERE ProcessingStatus__c = 'Failed'],
            'All failed records should be reset');
        System.assertEquals(3, [SELECT count() FROM COGSUpdateStagingRecord__c WHERE ProcessingStatus__c = 'Holding'],
            'Failed records should move back to Holding');
        System.assertEquals(1, [SELECT count() FROM COGSUpdateStagingRecord__c WHERE ProcessingStatus__c = 'Success'],
            'Non-failed records are left untouched');
    }

    @isTest
    static void updateToReadyForRetry_noFailedRecords_isNoOp() {
        createStaging('Success', 2);

        Test.startTest();
        UpdateCogsController.updateToReadyForRetry();
        Test.stopTest();

        System.assertEquals(2, [SELECT count() FROM COGSUpdateStagingRecord__c WHERE ProcessingStatus__c = 'Success'],
            'Nothing changes when there are no failed records');
    }
}
