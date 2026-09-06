/**
 * Migrated from ProductCogsTrigger (Product2, after update). When a Product2's cost or regional
 * total fields change, enqueues BatchUpdateProductCogs to re-sync Region_COGS__c on the open
 * quote lines that reference that product. Runs only for Products whose RecordType DeveloperName
 * is not JP_Product (and, as in the original source, only for Products with no record type set).
 */
public class TA_Product2_SyncQuoteLineCogs implements TriggerAction.AfterUpdate {

    public void afterUpdate(List<Product2> triggerNew, List<Product2> triggerOld) {
        Map<Id, Product2> oldMap = new Map<Id, Product2>(triggerOld);
        Set<Id> productIds = new Set<Id>();

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
                productIds.add(p.Id);
            }
        }

        if (!productIds.isEmpty()) {
            Database.executeBatch(
                new BatchUpdateProductCogs(productIds),
                Integer.valueOf(System.Label.Cogs_Batch_Size)
            );
        }
    }
}