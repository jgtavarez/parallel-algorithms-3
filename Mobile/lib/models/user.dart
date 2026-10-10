class User {
  const User({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.photo,
    required this.createdAt,
  });

  final int id;
  final String firstName;
  final String lastName;
  final String email;
  final String? photo;
  final DateTime createdAt;

  String get fullName => '$firstName $lastName';

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'],
    firstName: json['firstName'],
    lastName: json['lastName'],
    email: json['email'],
    photo: json['photo'],
    createdAt: DateTime.parse(json['createdAt']),
  );
}

class UserInput {
  const UserInput({
    required this.firstName,
    required this.lastName,
    required this.email,
    this.password,
  });

  final String firstName;
  final String lastName;
  final String email;
  final String? password;

  Map<String, dynamic> toJson() => {
    'firstName': firstName,
    'lastName': lastName,
    'email': email,
    if (password != null && password!.isNotEmpty) 'password': password,
  };
}
