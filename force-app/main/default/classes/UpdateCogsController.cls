public without sharing class UpdateCogsController {

	@AuraEnabled
	public static Map<String, String> getStatus() {
		Map<String, String> cogsStatusData = new Map<String, String>();
		Boolean isJobRunning = false;

		Integer pendingCount = [SELECT count() FROM COGSUpdateStagingRecord__c WHERE ProcessingStatus__c = 'Holding'];
		Integer runningCount = [SELECT count() FROM COGSUpdateStagingRecord__c WHERE ProcessingStatus__c = 'Running'];
		Integer failedCount = [SELECT count() FROM COGSUpdateStagingRecord__c WHERE ProcessingStatus__c = 'Failed'];
		String jobStatus = 'No Jobs Running';
		List<AsyncApexJob> jobDetails = [SELECT Id, Status FROM AsyncApexJob WHERE ApexClass.Name = 'AT_ProductCogsBatch' ORDER BY CreatedDate DESC LIMIT 1];
		if(!jobDetails.isEmpty()){
			if(jobDetails[0].Status == 'Holding' || jobDetails[0].Status == 'Preparing' || jobDetails[0].Status == 'Processing' || jobDetails[0].Status == 'Queued') {
				jobStatus = 'A job is ' + jobDetails[0].Status;
				isJobRunning = true;
			}
		}
		
		cogsStatusData.put('isJobRunning', String.valueOf(isJobRunning));
		cogsStatusData.put('pendingCount', String.valueOf(pendingCount));
		cogsStatusData.put('runningCount', String.valueOf(runningCount));
		cogsStatusData.put('failedCount', String.valueOf(failedCount));
		cogsStatusData.put('jobStatus', jobStatus);
		return cogsStatusData;
	}

	@AuraEnabled
	public static void doUpdate() {
		try{
			AT_ProductCogsBatch inst = new AT_ProductCogsBatch();
			Database.executeBatch(inst, 200);
		} catch (System.AsyncException ex) {
            Logger.logApexException(
				ex,
				'Batch Apex',
				'COGS Update',
				UserInfo.getUserId(),
				new Map<String, Object>()
			);
			Logger.commitLogs();
            throw ex;
        }
	}

}