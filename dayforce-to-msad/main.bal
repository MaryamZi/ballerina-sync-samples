import ballerina/lang.runtime;
import ballerina/log;

import bhashinee/dayforce;
import nuvindu/ldap;

configurable string dayforceServiceUrl = ?;
configurable string dayforceUsername = ?;
configurable string dayforcePassword = ?;
configurable decimal dayforceJobCompletionWaitTime = 300;
configurable decimal dayforceJobCompletionWaitInterval = 30;

configurable string adHostName = ?;
configurable int adPort = ?;
configurable string adDomainName = ?;
configurable string adPassword = ?;
configurable string adOU = "People";

const DAYFORCE_CLIENT_NAMESPACE = "demo.namespace";
const MODIFIED_SINCE_DELTA_DATE = "MODIFIED_SINCE_DELTA_DATE";
const SUCCEEDED = "Succeeded";
const STATUS = "Status";

final dayforce:Client dayforceClient = check new ({
    auth: {
        username: dayforceUsername,
        password: dayforcePassword
    }
}, dayforceServiceUrl);

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
        json job = check dayforceClient->/[DAYFORCE_CLIENT_NAMESPACE]/V1/EmployeeExportJobs.post(true, {
            DeltaOption: MODIFIED_SINCE_DELTA_DATE
        });
        int:Signed32 backgroundQueueItemId = check getBackgroundQueueItemId(job);

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
            fail error("Job did not complete within specified time", 
                       backgroundQueueItemId = backgroundQueueItemId,
                       status = status);
        }

        string jobId = check getJobId(jobStatus);
        jobIdOptional = jobId;

        dayforce:Employee[]? data;
        dayforce:PaginatedPayload_IEnumerable_Employee? employeeDetails =
            check dayforceClient->/[DAYFORCE_CLIENT_NAMESPACE]/v1/GetEmployeeBulkAPI/Data/[jobId];

        while employeeDetails !is () {
            data = employeeDetails?.Data;
            if data is () {
                break;
            }
            pageCount += 1;

            foreach dayforce:Employee employee in data {
                do {
                    ADEmployeeUpdate adUser = check transform(employee);
                    ldap:LDAPResponse {resultStatus} = check adClient->modify(getDistinguishedName(adUser), adUser);
                    if resultStatus != ldap:SUCCESS {
                        fail error("Received non-success status on update attempt", status = resultStatus);
                    }
                } on fail error err {
                    string employeeNumber = employee.EmployeeNumber ?: "Unavailable";
                    log:printError("Failed to sync data for user", err, employeeNumber = employeeNumber);
                    syncFailedEmployees.push(employeeNumber);
                }
            }
            employeeDetails = 
                check dayforceClient->/[DAYFORCE_CLIENT_NAMESPACE]/v1/GetEmployeeBulkAPI/Data/[jobId](employeeDetails.Paging);
        }
    } on fail error err {
        log:printError("Failed to sync data", err, syncedPageCount = pageCount, jobId = jobIdOptional, syncFailedEmployees = syncFailedEmployees);
        return err;
    }

    if syncFailedEmployees.length() == 0 {
        log:printInfo("Successfully synced data", syncedPageCount = pageCount, jobId = jobIdOptional);
        return;
    }

    log:printError("Failed to sync some data", syncedPageCount = pageCount, jobId = jobIdOptional, syncFailedEmployees = syncFailedEmployees);
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

public type ADEmployeeUpdate record {
    string employeeId;
    string userPrincipalName?;
    string givenName;
    string? sn?;
    string? company?;
    string? co?;
    string? streetAddress?;
    string? mobile?;
    string displayName?;
    string? middleName?;
    string? extensionAttribute11?;
    string? extensionAttribute10?;
    string? postalCode?;
    string? mail?;
    string? l?;
    string? telephoneNumber?;
    string? department?;
    string? st?;
    string title?;
    string manager?;
};

function transform(dayforce:Employee employee) returns ADEmployeeUpdate|error =>
    let dayforce:EmployeeSSOAccount? employeeSSOAccountItem = getEmployeeSSOAccountItem(employee),
        dayforce:PersonContact[]? personContactItems = employee?.Contacts?.Items,
        dayforce:EmployeeWorkAssignment[]? employeeWorkAssignmentItems = employee?.WorkAssignments?.Items,
        dayforce:PersonAddress? address = getAddress(employee) in
    {
        employeeId: check employee.EmployeeNumber.ensureType(),
        userPrincipalName: employeeSSOAccountItem is () ? () : employeeSSOAccountItem.LoginName,
        givenName: check employee.FirstName.ensureType(),
        middleName: employee.MiddleName,
        sn: employee.LastName,
        displayName: employee.DisplayName,
        mobile: getContactInfo(personContactItems, BUSINESS_MOBILE),
        telephoneNumber: getContactInfo(personContactItems, BUSINESS_PHONE),
        mail: getContactInfo(personContactItems, BUSINESS_EMAIL),
        title: getPositionField(employeeWorkAssignmentItems, TITLE),
        manager: getManager(employee?.EmployeeManagers?.Items),
        department: getPositionField(employeeWorkAssignmentItems, DEPARTMENT),
        company: getPositionField(employeeWorkAssignmentItems, COMPANY),
        streetAddress: address?.Address1,
        co: address?.Country?.Name,
        st: address?.State?.Name,
        l: getLocality(employee?.EmployeeProperties?.Items)
    };

function getEmployeeSSOAccountItem(dayforce:Employee employee) returns dayforce:EmployeeSSOAccount? {
    dayforce:EmployeeSSOAccount[]? employeeSSOAccountItems = employee?.SSOAccounts?.Items;
    if employeeSSOAccountItems is () || employeeSSOAccountItems.length() == 0 {
        return ();
    }
    return employeeSSOAccountItems[0];
}

function getDistinguishedName(ADEmployeeUpdate user) returns string =>
    let string firstName = user.givenName, 
        string? lastName = user?.sn,
        string name = lastName is () ? firstName : string `${firstName} ${lastName}` in
        string `CN=${name},OU=${adOU},DC=ad,DC=windows`;

function getContactInfo(dayforce:PersonContact[]? personContactItems, string xRefCode) returns string? {
    if personContactItems is () {
        return ();
    }

    foreach dayforce:PersonContact item in personContactItems {
        if item?.ContactInformationType?.XRefCode == xRefCode {
            return item.ContactNumber;
        }
    }
    return ();
}

enum BusinessContactDetailsField {
    BUSINESS_MOBILE = "BusinessMobile",
    BUSINESS_PHONE = "BusinessPhone",
    BUSINESS_EMAIL = "BusinessEmail"
}

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

function getAddress(dayforce:Employee employee) returns dayforce:PersonAddress? {
    dayforce:PersonAddress[]? personAddressItems = employee?.Addresses?.Items;
    if personAddressItems is () || personAddressItems.length() == 0 {
        return ();
    }
    return personAddressItems[0];
}
