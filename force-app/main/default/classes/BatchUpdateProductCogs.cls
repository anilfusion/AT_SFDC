/**
* ─────────────────────────────────────────────────────────────────────────────────────────────────┐
* Syncs SBQQ__QuoteLine__c.Region_COGS__c on open quotes whenever the related Product2's regional
* COGS values change. The target field is chosen from the quote's Quote_To_Region__c via
* REGION_TO_COGS_FIELD, so adding a new region only requires extending that map.
* ─────────────────────────────────────────────────────────────────────────────────────────────────
* @author            FusionGS
* @version           2.0
* @createDate        2023-Mar-01
* @systemLayer       Apex Class
* ─────────────────────────────────────────────────────────────────────────────────────────────────
* @changes
* v1.0             FusionGS          2023-Mar-01      Initial version
* v2.0             FusionGS          2026-Aug-15      Partial-success DML with error capture, FLS
*                                                      enforcement, metadata-driven region mapping,
*                                                      recursion-guard reset, failure reporting
* ─────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
public without sharing class BatchUpdateProductCogs implements Database.Batchable<sObject>, Database.Stateful {

    // Runs without sharing intentionally: COGS sync must reach every in-scope quote line
    // regardless of the record visibility of whichever user/process enqueues the batch.

    private static final Map<String, Schema.SObjectField> REGION_TO_COGS_FIELD = new Map<String, Schema.SObjectField>{
        'NA' => Product2.Total_NA__c,
        'EMEA' => Product2.Total_EMEA__c,
        'CSA' => Product2.Total_CSA__c,
        'APAC' => Product2.Total_APAC__c
    };

    private final Set<Id> productIds;
    private Integer failureCount = 0;
    private final List<String> failureMessages = new List<String>();

    public BatchUpdateProductCogs(Set<Id> productIds) {
        this.productIds = productIds;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Region_COGS__c,
                   SBQQ__Quote__r.Quote_To_Region__c,
                   SBQQ__Product__r.Total_APAC__c,
                   SBQQ__Product__r.Total_CSA__c,
                   SBQQ__Product__r.Total_EMEA__c,
                   SBQQ__Product__r.Total_NA__c
            FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Product__c IN :productIds
              AND SBQQ__Quote__r.SBQQ__Opportunity2__r.IsClosed = FALSE
              AND COGS_Sync__c = TRUE
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SBQQ__QuoteLine__c> scope) {
        List<SBQQ__QuoteLine__c> updates = new List<SBQQ__QuoteLine__c>();

        for (SBQQ__QuoteLine__c quoteLine : scope) {
            Schema.SObjectField cogsField = REGION_TO_COGS_FIELD.get(quoteLine.SBQQ__Quote__r.Quote_To_Region__c);
            if (cogsField == null) {
                continue; // Unmapped/blank region - nothing to sync for this line
            }

            updates.add(new SBQQ__QuoteLine__c(
                Id = quoteLine.Id,
                Region_COGS__c = (Decimal) quoteLine.SBQQ__Product__r.get(cogsField)
            ));
        }

        if (updates.isEmpty()) {
            return;
        }

        updates = Security.stripInaccessible(AccessType.UPDATABLE, updates).getRecords();

        ATFE_PLMUpdateOnQuickQuoteHelper.DoNotRunATFE_SBBQQuoteLineTrigger = true;
        try {
            List<Database.SaveResult> results = Database.update(updates, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    continue;
                }
                failureCount++;
                for (Database.Error err : results[i].getErrors()) {
                    failureMessages.add(updates[i].Id + ': ' + err.getStatusCode() + ' - ' + err.getMessage());
                }
            }
        } finally {
            ATFE_PLMUpdateOnQuickQuoteHelper.DoNotRunATFE_SBBQQuoteLineTrigger = false;
        }
    }

    public void finish(Database.BatchableContext bc) {
        AsyncApexJob apexJob = [
            SELECT Id, Status, NumberOfErrors, TotalJobItems, CreatedBy.Email
            FROM AsyncApexJob
            WHERE Id = :bc.getJobId()
        ];

        if (String.isBlank(apexJob.CreatedBy.Email)) {
            return;
        }

        String body = 'The batch Apex job "BatchUpdateProductCogs" processed ' + apexJob.TotalJobItems
            + ' batch(es) with ' + apexJob.NumberOfErrors + ' batch-level failure(s).\n'
            + 'Quote line update failures: ' + failureCount;

        /*if (!failureMessages.isEmpty()) {
            Integer previewCount = Math.min(failureMessages.size(), 20);
            body += '\n\nFirst ' + previewCount + ' error(s):\n'
                + String.join(new List<String>(failureMessages).subList(0, previewCount), '\n');
        }*/

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[] { apexJob.CreatedBy.Email });
        mail.setSubject('Apex Job status is ' + apexJob.Status);
        mail.setPlainTextBody(body);

        try {
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'BatchUpdateProductCogs.finish: failed to send completion email - ' + ex.getMessage());
        }
    }
}