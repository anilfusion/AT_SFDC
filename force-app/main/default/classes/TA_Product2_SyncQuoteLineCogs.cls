/**
 * Migrated from ProductCogsTrigger (Product2, after update). When a Product2's cost or regional
 * total fields change, enqueues BatchUpdateProductCogs to re-sync Region_COGS__c on the open
 * quote lines that reference that product. Runs only for Products whose RecordType DeveloperName
 * is not JP_Product (and, as in the original source, only for Products with no record type set).
 *
 * An unexpected failure while enqueuing the batch (e.g. a missing/invalid Cogs_Batch_Size label,
 * or the per-transaction async-job ceiling) is captured through the Logger framework and swallowed:
 * this is a best-effort background re-sync and must not roll back the user's Product2 update.
 */
public without sharing class TA_Product2_SyncQuoteLineCogs implements TriggerAction.AfterUpdate {

    public void afterUpdate(List<Product2> triggerNew, List<Product2> triggerOld) {
        List<COGSUpdateStagingRecord__c> stagingRecordsToCreate = new List<COGSUpdateStagingRecord__c>();
        try {
            Map<Id, Product2> oldMap = new Map<Id, Product2>(triggerOld);

            for (Product2 p : TA_Product2_TriggerHelper.excludeJpProduct(triggerNew)) {
                // Migrated as-is from ProductCogsTrigger: the original source only considered
                // Products with no record type.
                if (p.RecordTypeId != null) {
                    continue;
                }

                Product2 oldProduct = oldMap.get(p.Id);
                if (p.ATFE_Cost__c != oldProduct.ATFE_Cost__c
                    || p.Total_NA__c != oldProduct.Total_NA__c
                    || p.Total_EMEA__c != oldProduct.Total_EMEA__c
                    || p.Total_APAC__c != oldProduct.Total_APAC__c
                    || p.Total_CSA__c != oldProduct.Total_CSA__c) {
                        stagingRecordsToCreate.add(
                        	new COGSUpdateStagingRecord__c(
                            	ProductId__c = p.Id,
                                ProcessingStatus__c = 'Holding'
                            )
                        );
                }
            }

            if (!stagingRecordsToCreate.isEmpty()) {
                insert stagingRecordsToCreate;
            }
        } catch (Exception e) {
            // Logger.commitLogs() never throws, so no defensive wrapper is needed here.
            Logger.logApexException(
                e,
                'Apex Trigger',
                'Product COGS Sync',
                triggerNew.isEmpty() ? null : String.valueOf(triggerNew[0].Id),
                new Map<String, Object>{ 'Staging Records' => stagingRecordsToCreate }
            );
            Logger.commitLogs();
        }
    }
}