import ballerina/lang.runtime;
import ballerina/log;
import ballerinax/dayforce;

function waitForDayforceJobCompletion(int:Signed32 backgroundQueueItemId) returns dayforce:Payload_Object|error {
    dayforce:Payload_Object jobStatus = 
        check dayforceClient->/[DAYFORCE_CLIENT_NAMESPACE]/v1/EmployeeExportJobs/Status/[backgroundQueueItemId];
    int tryCount = <int> (dayforceJobCompletionWaitTime / dayforceJobCompletionWaitInterval);
    int currentTry = 0;
    while jobStatus?.Data[STATUS] != SUCCEEDED && currentTry < tryCount {
        runtime:sleep(dayforceJobCompletionWaitInterval);
        jobStatus = 
            check dayforceClient->/[DAYFORCE_CLIENT_NAMESPACE]/v1/EmployeeExportJobs/Status/[backgroundQueueItemId];
        currentTry += 1;
    }
    return jobStatus;
}

function getEffectivePageSize(int pageSize) returns int:Signed32? {
    if pageSize is int:Signed32 && pageSize > 0 {
        return pageSize;
    }
    log:printWarn("Ignoring invalid page size", pageSize = pageSize);
    return ();
}

function getBackgroundQueueItemId(json job) returns int:Signed32|error {
    string jobStatus = check job.Data.JobStatus;
    string[] split = re `Status/`.split(jobStatus);
    return int:fromString(split[split.length() - 1]).ensureType();
}

function getJobId(dayforce:Payload_Object jobStatus) returns string|error {
    string results = check jobStatus.Data["Results"].ensureType();
    string[] split = re `EmployeeExportJobs/Data/`.split(results);
    return split[split.length() - 1];
}
