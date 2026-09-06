/**
 * ─────────────────────────────────────────────────────────────────────────────────────────────────┐
 * LoggerQueueable
 *
 * Persists the `System_Log__c` records collected by {@link Logger} during a transaction. Running the
 * insert in a queueable keeps the logging DML out of the caller's transaction, so a logging failure
 * can never roll back business data and the log write does not count against the caller's limits.
 *
 * `Database.insert(logs, false)` is used so a single bad record cannot lose the rest of the batch;
 * failures are written to the debug log (there is nowhere safer to send them from here).
 * ─────────────────────────────────────────────────────────────────────────────────────────────────
 * @author            AT_Salesforce
 * @systemLayer       Apex Class
 * ─────────────────────────────────────────────────────────────────────────────────────────────────┘
 */
public without sharing class LoggerQueueable implements Queueable {
    private final List<System_Log__c> logs;

    public LoggerQueueable(List<System_Log__c> logs) {
        this.logs = logs == null ? new List<System_Log__c>() : logs;
    }

    public void execute(QueueableContext context) {
        persist(this.logs);
    }

    /**
     * Inserts the supplied logs with partial success. Safe to call synchronously as a fallback when
     * a queueable cannot be enqueued. Never throws.
     */
    public static void persist(List<System_Log__c> logs) {
        if (logs == null || logs.isEmpty()) {
            return;
        }

        try {
            List<Database.SaveResult> results = Database.insert(logs, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    continue;
                }
                for (Database.Error err : results[i].getErrors()) {
                    System.debug(
                        LoggingLevel.ERROR,
                        'LoggerQueueable: failed to insert System_Log__c [' +
                            logs[i].Transaction_ID__c +
                            '] - ' +
                            err.getStatusCode() +
                            ': ' +
                            err.getMessage()
                    );
                }
            }
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'LoggerQueueable: unexpected failure inserting ' + logs.size() + ' logs - ' + e.getMessage()
            );
        }
    }
}