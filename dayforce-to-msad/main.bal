import ballerina/log;
import ballerina/time;
import ballerinax/dayforce;

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

// Update window in hours, used to compute date since which updates have to be retrieved.
configurable int updateWindowInHours = 24;

// Configuration for time to wait for Dayforce job to complete.
configurable decimal dayforceJobCompletionWaitTime = 300;
configurable decimal dayforceJobCompletionWaitInterval = 15;

// MS AD configuration.
configurable string adHostName = ?;
configurable int adPort = ?;
configurable string adDomainName = ?;
configurable string adPassword = ?;
configurable string adOU = "People";

const DAYFORCE_CLIENT_NAMESPACE = "demo.namespace";
const MODIFIED_OR_EFFECTIVE_SINCE_DELTA_DATE = "MODIFIED_OR_EFFECTIVE_SINCE_DELTA_DATE";
const SUCCEEDED = "Succeeded";
const STATUS = "Status";

// The Dayforce connector instance that is used for Dayforce operations.
final dayforce:Client dayforceClient = check initDayforceClient();

function initDayforceClient() returns dayforce:Client|error => new ({
    auth: {
        username: dayforceUsername,
        password: dayforcePassword
    }
}, dayforceServiceUrl);

// The LDAP connector instance that is used for MS AD operations.
final ldap:Client adClient = check initLdapClient();

function initLdapClient() returns ldap:Client|error => new ({
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
            DeltaOption: MODIFIED_OR_EFFECTIVE_SINCE_DELTA_DATE,
            DeltaDate: getLastUpdateDate(),
            PageSize: getEffectivePageSize(dayforcePageSize)
        });
        int:Signed32 backgroundQueueItemId = check getBackgroundQueueItemId(job);

        // Wait, a specific time period, for the job to complete, periodically checking if the job
        // is complete by retrieving the job status.
        dayforce:Payload_Object jobStatus = check waitForDayforceJobCompletion(backgroundQueueItemId);

        anydata status = jobStatus?.Data[STATUS];
        if status != SUCCEEDED {
            fail error("Dayforce to MS AD sync job did not complete within specified time", 
                       backgroundQueueItemId = backgroundQueueItemId,
                       status = status);
        }

        // Retrieve the job ID on successful completion.
        string jobId = check getJobId(jobStatus);
        jobIdOptional = jobId;

        // Retrieve paginated data and update the data on MS AD page by page.
        pageCount = check syncData(jobId, syncFailedEmployees);
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

function getLastUpdateDate() returns string {
    time:Utc utc = time:utcAddSeconds(time:utcNow(), <decimal>updateWindowInHours * 60 * 60 * -1);
    return time:utcToString(utc);
}

// Handle pagination and sync all data.
function syncData(string jobId, string[] syncFailedEmployees) returns int|error {
    int pageCount = 0;
    dayforce:PaginatedPayload_IEnumerable_Employee? employeeDetails =
        check dayforceClient->/[DAYFORCE_CLIENT_NAMESPACE]/v1/GetEmployeeBulkAPI/Data/[jobId];
    DayforceEmployee[]? data;
    while employeeDetails !is () {
        data = employeeDetails?.Data;
        if data is () {
            return pageCount;
        }
        pageCount += 1;

        log:printInfo("Successfully retrieved entries from Dayforce", pageCount = pageCount, entryCount = data.length());
        syncPage(data, syncFailedEmployees);
        
        // Continue to retrieve paginated data.
        employeeDetails = 
            check dayforceClient->/[DAYFORCE_CLIENT_NAMESPACE]/v1/GetEmployeeBulkAPI/Data/[jobId](employeeDetails.Paging);
    }
    return pageCount;
}

