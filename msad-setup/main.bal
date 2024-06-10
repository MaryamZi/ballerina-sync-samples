import ballerina/log;
import ballerinax/dayforce;

import nuvindu/ldap;

configurable string adHostName = ?;
configurable int adPort = ?;
configurable string adDomainName = ?;
configurable string adPassword = ?;

configurable string adOU = "People";

final ldap:Client adClient = check new ({
    hostName: adHostName,
    port: adPort,
    domainName: adDomainName,
    password: adPassword
});

public function main() returns error? {
    map<record {}> users = map from dayforce:Employee employee in employees
        let string firstName = check employee.FirstName.ensureType(),
            string? lastName = employee.LastName
        select [
            getDistinguishedName(firstName, lastName),
            check transform(firstName, lastName, employee)
        ];

    foreach string dn in users.keys() {
        ldap:LdapResponse|ldap:Error deleteRes = adClient->delete(dn);
        if deleteRes is error {
            log:printError("Failed to delete user", deleteRes, dn = dn);
        }
    }

    foreach var [dn, user] in users.entries() {
        ldap:LdapResponse|ldap:Error addRes = adClient->add(dn, user);
        if addRes is error {
            log:printError("Failed to add user", addRes, dn = dn);
        }
    }
}

function getDistinguishedName(string firstName, string? lastName) returns string =>
    let string name = lastName is () ? firstName : string `${firstName} ${lastName}` in
        string `CN=${name},OU=${adOU},DC=ad,DC=windows`;

type ADEmployee record {
    string employeeID?;
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
    string objectClass = "user";
    string userAccountControl = "544";
};

function transform(string firstName, string? lastName, dayforce:Employee employee) returns ADEmployee|error =>
    let dayforce:PersonAddress? address = getAddress(employee.Addresses?.Items) in
    <ADEmployee>{
        employeeID: employee.EmployeeNumber,
        userPrincipalName: string `${firstName.toLowerAscii()}${lastName is () ? "" : lastName.toLowerAscii()}@ad.windows`,
        givenName: firstName,
        middleName: employee.MiddleName,
        sn: lastName,
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
