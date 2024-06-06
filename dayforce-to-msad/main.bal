import ballerina/lang.runtime;
import ballerina/log;

import bhashinee/dayforce;
import nuvindu/ldap;

// Specify values that can change by environment and/or run as `configurable`
// variables. These can be overridden via configuration files, environment variables,
// and CLI arguments - https://ballerina.io/learn/provide-values-to-configurable-variables/

// Dayforce configuration.
configurable string dayforceServiceUrl = ?;
configurable string dayforceUsername = ?;
configurable string dayforcePassword = ?;
// Page size for Dayforce pagination.
configurable int dayforcePageSize = 0;
// Configuration for time to wait for Dayforce job to complete.
configurable decimal dayforceJobCompletionWaitTime = 300;
configurable decimal dayforceJobCompletionWaitInterval = 30;

// MS AD configuration.
configurable string adHostName = ?;
configurable int adPort = ?;
configurable string adDomainName = ?;
configurable string adPassword = ?;
configurable string adOU = "People";

const DAYFORCE_CLIENT_NAMESPACE = "demo.namespace";
const MODIFIED_SINCE_DELTA_DATE = "MODIFIED_SINCE_DELTA_DATE";
const SUCCEEDED = "Succeeded";
const STATUS = "Status";

// The Dayforce connector instance that is used for Dayforce operations.
final dayforce:Client dayforceClient = check new ({
    timeout: 120,
    auth: {
        username: dayforceUsername,
        password: dayforcePassword
    }
}, dayforceServiceUrl);

// The LDAP connector instance that is used for MS AD operations.
final ldap:Client adClient = check new ({
    hostName: adHostName,
    port: adPort,
    domainName: adDomainName,
    password: adPassword
});

