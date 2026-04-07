const mcpApprovalHeader = 'Approve app tool call?';
const mcpApprovalApproveOnce = 'Approve Once';
const mcpApprovalApproveSession = 'Approve this Session';
const mcpApprovalDeny = 'Deny';
const mcpApprovalCancel = 'Cancel';
const _internalToolNameKey = '_ccpocketToolName';

Map<String, dynamic>? firstRequestUserInputQuestion(
  Map<String, dynamic> input,
) {
  final questions = input['questions'];
  if (questions is! List || questions.isEmpty) return null;
  final first = questions.first;
  return first is Map<String, dynamic>
      ? first
      : Map<String, dynamic>.from(first as Map);
}

List<String> requestUserInputOptionLabels(Map<String, dynamic> input) {
  final firstQuestion = firstRequestUserInputQuestion(input);
  final options = firstQuestion?['options'];
  if (options is! List) return const [];
  return options
      .whereType<Map>()
      .map((option) => option['label'])
      .whereType<String>()
      .toList(growable: false);
}

String? requestUserInputHeader(Map<String, dynamic> input) {
  return firstRequestUserInputQuestion(input)?['header'] as String?;
}

String? requestUserInputQuestionText(Map<String, dynamic> input) {
  return firstRequestUserInputQuestion(input)?['question'] as String?;
}

String? requestUserInputToolName(Map<String, dynamic> input) {
  return input[_internalToolNameKey] as String?;
}

Map<String, dynamic> withRequestUserInputToolName(
  Map<String, dynamic> input,
  String toolName,
) {
  return {...input, _internalToolNameKey: toolName};
}

bool isMcpApprovalRequestUserInput(Map<String, dynamic> input) {
  if (requestUserInputHeader(input) != mcpApprovalHeader) return false;
  final labels = requestUserInputOptionLabels(input).toSet();
  return labels.contains(mcpApprovalApproveOnce) &&
      labels.contains(mcpApprovalDeny) &&
      labels.contains(mcpApprovalCancel);
}
