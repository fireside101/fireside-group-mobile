class ProfileOptions {
  const ProfileOptions({
    this.city = const [],
    this.country = const [],
    this.department = const [],
    this.contractor = const [],
  });

  final List<String> city;
  final List<String> country;
  final List<String> department;
  final List<String> contractor;

  factory ProfileOptions.fromJson(Map<String, dynamic> json) => ProfileOptions(
    city: _strings(json['city']),
    country: _strings(json['country']),
    department: _strings(json['department']),
    contractor: _strings(json['contractor']),
  );
}

class ProfileEditableDetails {
  const ProfileEditableDetails({
    required this.firstName,
    required this.lastName,
    required this.dateOfBirth,
    required this.nationality,
    required this.nationalId,
    required this.department,
    required this.phoneNumber,
    required this.emergencyPhone,
    required this.assignedCity,
    required this.assignedCountry,
    required this.contractor,
    required this.contractorName,
  });

  final String firstName;
  final String lastName;
  final String dateOfBirth;
  final String nationality;
  final String nationalId;
  final String department;
  final String phoneNumber;
  final String emergencyPhone;
  final String assignedCity;
  final String assignedCountry;
  final bool contractor;
  final String contractorName;

  Map<String, dynamic> toJson() => {
    'first_name': firstName,
    'last_name': lastName,
    'date_of_birth': dateOfBirth,
    'nationality': nationality,
    'national_id': nationalId,
    'department': department,
    'phone_number': phoneNumber,
    'emergency_phone': emergencyPhone,
    'assigned_city': assignedCity,
    'assigned_country': assignedCountry,
    'contractor': contractor,
    'contractor_name': contractorName,
  };

  factory ProfileEditableDetails.fromJson(Map<String, dynamic> json) =>
      ProfileEditableDetails(
        firstName: _string(json['first_name']),
        lastName: _string(json['last_name']),
        dateOfBirth: _string(json['date_of_birth']),
        nationality: _string(json['nationality']),
        nationalId: _string(json['national_id']),
        department: _string(json['department']),
        phoneNumber: _string(json['phone_number']),
        emergencyPhone: _string(json['emergency_phone']),
        assignedCity: _string(json['assigned_city']),
        assignedCountry: _string(json['assigned_country']),
        contractor: json['contractor'] == true,
        contractorName: _string(json['contractor_name']),
      );
}

class ProfileField {
  const ProfileField({required this.label, required this.value});

  final String label;
  final String value;

  factory ProfileField.fromJson(Map<String, dynamic> json) => ProfileField(
    label: _string(json['label']),
    value: _string(json['value']),
  );
}

class PersonalDetails {
  const PersonalDetails({
    required this.fullName,
    required this.department,
    required this.fields,
    required this.editable,
  });

  final String fullName;
  final String department;
  final List<ProfileField> fields;
  final ProfileEditableDetails editable;

  factory PersonalDetails.fromJson(Map<String, dynamic> json) =>
      PersonalDetails(
        fullName: _string(json['fullName']),
        department: _string(json['department']),
        fields: (json['fields'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ProfileField.fromJson)
            .toList(),
        editable: ProfileEditableDetails.fromJson(
          (json['editable'] as Map<String, dynamic>?) ?? const {},
        ),
      );
}

class ProfileResponse {
  const ProfileResponse({
    required this.details,
    required this.options,
    required this.avatarUrl,
  });

  final PersonalDetails? details;
  final ProfileOptions options;
  final String avatarUrl;

  factory ProfileResponse.fromJson(Map<String, dynamic> json) =>
      ProfileResponse(
        details: json['details'] is Map<String, dynamic>
            ? PersonalDetails.fromJson(json['details'] as Map<String, dynamic>)
            : null,
        options: ProfileOptions.fromJson(
          (json['options'] as Map<String, dynamic>?) ?? const {},
        ),
        avatarUrl: _string(json['avatarUrl']),
      );
}

String _string(Object? value) => value is String ? value : '';

List<String> _strings(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const [];