public function main() returns error? {
    int pageCount = 0;
    string? jobIdOptional = ();
    string[] syncFailedEmployees = [];

    do {
        // Create the Employee export job and retrieve the queue ID.
        json job = check dayforceClient->/[DAYFORCE_CLIENT_NAMESPACE]/V1/EmployeeExportJobs.post(true, {
            DeltaOption: MODIFIED_SINCE_DELTA_DATE,
            PageSize: getEffectivePageSize(dayforcePageSize)
        });
        int:Signed32 backgroundQueueItemId = check getBackgroundQueueItemId(job);

        // Wait, a specific time period, for the job to complete, periodically checking if the job
        // is complete by retrieving the job status.
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

        anydata status = jobStatus?.Data[STATUS];
        if status != SUCCEEDED {
            fail error("Dayforce to MS AD sync job did not complete within specified time", 
                       backgroundQueueItemId = backgroundQueueItemId,
                       status = status);
        }

        // Retrieve the job ID on successful completion.
        string jobId = check getJobId(jobStatus);
        jobIdOptional = jobId;

        DayforceEmployee[]? data;

        // Retrieve paginated data until all the data is retrieved.
        dayforce:PaginatedPayload_IEnumerable_Employee? employeeDetails =
            check dayforceClient->/[DAYFORCE_CLIENT_NAMESPACE]/v1/GetEmployeeBulkAPI/Data/[jobId];

        while employeeDetails !is () {
            data = employeeDetails?.Data;
            if data is () {
                break;
            }
            pageCount += 1;
            log:printInfo("Successfully retrieved entries from Dayforce", pageCount = pageCount, entryCount = data.length());
            foreach DayforceEmployee employee in data {
                do {
                    // For each employee entry retrieved from Dayforce, transform the entry to the format
                    // expected by MS AD.
                    ADEmployee adUser = check transform(employee);
                    // Update the details on MS AD.
                    ldap:LDAPResponse {resultStatus} = check adClient->modify(getDistinguishedName(adUser), adUser);
                    if resultStatus != ldap:SUCCESS {
                        fail error("Received non-success status on MS AD update attempt", status = resultStatus);
                    }
                } on fail error err {
                    // For each individual failure, either due to transformation failure, update failure, or receiving a non-success
                    // status, add the employee number to the list of failed IDs for detailed error reporting.
                    string employeeNumber = employee.EmployeeNumber ?: "Unavailable";
                    log:printError("Failed to sync data from Dayforce to MS AD for user", err, employeeNumber = employeeNumber);
                    syncFailedEmployees.push(employeeNumber);
                }
            }
            // Continue to retrieve pagignated data.
            employeeDetails = 
                check dayforceClient->/[DAYFORCE_CLIENT_NAMESPACE]/v1/GetEmployeeBulkAPI/Data/[jobId](employeeDetails.Paging);
        }
    } on fail error err {
        // Log and return an error if retrieving an entire chunk of data fails.
        log:printError("Failed to sync data from Dayforce to MS AD", err, syncedPageCount = pageCount, 
                        jobId = jobIdOptional, syncFailedEmployees = syncFailedEmployees);
        return err;
    }

    if syncFailedEmployees.length() == 0 {
        log:printInfo("Successfully synced data from Dayforce to MS AD", syncedPageCount = pageCount, jobId = jobIdOptional);
        return;
    }

    log:printError("Failed to sync some data from Dayforce to MS AD", syncedPageCount = pageCount, jobId = jobIdOptional, 
                    syncFailedEmployees = syncFailedEmployees);
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

type DayforceLocation record {
    string ContactCellPhone?;
    string BusinessPhone?;
    string ContactEmail?;
};

// Alternatively, could directly use `dayforce:Employee`, but this would complicate
// the data mapper view with a large number of unnecessary fields.
type DayforceEmployee record {
    string EmployeeNumber?;
    dayforce:AppUserSSOCollection SSOAccounts?;
    string FirstName?;
    string MiddleName?;
    string LastName?;
    string DisplayName?;
    DayforceLocation HomeOrganization?;
    dayforce:EmployeeWorkAssignmentCollection WorkAssignments?;
    dayforce:EmployeeManagerCollection EmployeeManagers?;
    dayforce:PersonAddressCollection Addresses?;
    dayforce:EmployeePropertyValueCollection EmployeeProperties?;
};

type ADEmployee record {|
    string employeeId;
    string userPrincipalName?;
    string givenName;
    string? middleName?;
    string? sn?;
    string displayName?;
    string? mobile?;
    string? telephoneNumber?;
    string? mail?;
    string title?;
    string manager?;
    string? department?;
    string? company?;
    string? streetAddress?;
    string? co?;
    string? st?;
    string? l?;
|};

function transform(DayforceEmployee employee) returns ADEmployee|error =>
    let dayforce:EmployeeSSOAccount? employeeSSOAccountItem = getEmployeeSSOAccountItem(employee),
        DayforceLocation? homeOrganization = employee?.HomeOrganization,
        dayforce:EmployeeWorkAssignment[]? employeeWorkAssignmentItems = employee?.WorkAssignments?.Items,
        dayforce:PersonAddress? address = getAddress(employee) in
    {
        employeeId: check employee.EmployeeNumber.ensureType(),
        userPrincipalName: employeeSSOAccountItem is () ? () : employeeSSOAccountItem.LoginName,
        givenName: check employee.FirstName.ensureType(),
        middleName: employee.MiddleName,
        sn: employee.LastName,
        displayName: employee.DisplayName,
        mobile: homeOrganization is () ? "" : homeOrganization.ContactCellPhone,
        telephoneNumber: homeOrganization is () ? "" : homeOrganization.BusinessPhone,
        mail: homeOrganization is () ? "" : homeOrganization.ContactEmail,
        manager: getManager(employee?.EmployeeManagers?.Items),
        title: getPositionField(employeeWorkAssignmentItems, TITLE),
        department: getPositionField(employeeWorkAssignmentItems, DEPARTMENT),
        company: getPositionField(employeeWorkAssignmentItems, COMPANY),
        streetAddress: address is () ? () : address.Address1,
        co: address is () ? () : address.Country?.Name,
        st: address is () ? () : address.State?.Name,
        l: getLocality(employee?.EmployeeProperties?.Items)
    };

function getEmployeeSSOAccountItem(DayforceEmployee employee) returns dayforce:EmployeeSSOAccount? {
    dayforce:EmployeeSSOAccount[]? employeeSSOAccountItems = employee?.SSOAccounts?.Items;
    if employeeSSOAccountItems is () || employeeSSOAccountItems.length() == 0 {
        return ();
    }
    return employeeSSOAccountItems[0];
}

function getDistinguishedName(ADEmployee user) returns string =>
    let string firstName = user.givenName, 
        string? lastName = user?.sn,
        string name = lastName is () ? firstName : string `${firstName} ${lastName}` in
        string `CN=${name},OU=${adOU},DC=ad,DC=windows`;

enum TitleField {
    TITLE = "title",
    DEPARTMENT = "department",
    COMPANY = "company"
}

function getPositionField(dayforce:EmployeeWorkAssignment[]? employeeWorkAssignmentItems, TitleField fieldName) returns string? {
    if employeeWorkAssignmentItems is () {
        return ();
    }

    foreach dayforce:EmployeeWorkAssignment item in employeeWorkAssignmentItems {
        if item.IsPrimary == true {
            match fieldName {
                TITLE => {
                    return item?.Position?.Job?.ShortName;
                }
                DEPARTMENT => {
                    return item?.Position?.Department?.ShortName;
                }
                COMPANY => {
                    return item?.Location?.LegalEntity?.LongName;
                }
            }
        }
    }
    return ();
}

function getManager(dayforce:EmployeeManager[]? employeeManagerItems) returns string? {
    if employeeManagerItems is () || employeeManagerItems.length() == 0 {
        return ();
    }

    dayforce:EmployeeManager manager = employeeManagerItems[0];
    string? firstName = manager.ManagerFirstName;
    if firstName is () {
        return ();
    }

    string? lastName = manager.ManagerLastName;
    if lastName is () {
        return firstName;
    }

    return string `${firstName} ${lastName}`;
}

function getLocality(dayforce:EmployeePropertyValue[]? employeePropertyValueItems) returns string? {
    if employeePropertyValueItems is () {
        return ();
    }

    foreach dayforce:EmployeePropertyValue item in employeePropertyValueItems {
        if item.EmployeeProperty?.ShortName == "Employee Work Address" {
            return item.OptionValue?.ShortName;
        }
    }
    return ();
}

function getAddress(DayforceEmployee employee) returns dayforce:PersonAddress? {
    dayforce:PersonAddress[]? personAddressItems = employee?.Addresses?.Items;
    if personAddressItems is () || personAddressItems.length() == 0 {
        return ();
    }
    return personAddressItems[0];
}
