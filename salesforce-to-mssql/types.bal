import ballerina/time;

type Contact record {|
    string Id;
    string FirstName;
    string LastName;
    string Phone;
    string Fax;
    string Email;
    string Title;
    string MailingStreet;
    string MailingCity;
    string MailingState;
    string MailingCountry;
    string OtherPostalCode;
    string IsDeleted;
    string LastModifiedDate;
    string...;
|};

public type DbContact record {|
    readonly string id;
    string name;
    string? phone;
    string? fax;
    string? email;
    string? title;
    string? address;
    int? backupPostalCode;
    boolean isDeleted;
    time:Civil lastModifiedDate;
|};
