/**
 * Purges processed COGS staging records (ProcessingStatus__c = Success or Skipped)
 * from COGSUpdateStagingRecord__c. Holding, Running and Failed records are left untouched.
 * Typically invoked from AT_CleanUpCogsStagingTableScheduler.
 */
public without sharing class AT_CleanUpCogsStagingTable implements Database.Batchable<sObject>, Database.Stateful {

    public static final Integer DEFAULT_BATCH_SIZE = 2000;
    @TestVisible private static final Set<String> STATUSES_TO_DELETE = new Set<String>{ 'Success', 'Skipped' };

    @TestVisible private Integer deletedCount = 0;
    @TestVisible private Integer failureCount = 0;
    @TestVisible private final List<String> failureMessages = new List<String>();

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id
            FROM COGSUpdateStagingRecord__c
            WHERE ProcessingStatus__c IN :STATUSES_TO_DELETE
        ]);
    }

    public void execute(Database.BatchableContext bc, List<COGSUpdateStagingRecord__c> scope) {
        try {
            List<Database.DeleteResult> results = Database.delete(scope, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    deletedCount++;
                    continue;
                }
                failureCount++;
                for (Database.Error err : results[i].getErrors()) {
                    failureMessages.add(scope[i].Id + ': ' + err.getStatusCode() + ' - ' + err.getMessage());
                }
            }
        } catch (Exception e) {
            failureCount += scope.size();
            failureMessages.add('execute: ' + e.getMessage());
            Logger.logApexException(
                e,
                'Batch Apex',
                'COGS Staging Clean Up',
                bc == null ? null : String.valueOf(bc.getJobId()),
                new Map<String, Object>{ 'phase' => 'execute' }
            );
            Logger.commitLogs();
        }
    }

    public void finish(Database.BatchableContext bc) {
        String logMessage = 'The batch Apex job "AT_CleanUpCogsStagingTable" deleted ' + deletedCount
            + ' staging record(s) with ' + failureCount + ' failure(s). Failure Information: '
            + (failureMessages.isEmpty() ? 'N/A' : String.join(failureMessages, '\\n'));

        Logger.logTransaction(
            'Generic Transaction',
            'Batch Apex',
            logMessage,
            bc == null ? null : String.valueOf(bc.getJobId())
        );
        Logger.commitLogs();
    }
}
