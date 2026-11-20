import { api, LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import listFiles from '@salesforce/apex/S3FilesHelper.listFiles';
import getUploadUrl from '@salesforce/apex/S3FilesHelper.getUploadUrl';
import getFileUrl from '@salesforce/apex/S3FilesHelper.getFileUrl';
import deleteFile from '@salesforce/apex/S3FilesHelper.deleteFile';
import createSoftwareRecord from '@salesforce/apex/S3FilesHelper.createSoftwareRecord';
import syncFileDetails from '@salesforce/apex/S3FilesHelper.syncFileDetails';

import { crc32Base64, putToS3, triggerDownload, openInNewTab, toFileRows, errorMessage } from 'c/s3FileService';
import { fileTypesMap } from './utilities';

/**
 * Same as amazonS3Software, and additionally refreshes the Software_File__c record with the
 * details of the file in S3 (key, size, ETag, date) every time the list is loaded.
 *
 * No AWS credentials are ever sent to the browser: Apex authorises the user and returns
 * short-lived presigned URLs, and the file bytes travel directly between the browser and S3.
 */
export default class AmazonS3LoadAndFetchDetails extends LightningElement {
    @api recordId;
    @api allowUploads = false;
    @api allowView = false;
    @api allowDownload = false;
    @api allowDelete = false;

    files = [];
    progress = 0;
    isUploading = false;
    isLoading = false;

    connectedCallback() {
        this.listS3Objects();
    }

    get disable() {
        return this.isUploading;
    }

    async listS3Objects() {
        if (!this.recordId) {
            return;
        }
        this.isLoading = true;
        try {
            this.files = toFileRows(await listFiles({ recordId: this.recordId }), fileTypesMap);
        } catch (error) {
            this.toast('Error loading files', errorMessage(error), 'error');
            return;
        } finally {
            this.isLoading = false;
        }

        if (this.files.length) {
            this.syncRecord();
        }
    }

    /** Writes the S3 file details onto the record. Best effort: viewers without edit access just skip it. */
    async syncRecord() {
        try {
            await syncFileDetails({ recordId: this.recordId });
        } catch (error) {
            console.warn('Could not sync file details onto the record:', errorMessage(error));
        }
    }

    async view(event) {
        const key = event.currentTarget.dataset.key;
        try {
            await openInNewTab(() => getFileUrl({ recordId: this.recordId, key, asAttachment: false }));
        } catch (error) {
            this.toast('Error opening file', errorMessage(error), 'error');
        }
    }

    async download(event) {
        const key = event.currentTarget.dataset.key;
        try {
            triggerDownload(await getFileUrl({ recordId: this.recordId, key, asAttachment: true }));
        } catch (error) {
            this.toast('Error downloading file', errorMessage(error), 'error');
        }
    }

    async upload(event) {
        const files = Array.from(event.target.files || []);
        if (!files.length) {
            return;
        }
        this.isUploading = true;
        try {
            for (const file of files) {
                // eslint-disable-next-line no-await-in-loop
                await this.uploadFile(file);
            }
            this.toast('Success', `${files.length} file(s) uploaded`);
        } catch (error) {
            this.toast('Upload failed', errorMessage(error), 'error');
        } finally {
            this.isUploading = false;
            this.progress = 0;
            this.listS3Objects();
        }
    }

    async uploadFile(file) {
        // Checksum first (0-20% of the bar): S3 requires it for Object Lock buckets, and it is
        // signed into the URL so S3 only accepts this exact content.
        const checksumCrc32 = await crc32Base64(file, (pct) => {
            this.progress = Math.max(1, Math.round(pct * 0.2));
        });
        const { key, url, headers } = await getUploadUrl({ recordId: this.recordId, fileName: file.name, checksumCrc32 });
        const etag = await putToS3(url, file, (pct) => {
            this.progress = 20 + Math.round(pct * 0.8);
        }, headers);
        await createSoftwareRecord({
            fileName: file.name,
            fileKey: key,
            fileSize: file.size,
            etag,
            recId: this.recordId
        });
    }

    async remove(event) {
        const key = event.currentTarget.dataset.key;
        try {
            await deleteFile({ recordId: this.recordId, key });
            this.toast('Success', 'File deleted');
            this.listS3Objects();
        } catch (error) {
            this.toast('Delete failed', errorMessage(error), 'error');
        }
    }

    toast(title = 'Success', message = '', variant = 'success') {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}