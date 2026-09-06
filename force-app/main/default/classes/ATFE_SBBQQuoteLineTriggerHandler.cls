/**
* ─────────────────────────────────────────────────────────────────────────────────────────────────┐
* Keeps SBQQ__Quote__c.Contains_EOS_Product__c / Contains_EOS_Service__c in sync with the EOS
* availability of the products on their quote lines. Entry points cover both directions of change:
* edits to the quote lines themselves (EOSProductAvailbility) and Product2 availability changes that
* ripple out to every quote line referencing that product (EOSProductHandler).
* ─────────────────────────────────────────────────────────────────────────────────────────────────
* @author            FusionGS
* @version           1.1
* @createDate        2022-Dec-25
* @systemLayer       Apex Class
* ─────────────────────────────────────────────────────────────────────────────────────────────────
* @changes
* v1.0             FusionGS          2022-Dec-25      Initial version
* v1.1             FusionGS          2026-Aug-24      Merged ProductTriggerHandler.EOSProductHandler
*                                                      in, dropped dead code/debug logging, removed
*                                                      a redundant subquery, added FLS enforcement
* ─────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
public without sharing class ATFE_SBBQQuoteLineTriggerHandler {

    // Without sharing intentionally: EOS availability must stay correct on every affected quote
    // regardless of the record visibility of whichever user/process triggers the sync.

    public static void EOSProductAvailbility(Map<Id, SBQQ__QuoteLine__c> oldQuoteLines, Map<Id, SBQQ__QuoteLine__c> newQuoteLines) {
        Set<Id> quoteIds = new Set<Id>();

        if (Trigger.isInsert || Trigger.isUpdate) {
            for (SBQQ__QuoteLine__c ql : newQuoteLines.values()) {
                if (ql.SBQQ__Quote__c != null) {
                    quoteIds.add(ql.SBQQ__Quote__c);
                }
            }
        }

        if (Trigger.isDelete || Trigger.isUpdate) {
            for (SBQQ__QuoteLine__c ql : oldQuoteLines.values()) {
                if (ql.SBQQ__Quote__c != null) {
                    quoteIds.add(ql.SBQQ__Quote__c);
                }
            }
        }

        EOSupdatesOnQuote(quoteIds);
    }

    @Future
    public static void EOSProductHandler(Set<Id> productIds) {
        Set<Id> quoteIdsToConsider = new Set<Id>();

        for (SBQQ__QuoteLine__c ql : [
            SELECT Id, SBQQ__Quote__c
            FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Product__c IN :productIds
        ]) {
            quoteIdsToConsider.add(ql.SBQQ__Quote__c);
        }

        EOSupdatesOnQuote(quoteIdsToConsider);
    }

    public static void EOSupdatesOnQuote(Set<Id> quoteIds) {
        List<SBQQ__Quote__c> quotesToUpdate = new List<SBQQ__Quote__c>();

        for (SBQQ__Quote__c quote : [
            SELECT Id, Contains_EOS_Product__c, Contains_EOS_Service__c,
               (SELECT Id, Product_Availability__c, SBQQ__Product__r.Family
                FROM SBQQ__LineItems__r
                WHERE Product_Availability__c = false)
            FROM SBQQ__Quote__c
            WHERE Id IN :quoteIds
        ]) {
            Boolean containsEOSProduct = false;
            Boolean containsEOSService = false;

            for (SBQQ__QuoteLine__c qli : quote.SBQQ__LineItems__r) {
                if (qli.SBQQ__Product__r.Family == 'PRODUCT') {
                    containsEOSProduct = true;
                }
                if (qli.SBQQ__Product__r.Family == 'SERVICE') {
                    containsEOSService = true;
                }
                if (containsEOSProduct && containsEOSService) break; // exit early
            }

            // Only update if there's a change
            if (quote.Contains_EOS_Product__c != containsEOSProduct ||
                quote.Contains_EOS_Service__c != containsEOSService) {
                quotesToUpdate.add(new SBQQ__Quote__c(
                    Id = quote.Id,
                    Contains_EOS_Product__c = containsEOSProduct,
                    Contains_EOS_Service__c = containsEOSService
                ));
            }
        }

        if (quotesToUpdate.isEmpty()) {
            return;
        }

        quotesToUpdate = Security.stripInaccessible(AccessType.UPDATABLE, quotesToUpdate).getRecords();
        update quotesToUpdate;
    }
}