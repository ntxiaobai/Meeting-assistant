const QUESTION_PATTERNS = [/\?/, /\b(what|why|how|when|where|which|could you|would you)\b/i];

export function useQuestionTrigger() {
  function isQuestion(text: string): boolean {
    return QUESTION_PATTERNS.some((pattern) => pattern.test(text.trim()));
  }

  return { isQuestion };
}
