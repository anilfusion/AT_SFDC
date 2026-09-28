/**
 * @description       : Queueable handler for updating EOS flag on Quote. 
 						Initially part of sync transaction, now moved to Queueable due to 
						recurrsion and rollback cause by CPQ managed package triggers
 * @author            : FusionGS
 * @group             : Quote Triggers
 * @last modified on  : 09-24-2026
 * @last modified by  : FusionGS
 * Mod Log            : 
 * Ver   Date         Author             Modification
 * 1.0   09-24-2026   FusionGS         Initial Version
**/
public class ATFE_EOSUpdateQueueable implements Queueable {

	private List<SBQQ__Quote__c> quotesToProcess;

	public ATFE_EOSUpdateQueueable(List<SBQQ__Quote__c> quoteList) {
		this.quotesToProcess = quoteList;
	}

    public void execute(QueueableContext context) {
		Database.SaveResult[] results = Database.update(quotesToProcess, false);

		logTransaction(results);
    }

	private static void logTransaction(Database.SaveResult[] results) {

		//Send failure email for now - To be moved to Logging Franework once pushed upto Production
		Boolean hasError = false;
		String message = 'EOS Update failed for quotes. Please find the additional details below:';
		Integer iterator = 1;
		for (Database.SaveResult sr : results) {
			if (!sr.isSuccess()) {
				hasError = true;
				message += '\n' + iterator + ': Quote Id = ' + sr.getId() + ' | '; 
				for (Database.Error err : sr.getErrors()) {
					message += ' Error = ' + err.getMessage() + ' | Fields = ' + err.getFields() + ' | ';
				}
				iterator++;
			}
		}

		if(hasError || Test.isRunningTest()) {
            
            //Check if Email Deliverability is enabled or if limits are not hit
            Boolean isEmailDeliverabilityEnabled = true;

            try {
                Messaging.reserveSingleEmailCapacity(1);
            } catch (System.NoAccessException e) {
                isEmailDeliverabilityEnabled = false;
            } catch (System.HandledException e) {
                isEmailDeliverabilityEnabled = false;
            }
            
            
			Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
			String[] toAddresses = (System.Label.EOSUpdateFailureRecipients).split(';');
			mail.setToAddresses(toAddresses);
			mail.setSubject('HIGH PRIORITY: EOS Update Failed!');
			mail.setPlainTextBody(message);
            
            if(isEmailDeliverabilityEnabled) {
				Messaging.SendEmailResult[] sendEmailResults = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
            }
		}
		
	}
}