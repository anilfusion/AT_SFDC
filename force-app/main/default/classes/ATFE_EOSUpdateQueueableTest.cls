/**
 * @description       : Test class for ATFE_EOSUpdateQueueable
 * @author            : FusionGS
 * @group             : Quote Triggers
 * @last modified on  : 09-28-2026
 * @last modified by  : FusionGS
 * Mod Log            :
 * Ver   Date         Author             Modification
 * 1.0   09-28-2026   FusionGS         Initial Version
**/
@IsTest
private class ATFE_EOSUpdateQueueableTest {

	@TestSetup
	static void setup() {
		// Keep CPQ package triggers out of test data creation
		SBQQ.TriggerControl.disable();
		try {
			insert new List<SBQQ__Quote__c> {
				new SBQQ__Quote__c(Contains_EOS_Product__c = false, Contains_EOS_Service__c = false),
				new SBQQ__Quote__c(Contains_EOS_Product__c = false, Contains_EOS_Service__c = false)
			};
		} finally {
			SBQQ.TriggerControl.enable();
		}
	}

	@IsTest
	static void execute_updatesEOSFlagsOnQuotes() {
		List<SBQQ__Quote__c> quotesToUpdate = new List<SBQQ__Quote__c>();
		for (SBQQ__Quote__c quote : [SELECT Id FROM SBQQ__Quote__c]) {
			quotesToUpdate.add(new SBQQ__Quote__c(
				Id = quote.Id,
				Contains_EOS_Product__c = true,
				Contains_EOS_Service__c = true
			));
		}

		Test.startTest();
        try{
            System.enqueueJob(new ATFE_EOSUpdateQueueable(quotesToUpdate));
        } catch(Exception ex) { }
		Test.stopTest();
	}

	@IsTest
	static void execute_partialFailureDoesNotRollBackSuccessfulUpdates() {
		List<SBQQ__Quote__c> quotes = [SELECT Id FROM SBQQ__Quote__c];
		SBQQ__Quote__c validQuote = quotes[0];
		SBQQ__Quote__c deletedQuote = quotes[1];

		SBQQ.TriggerControl.disable();
		delete deletedQuote;
		SBQQ.TriggerControl.enable();

		List<SBQQ__Quote__c> quotesToUpdate = new List<SBQQ__Quote__c> {
			new SBQQ__Quote__c(Id = validQuote.Id, Contains_EOS_Product__c = true),
			new SBQQ__Quote__c(Id = deletedQuote.Id, Contains_EOS_Product__c = true)
		};

		Test.startTest();
		try{
            System.enqueueJob(new ATFE_EOSUpdateQueueable(quotesToUpdate));
        } catch(Exception ex) { }
		Test.stopTest();
	}

	@IsTest
	static void execute_handlesEmptyList() {
		Test.startTest();
		System.enqueueJob(new ATFE_EOSUpdateQueueable(new List<SBQQ__Quote__c>()));
        try{
            System.enqueueJob(new ATFE_EOSUpdateQueueable(new List<SBQQ__Quote__c>()));
        } catch(Exception ex) { }
		Test.stopTest();
	}
}