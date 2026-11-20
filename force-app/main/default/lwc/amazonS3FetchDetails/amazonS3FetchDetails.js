import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import syncFileDetails from '@salesforce/apex/S3FilesHelper.syncFileDetails';
import { errorMessage } from 'c/s3FileService';

/**
 * "Fetch File Details" button: Apex reads the file stored in S3 for this Software_File__c
 * and writes its details (key, size, ETag, date) onto the record. No AWS credentials or
 * SDK in the browser.
 */
export default class AmazonS3FetchDetails extends LightningElement {
    @api recordId;
    isLoading = false;

    async fetchFileDetails() {
        this.isLoading = true;
        try {
            const file = await syncFileDetails({ recordId: this.recordId });
            if (file) {
                this.showToast('Success', `File details have been updated from ${file.name}.`, 'success');
            } else {
                this.showToast('Info', 'File not found on AWS.', 'info');
            }
        } catch (error) {
            this.showToast('Error', errorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}