// Sync data on one page.
function syncPage(DayforceEmployee[] data, string[] syncFailedEmployees) {
    foreach DayforceEmployee employee in data {
        do {
            // For each employee entry retrieved from Dayforce, transform the entry to the format
            // expected by MS AD.
            ADEmployee adUser = check transform(employee);
            // Update the details on MS AD.
            string distinguishedName = getDistinguishedName(adUser.givenName, adUser?.sn);
            ldap:LdapResponse|ldap:Error modifyRes = adClient->modify(distinguishedName, adUser);
            
            if modifyRes is error {
                fail error("Failed to update user on MS AD", distinguishedName = distinguishedName);
            }
            
            ldap:Status resultStatus = modifyRes.resultCode;
            if resultStatus != ldap:SUCCESS {
                fail error("Received non-success status on MS AD update attempt", 
                           distinguishedName = distinguishedName, status = resultStatus);
            }
        } on fail error err {
            // For each individual failure, either due to transformation failure, update failure, or receiving a non-success
            // status, add the employee number to the list of failed IDs for detailed error reporting.
            string employeeNumber = employee.EmployeeNumber ?: "Unavailable";
            log:printError("Failed to sync data from Dayforce to MS AD for user", err, employeeNumber = employeeNumber);
            syncFailedEmployees.push(employeeNumber);
        }
    }
}

function transform(DayforceEmployee employee) returns ADEmployee|error =>
    let dayforce:PersonAddress? address = getAddress(employee.Addresses?.Items) in
    {
        employeeID: employee.EmployeeNumber,
        userPrincipalName: getUserPrincipalName(employee.SSOAccounts?.Items),
        givenName: check employee.FirstName.ensureType(),
        middleName: employee.MiddleName,
        sn: employee.LastName,
        displayName: employee.DisplayName,
        mobile: employee.HomeOrganization?.ContactCellPhone,
        telephoneNumber: employee.HomeOrganization?.BusinessPhone,
        mail: employee.HomeOrganization?.ContactEmail,
        manager: getManagerDistinguishedName(employee.EmployeeManagers?.Items),
        title: getPositionField(employee.WorkAssignments?.Items, TITLE),
        department: getPositionField(employee.WorkAssignments?.Items, DEPARTMENT),
        company: getPositionField(employee.WorkAssignments?.Items, COMPANY),
        streetAddress: address is () ? () : address.Address1,
        co: address is () ? () : address.Country?.Name,
        st: address is () ? () : address.State?.Name,
        l: getLocality(employee.EmployeeProperties?.Items)
    };

function getUserPrincipalName(dayforce:EmployeeSSOAccount[]? employeeSSOAccountItems) returns string? {
    if employeeSSOAccountItems is () || employeeSSOAccountItems.length() == 0 {
        return ();
    }
    return employeeSSOAccountItems[0].LoginName;
}

function getDistinguishedName(string firstName, string? lastName) returns string =>
    let string name = lastName is () ? firstName : string `${firstName} ${lastName}` in
        string `CN=${name},OU=${adOU},DC=ad,DC=windows`;

enum TitleField {
    TITLE = "title",
    DEPARTMENT = "department",
    COMPANY = "company"
}

function getPositionField(dayforce:EmployeeWorkAssignment[]? employeeWorkAssignmentItems, TitleField fieldName) returns string? {
    dayforce:EmployeeWorkAssignment? item = getPrimaryWorkAssignment(employeeWorkAssignmentItems);
    if item is () {
        return ();
    }

    match fieldName {
        TITLE => {
            return item?.Position?.Job?.ShortName;
        }
        DEPARTMENT => {
            return item?.Position?.Department?.ShortName;
        }
        _ => {
            return item?.Location?.LegalEntity?.LongName;
        }
    }
}

function getPrimaryWorkAssignment(dayforce:EmployeeWorkAssignment[]? employeeWorkAssignmentItems) returns dayforce:EmployeeWorkAssignment? {
    if employeeWorkAssignmentItems is () {
        return ();
    }
    foreach dayforce:EmployeeWorkAssignment item in employeeWorkAssignmentItems {
        if item.IsPrimary == true {
            return item;
        }
    }
    return ();
}

function getManagerDistinguishedName(dayforce:EmployeeManager[]? employeeManagerItems) returns string? {
    if employeeManagerItems is () || employeeManagerItems.length() == 0 {
        return ();
    }

    dayforce:EmployeeManager manager = employeeManagerItems[0];
    string? firstName = manager.ManagerFirstName;
    if firstName is () {
        return ();
    }

    return getDistinguishedName(firstName, manager.ManagerLastName);
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

function getAddress(dayforce:PersonAddress[]? personAddressItems) returns dayforce:PersonAddress? {
    if personAddressItems is () || personAddressItems.length() == 0 {
        return ();
    }
    return personAddressItems[0];
}
