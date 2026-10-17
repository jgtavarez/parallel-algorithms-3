class EmailInput {
  const EmailInput({
    required this.email,
    required this.subject,
    required this.message,
  });

  final String email;
  final String subject;
  final String message;

  Map<String, dynamic> toJson() => {
    'email': email,
    'subject': subject,
    'message': message,
  };
}
