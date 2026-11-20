import { api, wire, LightningElement } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getSoftwareFile from '@salesforce/apex/S3FilesDownloadHelper.getSoftwareFile';
import getDownloadUrl from '@salesforce/apex/S3FilesDownloadHelper.getDownloadUrl';

/**
 * Download button for an entitled Software_File__c.
 *
 * Apex checks entitlement and returns a short-lived presigned S3 URL; no AWS credentials
 * are ever sent to the browser, and the file streams directly from S3.
 */
export default class AmazonS3SecureDownload extends LightningElement {
    @api recordId;
    fileKey;
    isUserEntitled = false;
    isLoading = false;

    @wire(CurrentPageReference)
    getCurrentPageReference(currentPageRef) {
        if (currentPageRef) {
            const urlPath =
                currentPageRef.attributes?.recordId || currentPageRef.attributes?.url || window.location.href;
            this.recordId = this.extractRecordId(urlPath);
        }
    }

    extractRecordId(urlPath) {
        // Salesforce record IDs are 15 or 18 alphanumeric characters
        const match = urlPath.match(/[a-zA-Z0-9]{15,18}/);
        return match ? match[0] : null;
    }

    async connectedCallback() {
        await this.fetchFileKey();
    }

    async fetchFileKey() {
        try {
            const softwareFile = await getSoftwareFile({ recordId: this.recordId });
            this.isUserEntitled = !!softwareFile;
            this.fileKey = softwareFile ? softwareFile.File_Key__c : null;
        } catch (error) {
            console.error('Error fetching software file record:', error);
            this.isUserEntitled = false;
            this.fileKey = null;
        }
    }

    async handleDownload() {
        if (!this.fileKey) {
            return;
        }
        this.isLoading = true;
        try {
            // Content-Disposition: attachment (with the file name) is signed into the URL,
            // so the browser downloads the file natively in the background.
            const url = await getDownloadUrl({ recordId: this.recordId });
            const link = document.createElement('a');
            link.href = url;
            link.rel = 'noopener';
            document.body.appendChild(link);
            link.click();
            link.remove();
        } catch (error) {
            console.error('Download error:', error);
        } finally {
            this.isLoading = false;
        }
    }
}