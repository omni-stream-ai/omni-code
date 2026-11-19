class WorkspaceComposerReference {
  const WorkspaceComposerReference({
    required this.kind,
    required this.projectId,
    required this.projectName,
    required this.value,
  });

  final String kind, projectId, projectName, value;
  String get token => kind == 'skill'
      ? r'$' + value
      : value.contains(RegExp(r'\s'))
          ? '@"$value"'
          : '@$value';
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'project_id': projectId,
        kind == 'skill' ? 'name' : 'path': value,
      };
  bool isUsedIn(String text) =>
      RegExp(r'(^|\s)' + RegExp.escape(token) + r'(?=\s|$)').hasMatch(text);
}
