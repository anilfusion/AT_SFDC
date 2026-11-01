public without sharing class AT_ProductCogsBatch implements Database.Batchable<sObject>, Database.Stateful {

    private static final Map<String, Schema.SObjectField> REGION_TO_COGS_FIELD = new Map<String, Schema.SObjectField>{
        'NA' => Product2.Total_NA__c,
        'EMEA' => Product2.Total_EMEA__c,
        'CSA' => Product2.Total_CSA__c,
        'APAC' => Product2.Total_APAC__c
    };

    @TestVisible private final Set<Id> productIds = new Set<Id>();
    @TestVisible private Integer failureCount = 0;
    @TestVisible private final List<String> failureMessages = new List<String>();
	@TestVisible private static List<COGSUpdateStagingRecord__c> allStagingRecords = new List<COGSUpdateStagingRecord__c>();
	@TestVisible private Map<String, List<COGSUpdateStagingRecord__c>> stagingRecordsByProductIdMap = new Map<String, List<COGSUpdateStagingRecord__c>>();
	@TestVisible private static Set<String> productIdsForCurrentChunk = new Set<String>();

    public AT_ProductCogsBatch() {
		for(COGSUpdateStagingRecord__c eachStagingRecord : [SELECT Id, ProductId__c 
														    FROM COGSUpdateStagingRecord__c
														    WHERE ProcessingStatus__c = 'Holding']){
			eachStagingRecord.ProcessingStatus__c = 'Running';
			allStagingRecords.add(eachStagingRecord);
            if(stagingRecordsByProductIdMap.containsKey(eachStagingRecord.ProductId__c)){
                List<COGSUpdateStagingRecord__c> tempList = stagingRecordsByProductIdMap.get(eachStagingRecord.ProductId__c);
                tempList.add(eachStagingRecord);
                stagingRecordsByProductIdMap.put(eachStagingRecord.ProductId__c, tempList);
            } else {
                stagingRecordsByProductIdMap.put(eachStagingRecord.ProductId__c, new List<COGSUpdateStagingRecord__c>{eachStagingRecord});
            }
			productIds.add(eachStagingRecord.ProductId__c);
		}
		update allStagingRecords;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        try {
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
        } catch (Exception e) {
            // The job cannot run without a scope - log it, then let the platform mark the job failed.
            logException(e, 'start', bc);
            throw e;
        }
    }

    public void execute(Database.BatchableContext bc, List<SBQQ__QuoteLine__c> scope) {
        try {
            List<SBQQ__QuoteLine__c> updates = new List<SBQQ__QuoteLine__c>();
			productIdsForCurrentChunk = new Set<String>();
			List<COGSUpdateStagingRecord__c> stagingRecordsToUpdateStatus = new List<COGSUpdateStagingRecord__c>();
			Map<String, String> qliIdWithProductIdMap = new Map<String, String>();

            for (SBQQ__QuoteLine__c quoteLine : scope) {
				productIdsForCurrentChunk.add(quoteLine.SBQQ__Product__c);
				qliIdWithProductIdMap.put(quoteLine.Id, quoteLine.SBQQ__Product__c);
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

            ATFE_PLMUpdateOnQuickQuoteHelper.DoNotRunATFE_SBBQQuoteLineTrigger = true;
            try {
                List<Database.SaveResult> results = Database.update(updates, false);
                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess()) {
                        List<COGSUpdateStagingRecord__c> relatedStagingRecords = stagingRecordsByProductIdMap.get(qliIdWithProductIdMap.get(results[i].getId()));
                        System.debug(results[i].getId());
                        System.debug(qliIdWithProductIdMap.keyset());
                        System.debug(stagingRecordsByProductIdMap.keyset());
                        if(relatedStagingRecords != null && relatedStagingRecords.size() > 0) {
                            for(COGSUpdateStagingRecord__c eachStagingRecord : relatedStagingRecords) {
                                eachStagingRecord.ProcessingStatus__c = 'Success';
						        stagingRecordsToUpdateStatus.add(eachStagingRecord);
                            }
                        }
                        continue;
                    }
                    failureCount++;
                    for (Database.Error err : results[i].getErrors()) {
                        failureMessages.add(updates[i].Id + ': ' + err.getStatusCode() + ' - ' + err.getMessage());
                    }
                    List<COGSUpdateStagingRecord__c> relatedStagingRecords = stagingRecordsByProductIdMap.get(qliIdWithProductIdMap.get(results[i].getId()));
                    if(relatedStagingRecords != null && relatedStagingRecords.size() > 0) {
                        for(COGSUpdateStagingRecord__c eachStagingRecord : relatedStagingRecords) {
                            eachStagingRecord.ProcessingStatus__c = 'Failed';
                            stagingRecordsToUpdateStatus.add(eachStagingRecord);
                        }
                    }
                }
            } finally {
                ATFE_PLMUpdateOnQuickQuoteHelper.DoNotRunATFE_SBBQQuoteLineTrigger = false;
				update stagingRecordsToUpdateStatus;
            }
        } catch (Exception e) {
            failureCount++;
            failureMessages.add('execute: ' + e.getMessage());
            logException(e, 'execute', bc);
			failAllStagingRecordsForCurrentChunk();
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

        String body = 'The batch Apex job "AT_ProductCogsBatch" processed ' + apexJob.TotalJobItems
            + ' batch(es) with ' + apexJob.NumberOfErrors + ' batch-level failure(s).\n'
            + 'Quote line update failures: ' + failureCount;
			
        try {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new String[] { apexJob.CreatedBy.Email });
            mail.setSubject('Apex Job status is ' + apexJob.Status);
            mail.setPlainTextBody(body);

            try {
                Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
            } catch (Exception ex) {
                logException(ex, 'finish', bc);
            }
        } catch (Exception e) {
            // finish() must never throw - the batch work is already committed at this point.
            logException(e, 'finish', bc);
        } finally {
            List<COGSUpdateStagingRecord__c> allStagingRecordsToSkip = new List<COGSUpdateStagingRecord__c>();
            for(COGSUpdateStagingRecord__c eachStagingRecord : [SELECT Id, ProductId__c 
                                                                FROM COGSUpdateStagingRecord__c
                                                                WHERE ProcessingStatus__c = 'Running']){
                eachStagingRecord.ProcessingStatus__c = 'Skipped';
                allStagingRecordsToSkip.add(eachStagingRecord);
            }
            update allStagingRecordsToSkip;

			String logMessage = body + '. Failure Information: ' + (failureMessages.size() > 0 ? String.join(failureMessages, '\\n')  : 'N/A');
            Logger.logTransaction(
				'Generic Transaction',
				'Batch Apex',
				logMessage,
				bc == null ? null : String.valueOf(bc.getJobId())
			);
			Logger.commitLogs();
        }
    }

    /**
     * Captures an unexpected exception through the Logger framework as a Batch Apex exception.
     * Logger.commitLogs() never throws, so a failure inside the logging framework itself cannot
     * mask the original error or abort the batch.
     */
    private static void logException(Exception e, String phase, Database.BatchableContext bc) {
        Logger.logApexException(
            e,
            'Batch Apex',
            'Product COGS Sync',
            bc == null ? null : String.valueOf(bc.getJobId()),
            new Map<String, Object>{ 'phase' => phase }
        );
        Logger.commitLogs();
    }

	private static void failAllStagingRecordsForCurrentChunk() {
		List<COGSUpdateStagingRecord__c> stagingRecordsToMarkFailed = new List<COGSUpdateStagingRecord__c>();
		for(COGSUpdateStagingRecord__c eachStagingRecord : allStagingRecords) {
			if(productIdsForCurrentChunk.contains(eachStagingRecord.ProductId__c)){
				eachStagingRecord.ProcessingStatus__c = 'Failed';
				stagingRecordsToMarkFailed.add(eachStagingRecord);
			}
		}
		update stagingRecordsToMarkFailed;
	}
}