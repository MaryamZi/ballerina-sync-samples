import bhashinee/dayforce;

type DayforceLocation record {
    string ContactCellPhone?;
    string BusinessPhone?;
    string ContactEmail?;
};

// Record representing data from Dayforce.
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

// Record representing data on MS AD.
type ADEmployee record {|
    string employeeID;
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
