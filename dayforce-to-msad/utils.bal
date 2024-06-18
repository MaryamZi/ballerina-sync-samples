import ballerina/log;
import ballerinax/dayforce;

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
