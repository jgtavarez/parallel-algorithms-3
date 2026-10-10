class Stats {
  const Stats({required this.totalUsers, required this.totalFiles});

  final int totalUsers;
  final int totalFiles;

  factory Stats.fromJson(Map<String, dynamic> json) =>
      Stats(totalUsers: json['totalUsers'], totalFiles: json['totalFiles']);
}
