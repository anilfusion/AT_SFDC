/**
 * ─────────────────────────────────────────────────────────────────────────────────────────────────┐
 * LoggerCleanupBatch
 *
 * Deletes `System_Log__c` records older than the retention window (3 months by default) and empties
 * them from the Recycle Bin so they do not count against org storage.
 *
 * Also implements `Schedulable` so it can be scheduled directly:
 * ┌───────────────────────────────────────────────────────────────────────────────────────────────┐
 * │  // every day at 1am                                                                           │
 * │  System.schedule('System Log Cleanup', '0 0 1 * * ?', new LoggerCleanupBatch());               │
 * └───────────────────────────────────────────────────────────────────────────────────────────────┘
 * ─────────────────────────────────────────────────────────────────────────────────────────────────
 * @author            AT_Salesforce
 * @systemLayer       Apex Class
 * ─────────────────────────────────────────────────────────────────────────────────────────────────┘
 */
public without sharing class LoggerCleanupBatch implements Database.Batchable<SObject>, Schedulable {
    private static final Integer DEFAULT_RETENTION_MONTHS = 3;
    private static final Integer DEFAULT_BATCH_SIZE = 2000;

    private final Integer retentionMonths;

    public LoggerCleanupBatch() {
        this(DEFAULT_RETENTION_MONTHS);
    }

    public LoggerCleanupBatch(Integer retentionMonths) {
        this.retentionMonths = (retentionMonths == null || retentionMonths < 1)
            ? DEFAULT_RETENTION_MONTHS
            : retentionMonths;
    }

    // ── Schedulable ──────────────────────────────────────────────────────────────
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new LoggerCleanupBatch(this.retentionMonths), DEFAULT_BATCH_SIZE);
    }

    // ── Batchable ───────────────────────────────────────────────────────────────
    public Database.QueryLocator start(Database.BatchableContext bc) {
        Datetime cutoff = Datetime.now().addMonths(-this.retentionMonths);
        return Database.getQueryLocator(
            [SELECT Id FROM System_Log__c WHERE CreatedDate < :cutoff]
        );
    }

    public void execute(Database.BatchableContext bc, List<System_Log__c> scope) {
        if (scope == null || scope.isEmpty()) {
            return;
        }

        List<Database.DeleteResult> deleteResults = Database.delete(scope, false);
        Integer failures = 0;
        List<Id> deletedIds = new List<Id>();
        for (Integer i = 0; i < deleteResults.size(); i++) {
            if (deleteResults[i].isSuccess()) {
                deletedIds.add(scope[i].Id);
                continue;
            }
            failures++;
            for (Database.Error err : deleteResults[i].getErrors()) {
                System.debug(
                    LoggingLevel.ERROR,
                    'LoggerCleanupBatch: failed to delete ' + scope[i].Id + ' - ' + err.getStatusCode() + ': ' + err.getMessage()
                );
            }
        }

        if (!deletedIds.isEmpty()) {
            try {
                Database.emptyRecycleBin(deletedIds);
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'LoggerCleanupBatch: emptyRecycleBin failed - ' + e.getMessage());
            }
        }

        if (failures > 0) {
            System.debug(LoggingLevel.WARN, 'LoggerCleanupBatch: ' + failures + ' of ' + scope.size() + ' deletes failed this batch.');
        }
    }

    public void finish(Database.BatchableContext bc) {
        // No notification by design - this is routine housekeeping. Add an email here if desired.
    }
}