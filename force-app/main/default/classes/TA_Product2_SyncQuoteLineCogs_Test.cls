/**
 * Unit tests for TA_Product2_SyncQuoteLineCogs.
 *
 * The TriggerAction is exercised directly – afterUpdate() is called with hand-built
 * old / new Product2 lists – so the tests stay independent of Product2 record-type
 * defaults, the read-only regional Total_* formula fields and CPQ quote data.
 * Product2 records are built through JSON.deserialize so the formula fields (and,
 * where needed, RecordTypeId) can be given explicit values.
 *
 * When a Product2 with no record type has a cost / regional total change, the class
 * enqueues BatchUpdateProductCogs. Each test asserts on the number of async calls
 * made (1 => the batch was enqueued, 0 => it was not).
 */
@isTest
private class TA_Product2_SyncQuoteLineCogs_Test {

    private static Integer idSeq = 1;

    private static final String PRODUCT2_PREFIX = Product2.SObjectType.getDescribe().getKeyPrefix();
    private static final String RECORDTYPE_PREFIX = '012';

    private static Id fakeId(String keyPrefix) {
        String suffix = String.valueOf(idSeq++);
        return Id.valueOf(keyPrefix + '0'.repeat(12 - suffix.length()) + suffix);
    }

    /**
     * Builds an in-memory Product2. Total_* are formula fields, so the record is
     * assembled as JSON and deserialized to bypass the "field is not writeable" check.
     */
    private static Product2 buildProduct(
        Id recId, Decimal cost, Decimal na, Decimal emea, Decimal apac, Decimal csa, Id recordTypeId
    ) {
        Map<String, Object> raw = new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'Product2' },
            'Id' => recId,
            'ATFE_Cost__c' => cost,
            'Total_NA__c' => na,
            'Total_EMEA__c' => emea,
            'Total_APAC__c' => apac,
            'Total_CSA__c' => csa
        };
        if (recordTypeId != null) {
            raw.put('RecordTypeId', recordTypeId);
        }
        return (Product2) JSON.deserialize(JSON.serialize(raw), Product2.class);
    }

    /**
     * Runs the TriggerAction inside a start/stop test window and returns the number
     * of async calls (future / batch) it queued.
     */
    private static Integer asyncCallsFor(List<Product2> newList, List<Product2> oldList) {
        Test.startTest();
        new TA_Product2_SyncQuoteLineCogs().afterUpdate(newList, oldList);
        Integer asyncCalls = Limits.getAsyncCalls();
        Test.stopTest();
        return asyncCalls;
    }

    @isTest
    static void test_costChange_enqueuesCogsBatch() {
        Id pid = fakeId(PRODUCT2_PREFIX);
        List<Product2> oldList = new List<Product2>{ buildProduct(pid, 100, 10, 20, 30, 40, null) };
        List<Product2> newList = new List<Product2>{ buildProduct(pid, 250, 10, 20, 30, 40, null) };

        System.assertEquals(1, asyncCallsFor(newList, oldList),
            'A change to ATFE_Cost__c should enqueue BatchUpdateProductCogs');
    }

    @isTest
    static void test_regionalTotalChange_enqueuesCogsBatch() {
        // ATFE_Cost__c unchanged; only Total_CSA__c differs – exercises the later
        // operands of the OR condition.
        Id pid = fakeId(PRODUCT2_PREFIX);
        List<Product2> oldList = new List<Product2>{ buildProduct(pid, 100, 10, 20, 30, 40, null) };
        List<Product2> newList = new List<Product2>{ buildProduct(pid, 100, 10, 20, 30, 99, null) };

        System.assertEquals(1, asyncCallsFor(newList, oldList),
            'A change to a regional total should enqueue BatchUpdateProductCogs');
    }

    @isTest
    static void test_noRelevantChange_doesNotEnqueue() {
        Id pid = fakeId(PRODUCT2_PREFIX);
        List<Product2> oldList = new List<Product2>{ buildProduct(pid, 100, 10, 20, 30, 40, null) };
        List<Product2> newList = new List<Product2>{ buildProduct(pid, 100, 10, 20, 30, 40, null) };

        System.assertEquals(0, asyncCallsFor(newList, oldList),
            'No cost / total change should not enqueue the COGS batch');
    }

    @isTest
    static void test_multipleProducts_singleBatchForAllChanged() {
        Id changedA = fakeId(PRODUCT2_PREFIX);
        Id changedB = fakeId(PRODUCT2_PREFIX);
        Id unchanged = fakeId(PRODUCT2_PREFIX);
        List<Product2> oldList = new List<Product2>{
            buildProduct(changedA, 100, 10, 20, 30, 40, null),
            buildProduct(changedB, 100, 10, 20, 30, 40, null),
            buildProduct(unchanged, 100, 10, 20, 30, 40, null)
        };
        List<Product2> newList = new List<Product2>{
            buildProduct(changedA, 150, 10, 20, 30, 40, null),
            buildProduct(changedB, 100, 10, 20, 30, 77, null),
            buildProduct(unchanged, 100, 10, 20, 30, 40, null)
        };

        System.assertEquals(1, asyncCallsFor(newList, oldList),
            'All changed products should be handled by a single batch execution');
    }

    @isTest
    static void test_productWithRecordType_isSkipped() {
        // Migrated behaviour: only Products with no record type are processed.
        Id pid = fakeId(PRODUCT2_PREFIX);
        Id rtId = fakeId(RECORDTYPE_PREFIX);
        List<Product2> oldList = new List<Product2>{ buildProduct(pid, 100, 10, 20, 30, 40, rtId) };
        List<Product2> newList = new List<Product2>{ buildProduct(pid, 250, 10, 20, 30, 40, rtId) };

        System.assertEquals(0, asyncCallsFor(newList, oldList),
            'A Product with a record type set should be skipped');
    }

    @isTest
    static void test_helper_excludeJpProduct_passesThroughNonJpProducts() {
        List<Product2> input = new List<Product2>{
            buildProduct(fakeId(PRODUCT2_PREFIX), 100, 10, 20, 30, 40, null),
            buildProduct(fakeId(PRODUCT2_PREFIX), 100, 10, 20, 30, 40, null)
        };

        Test.startTest();
        List<Product2> result = TA_Product2_TriggerHelper.excludeJpProduct(input);
        Test.stopTest();

        System.assertEquals(input.size(), result.size(),
            'Products that are not the JP_Product record type should pass through unchanged');
    }
}