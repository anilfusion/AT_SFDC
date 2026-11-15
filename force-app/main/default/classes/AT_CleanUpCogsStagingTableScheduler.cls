/**
 * Schedules AT_CleanUpCogsStagingTable. Example (daily at 2 AM):
 *   System.schedule('COGS Staging Clean Up', '0 0 2 * * ?', new AT_CleanUpCogsStagingTableScheduler());
 */
public without sharing class AT_CleanUpCogsStagingTableScheduler implements Schedulable {

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new AT_CleanUpCogsStagingTable(), AT_CleanUpCogsStagingTable.DEFAULT_BATCH_SIZE);
    }
}
