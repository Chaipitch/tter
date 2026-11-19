import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import enqueue from '@salesforce/apex/AccountLocationGeocodeAction.enqueue';
import getStatus from '@salesforce/apex/AccountLocationGeocodeAction.getStatus';

const POLL_INTERVAL_MS = 2000;
const MAX_POLLS = 20; // ~40 seconds
const FINISHED = ['Completed', 'Failed', 'Aborted'];

export default class SuggestGoogleLocation extends LightningElement {
    @api recordId;
    isRunning = false;

    @api
    async invoke() {
        if (this.isRunning) {
            return;
        }
        this.isRunning = true;
        try {
            const jobId = await enqueue({ recordId: this.recordId });
            this.toast('Google Maps lookup started', 'Looking up the Account address…', 'info');

            const result = await this.waitForJob(jobId);
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            this.report(result);
        } catch (error) {
            this.toast('Google Maps lookup failed', this.errorMessage(error), 'error');
        } finally {
            this.isRunning = false;
        }
    }

    async waitForJob(jobId) {
        let last = null;
        for (let i = 0; i < MAX_POLLS; i++) {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS));
            last = await getStatus({ jobId, recordId: this.recordId });
            if (FINISHED.includes(last.status)) {
                return last;
            }
        }
        return last; // still queued / processing
    }

    report(result) {
        if (!result || !FINISHED.includes(result.status)) {
            this.toast('Still running',
                'The lookup is taking longer than usual. Refresh the page in a minute.', 'warning');
            return;
        }
        if (result.status !== 'Completed') {
            this.toast('Google Maps lookup failed', result.message || result.status, 'error');
            return;
        }
        if (result.suggestedLatitude == null) {
            this.toast('No suggestion',
                'Google Maps returned no location for this address. Check the Account address.', 'warning');
            return;
        }
        const distance = result.distance == null
            ? 'distance not available (original location is empty)'
            : `${Number(result.distance).toLocaleString()} m from the current location`;
        this.toast('Suggested location updated',
            `${result.suggestedLatitude}, ${result.suggestedLongitude} — ${distance}`, 'success');
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    errorMessage(error) {
        return (error && error.body && error.body.message) || (error && error.message) || 'Unknown error';
    }
}
