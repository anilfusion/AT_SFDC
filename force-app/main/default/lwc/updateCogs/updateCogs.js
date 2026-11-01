import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import { NavigationMixin } from "lightning/navigation";


import getStatus from '@salesforce/apex/UpdateCogsController.getStatus';
import doUpdate from '@salesforce/apex/UpdateCogsController.doUpdate';

export default class UpdateCogs extends NavigationMixin(LightningElement) {

    batchCurrentStatus;
    pendingProcessing;
    failedProcessing;
    running;
    disableButton = false;

    connectedCallback() {
        this.doRefresh();
    }

    async doRefresh() {
        await getStatus().then(result => {
            if(result) {
                this.disableButton = result.isJobRunning == 'true';
                this.batchCurrentStatus = result.jobStatus;
                this.pendingProcessing = result.pendingCount + ' Pending Processing';
                this.failedProcessing = result.failedCount + ' Failed Processing';
                this.running = result.runningCount + ' Processing';
            }
        })
    }

    async doCogsUpdate(event){
        const refreshResult = this.doRefresh();

        if(this.disableButton == true){
            const jobCompletionWaitResult = await LightningConfirm.open({
                message: 'Another job is currently running. Please wait for the job to complete to request another job execution. Click on Ok to view the list of Apex Jobs.',
                label: 'Initiate COGS Update',
                theme: 'error',
            });

            if(jobCompletionWaitResult) {

            }
        } else {
            const result = await LightningConfirm.open({
                message: 'Please confirm if you would like to initiate the COGS update job?',
                label: 'Initiate COGS Update',
                theme: 'warning',
            });
            console.log('confirm result', result);

            if(result) {
                doUpdate().then(result => {
                    const event = new ShowToastEvent({
                        title: 'Success!',
                        message: 'COGS update process has been initited.',
                        variant: 'success', // Options: info, success, warning, error
                        mode: 'dismissable' // Options: dismissible, sticky, pester
                    });
                    this.dispatchEvent(event);
                }).catch(error => {
                    const event = new ShowToastEvent({
                        title: 'Error!',
                        message: 'Something went wrong when trying to initiate the COGS update process. Please check the System Logs.',
                        variant: 'success', // Options: info, success, warning, error
                        mode: 'dismissable' // Options: dismissible, sticky, pester
                    });
                    this.dispatchEvent(event);
                });
            }
        }
    }

    viewPending() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'COGSUpdateStagingRecord__c',
                actionName: 'list'
            },
            state: {
                filterName: 'PendingProcessing'
            }
        });
    }

    viewFailed() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'COGSUpdateStagingRecord__c',
                actionName: 'list'
            },
            state: {
                filterName: 'FailedProcessing'
            }
        });
    }

}