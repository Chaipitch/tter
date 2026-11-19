import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getOverview from '@salesforce/apex/SuggestLocationsPanelController.getOverview';
import startRun from '@salesforce/apex/SuggestLocationsPanelController.startRun';
import getStatus from '@salesforce/apex/SuggestLocationsPanelController.getStatus';

const POLL_INTERVAL_MS = 5000;

/**
 * "Suggest Locations" panel: floats over any page (e.g. the Account list view), either as a utility bar
 * item (mode "utility") or inside the global action modal suggestLocationsGlobalAction (mode "modal").
 * Shows how many oggLocations aren't processed yet, starts the bulk lookup (AccountLocationGeocodeBatch),
 * follows its progress every 5 s, then shows a summary and a toast. Keeps following the run while the
 * user navigates; when opened, it also picks up a run of this user that is still going.
 */
export default class SuggestLocationsPanel extends LightningElement {
    /** "utility" (utility bar, default) or "modal" (global action). Only changes the help text. */
    @api mode = 'utility';

    overview;
    run;        // { jobId, startedAtMs, recordsInRun }
    status;     // LocationLookupRunService.RunStatus
    error;
    loading = true;
    starting = false;
    timer;

    connectedCallback() {
        this.loadOverview();
    }

    disconnectedCallback() {
        this.stopPolling();
    }

    async loadOverview() {
        this.loading = true;
        this.error = undefined;
        try {
            this.overview = await getOverview();
            const running = this.overview.runningJob;
            if (running && !this.run) {
                this.run = { jobId: running.jobId, startedAtMs: running.startedAtMs, recordsInRun: 0 };
                this.status = undefined;
                this.poll();
            }
        } catch (e) {
            this.error = this.errorMessage(e);
        } finally {
            this.loading = false;
        }
    }

    async handleStart() {
        this.starting = true;
        try {
            this.run = await startRun();
            this.status = undefined;
            this.poll();
        } catch (e) {
            this.toast('Could not start the location lookup', this.errorMessage(e), 'error');
        } finally {
            this.starting = false;
        }
    }

    handleRefresh() {
        this.loadOverview();
    }

    handleNewRun() {
        this.stopPolling();
        this.run = undefined;
        this.status = undefined;
        this.loadOverview();
    }

    async poll() {
        this.stopPolling();
        if (!this.run) {
            return;
        }
        try {
            this.status = await getStatus({
                jobId: this.run.jobId,
                startedAtMs: this.run.startedAtMs,
                recordsInRun: this.run.recordsInRun
            });
            if (this.status.finished) {
                this.notifyFinished();
                return;
            }
        } catch (e) {
            this.error = this.errorMessage(e);
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.timer = setTimeout(() => this.poll(), POLL_INTERVAL_MS);
    }

    stopPolling() {
        if (this.timer) {
            clearTimeout(this.timer);
            this.timer = null;
        }
    }

    notifyFinished() {
        const s = this.status;
        let message = `${s.updatedCount} updated (${s.farCount} more than ${this.farDistanceMeters} m from UPWARD's pin), `
            + `${s.remainingCount} still not processed`;
        if (s.batchesFailed > 0) {
            message += `, ${s.batchesFailed} batch(es) failed`;
        }
        this.toast('Location lookup finished', message + '.', s.batchesFailed > 0 ? 'warning' : 'success');
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    errorMessage(e) {
        return (e && e.body && e.body.message) || (e && e.message) || 'Unknown error';
    }

    // ---------------------------------------------------------------- view state

    get enabled() {
        return this.overview && this.overview.enabled;
    }

    get disabledMessage() {
        return this.overview && !this.overview.enabled;
    }

    get showIntro() {
        return this.enabled && !this.run;
    }

    get showRun() {
        return !!this.run;
    }

    get finished() {
        return !!(this.status && this.status.finished);
    }

    get running() {
        return this.showRun && !this.finished;
    }

    get countLabel() {
        if (!this.overview) {
            return '';
        }
        return this.overview.unprocessedCount + (this.overview.moreThanCounted ? '+' : '');
    }

    get startDisabled() {
        return this.starting || !this.overview || this.overview.unprocessedCount === 0;
    }

    get openStreetMap() {
        return this.overview && this.overview.openStreetMap;
    }

    get openStreetMapLimit() {
        return this.overview ? this.overview.openStreetMapLimit : 0;
    }

    get farDistanceMeters() {
        return this.overview ? this.overview.farDistanceMeters : 500;
    }

    get percent() {
        return this.status ? this.status.percent : 0;
    }

    get statusLabel() {
        if (!this.status) {
            return 'Starting…';
        }
        return this.finished ? 'Finished' : 'Running · ' + this.status.status;
    }

    get progressText() {
        const s = this.status;
        if (!s) {
            return '';
        }
        if (s.batchesTotal > 0) {
            return `${s.percent}% · batch ${s.batchesProcessed} of ${s.batchesTotal}, `
                + `about ${s.recordsDoneApprox} of ${s.recordsInRun} record(s)`;
        }
        return s.finished ? '100%' : 'Waiting to start (other background jobs may be running)';
    }

    get isModal() {
        return this.mode === 'modal';
    }

    get backgroundHint() {
        return this.isModal
            ? 'You can close this window: the run continues in the background. Open Suggest Locations again to see its progress.'
            : 'You can keep working and navigate; this panel keeps following the run.';
    }

    get hasFailures() {
        return this.status && this.status.batchesFailed > 0;
    }
}
